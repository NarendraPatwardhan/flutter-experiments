//! exec / run / jobs / autocomplete.

use std::collections::BTreeMap;
use std::ffi::CStr;
use std::os::raw::c_char;

use host::{AutocompleteOptions, ExecOptions};

use crate::buf::{copy_out, fill_buf, parse_env_blob, AosBuf};
use crate::error::{clear_error, cstr_to_str, set_error};
use crate::table::with_host_mut;

#[repr(C)]
pub struct AosExecOpts {
    pub size: usize,
    pub cwd: *const c_char,
    pub env_blob: *const u8,
    pub env_blob_len: usize,
    pub stdin_data: *const u8,
    pub stdin_len: usize,
    pub max_ticks: u64,
}

unsafe fn read_exec_opts(opts: *const AosExecOpts) -> Result<(ExecOptions, usize), String> {
    let mut eo = ExecOptions::default();
    let mut max_ticks = 5_000_000usize;
    if opts.is_null() {
        return Ok((eo, max_ticks));
    }
    let o = &*opts;
    if !o.cwd.is_null() {
        let s = cstr_to_str(o.cwd).map_err(|_| "cwd not utf8".to_string())?;
        if !s.is_empty() {
            eo.cwd = Some(s.to_string());
        }
    }
    if o.env_blob_len > 0 {
        if o.env_blob.is_null() {
            return Err("env_blob_len > 0 but null".into());
        }
        let blob = std::slice::from_raw_parts(o.env_blob, o.env_blob_len);
        let pairs = parse_env_blob(blob)?;
        let mut map = BTreeMap::new();
        for (k, v) in pairs {
            map.insert(k, v);
        }
        eo.env = map;
    }
    if o.stdin_len > 0 {
        if o.stdin_data.is_null() {
            return Err("stdin_len > 0 but null".into());
        }
        eo.stdin = Some(std::slice::from_raw_parts(o.stdin_data, o.stdin_len).to_vec());
    }
    if o.max_ticks != 0 {
        max_ticks = usize::try_from(o.max_ticks).map_err(|_| "max_ticks too large".to_string())?;
    }
    Ok((eo, max_ticks))
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_exec(
    vm: u64,
    cmd: *const c_char,
    max_ticks: u64,
    stdout_buf: *mut u8,
    stdout_cap: usize,
    stdout_len: *mut usize,
    stderr_buf: *mut u8,
    stderr_cap: usize,
    stderr_len: *mut usize,
    out_exit: *mut i32,
) -> i32 {
    clear_error();
    if vm == 0 || cmd.is_null() {
        set_error("aos_vm_exec: invalid args");
        return -1;
    }
    let cmd = match CStr::from_ptr(cmd).to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("aos_vm_exec: cmd is not UTF-8");
            return -1;
        }
    };
    let ticks = if max_ticks == 0 {
        5_000_000usize
    } else {
        match usize::try_from(max_ticks) {
            Ok(t) => t,
            Err(_) => {
                set_error("aos_vm_exec: max_ticks too large");
                return -1;
            }
        }
    };
    match with_host_mut(vm, |mut host| {
        host.exec(cmd, ticks, ExecOptions::default())
            .map_err(|e| format!("exec failed: {e:#}"))
    }) {
        Ok(result) => {
            copy_out(&result.stdout, stdout_buf, stdout_cap, stdout_len);
            copy_out(&result.stderr, stderr_buf, stderr_cap, stderr_len);
            if !out_exit.is_null() {
                *out_exit = result.exit_code;
            }
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_exec_ex(
    vm: u64,
    cmd: *const c_char,
    opts: *const AosExecOpts,
    stdout_b: *mut AosBuf,
    stderr_b: *mut AosBuf,
    out_exit: *mut i32,
) -> i32 {
    clear_error();
    if vm == 0 || cmd.is_null() {
        set_error("aos_vm_exec_ex: invalid args");
        return -1;
    }
    let cmd = match cstr_to_str(cmd) {
        Ok(s) => s,
        Err(()) => {
            set_error("aos_vm_exec_ex: cmd not utf8");
            return -1;
        }
    };
    let (eo, ticks) = match read_exec_opts(opts) {
        Ok(v) => v,
        Err(e) => {
            set_error(e);
            return -1;
        }
    };
    match with_host_mut(vm, |mut host| {
        host.exec(cmd, ticks, eo)
            .map_err(|e| format!("exec failed: {e:#}"))
    }) {
        Ok(result) => {
            if !stdout_b.is_null() {
                let _ = fill_buf(stdout_b, &result.stdout);
            }
            if !stderr_b.is_null() {
                let _ = fill_buf(stderr_b, &result.stderr);
            }
            if !out_exit.is_null() {
                *out_exit = result.exit_code;
            }
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_run(
    vm: u64,
    program: *const c_char,
    argv: *const *const c_char,
    argc: usize,
    opts: *const AosExecOpts,
    stdout_b: *mut AosBuf,
    stderr_b: *mut AosBuf,
    out_exit: *mut i32,
) -> i32 {
    clear_error();
    if vm == 0 || program.is_null() {
        set_error("aos_vm_run: invalid args");
        return -1;
    }
    let program = match cstr_to_str(program) {
        Ok(s) => s.to_string(),
        Err(()) => {
            set_error("aos_vm_run: program not utf8");
            return -1;
        }
    };
    let mut args = Vec::new();
    if argc > 0 {
        if argv.is_null() {
            set_error("aos_vm_run: argv null");
            return -1;
        }
        for i in 0..argc {
            let p = *argv.add(i);
            if p.is_null() {
                set_error("aos_vm_run: argv element null");
                return -1;
            }
            match cstr_to_str(p) {
                Ok(s) => args.push(s.to_string()),
                Err(()) => {
                    set_error("aos_vm_run: argv not utf8");
                    return -1;
                }
            }
        }
    }
    let (eo, ticks) = match read_exec_opts(opts) {
        Ok(v) => v,
        Err(e) => {
            set_error(e);
            return -1;
        }
    };
    match with_host_mut(vm, |mut host| {
        host.run(&program, &args, ticks, eo)
            .map_err(|e| format!("run failed: {e:#}"))
    }) {
        Ok(result) => {
            if !stdout_b.is_null() {
                let _ = fill_buf(stdout_b, &result.stdout);
            }
            if !stderr_b.is_null() {
                let _ = fill_buf(stderr_b, &result.stderr);
            }
            if !out_exit.is_null() {
                *out_exit = result.exit_code;
            }
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_exec_start(
    vm: u64,
    cmd: *const c_char,
    opts: *const AosExecOpts,
    out_job: *mut i64,
) -> i32 {
    clear_error();
    if vm == 0 || cmd.is_null() || out_job.is_null() {
        set_error("aos_vm_exec_start: invalid args");
        return -1;
    }
    let cmd = match cstr_to_str(cmd) {
        Ok(s) => s,
        Err(()) => {
            set_error("cmd not utf8");
            return -1;
        }
    };
    let (eo, _) = match read_exec_opts(opts) {
        Ok(v) => v,
        Err(e) => {
            set_error(e);
            return -1;
        }
    };
    match with_host_mut(vm, |mut host| {
        host.exec_start(cmd, eo)
            .map_err(|e| format!("exec_start failed: {e:#}"))
    }) {
        Ok(job) => {
            *out_job = job as i64;
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_run_start(
    vm: u64,
    program: *const c_char,
    argv: *const *const c_char,
    argc: usize,
    opts: *const AosExecOpts,
    out_job: *mut i64,
) -> i32 {
    clear_error();
    if vm == 0 || program.is_null() || out_job.is_null() {
        set_error("aos_vm_run_start: invalid args");
        return -1;
    }
    let program = match cstr_to_str(program) {
        Ok(s) => s.to_string(),
        Err(()) => {
            set_error("program not utf8");
            return -1;
        }
    };
    let mut args = Vec::new();
    if argc > 0 {
        if argv.is_null() {
            set_error("argv null");
            return -1;
        }
        for i in 0..argc {
            let p = *argv.add(i);
            if p.is_null() {
                set_error("argv element null");
                return -1;
            }
            match cstr_to_str(p) {
                Ok(s) => args.push(s.to_string()),
                Err(()) => {
                    set_error("argv not utf8");
                    return -1;
                }
            }
        }
    }
    let (eo, _) = match read_exec_opts(opts) {
        Ok(v) => v,
        Err(e) => {
            set_error(e);
            return -1;
        }
    };
    match with_host_mut(vm, |mut host| {
        host.run_start(&program, &args, eo)
            .map_err(|e| format!("run_start failed: {e:#}"))
    }) {
        Ok(job) => {
            *out_job = job as i64;
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_exec_poll(
    vm: u64,
    job: i64,
    out_done: *mut i32,
    out_exit: *mut i32,
    stdout_b: *mut AosBuf,
    stderr_b: *mut AosBuf,
) -> i32 {
    clear_error();
    if vm == 0 || job <= 0 {
        set_error("aos_vm_exec_poll: invalid args");
        return -1;
    }
    match with_host_mut(vm, |mut host| {
        host.exec_poll(job as i32)
            .map_err(|e| format!("exec_poll failed: {e:#}"))
    }) {
        Ok(None) => {
            if !out_done.is_null() {
                *out_done = 0;
            }
            0
        }
        Ok(Some(result)) => {
            if !out_done.is_null() {
                *out_done = 1;
            }
            if !out_exit.is_null() {
                *out_exit = result.exit_code;
            }
            if !stdout_b.is_null() {
                let _ = fill_buf(stdout_b, &result.stdout);
            }
            if !stderr_b.is_null() {
                let _ = fill_buf(stderr_b, &result.stderr);
            }
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_exec_stdout_peek(vm: u64, job: i64, out: *mut AosBuf) -> i32 {
    clear_error();
    if vm == 0 || job <= 0 || out.is_null() {
        set_error("aos_vm_exec_stdout_peek: invalid args");
        return -1;
    }
    match with_host_mut(vm, |mut host| {
        host.exec_stdout_peek(job as i32)
            .map_err(|e| format!("exec_stdout_peek failed: {e:#}"))
    }) {
        Ok(data) => fill_buf(out, &data),
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_exec_cancel(vm: u64, job: i64) -> i32 {
    clear_error();
    if vm == 0 || job <= 0 {
        set_error("aos_vm_exec_cancel: invalid args");
        return -1;
    }
    match with_host_mut(vm, |mut host| {
        host.exec_cancel(job as i32)
            .map_err(|e| format!("exec_cancel failed: {e:#}"))
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_autocomplete(
    vm: u64,
    source: *const c_char,
    cursor_byte: usize,
    opts: *const AosExecOpts,
    out_encoded: *mut AosBuf,
) -> i32 {
    clear_error();
    if vm == 0 || source.is_null() || out_encoded.is_null() {
        set_error("aos_vm_autocomplete: invalid args");
        return -1;
    }
    let source = match cstr_to_str(source) {
        Ok(s) => s.as_bytes(),
        Err(()) => {
            set_error("source not utf8");
            return -1;
        }
    };
    let (eo, _) = match read_exec_opts(opts) {
        Ok(v) => v,
        Err(e) => {
            set_error(e);
            return -1;
        }
    };
    let mut ao = AutocompleteOptions::default();
    ao.cwd = eo.cwd;
    ao.env = eo.env;
    match with_host_mut(vm, |mut host| {
        host.autocomplete(source, cursor_byte as u32, ao)
            .map_err(|e| format!("autocomplete failed: {e:#}"))
    }) {
        Ok(r) => {
            // Encode as JSON-like simple text for Dart.
            let mut s = format!(
                "{{\"replace_start\":{},\"replace_end\":{},\"common_prefix\":{:?},\"truncated\":{},\"items\":[",
                r.replace_start, r.replace_end, r.common_prefix, r.truncated
            );
            for (i, it) in r.items.iter().enumerate() {
                if i > 0 {
                    s.push(',');
                }
                s.push_str(&format!(
                    "{{\"label\":{:?},\"value\":{:?},\"kind\":{:?}}}",
                    it.label, it.value, it.kind
                ));
            }
            s.push_str("]}");
            fill_buf(out_encoded, s.as_bytes())
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}
