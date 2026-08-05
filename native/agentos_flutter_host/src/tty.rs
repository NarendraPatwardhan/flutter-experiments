//! Tick, input, output drain, status.

use host::TickState;

use crate::buf::{fill_buf, AosBuf};
use crate::error::{clear_error, set_error};
use crate::table::{drain_arc, with_host_mut, with_vm};

#[repr(C)]
pub struct AosVmStatus {
    pub size: usize,
    pub bytes_written: u64,
    pub exit_code: i32,
    pub at_prompt: i32,
    pub workers: u32,
    pub has_worker_entry: i32,
    pub inflight_egress: u32,
    pub pending_commits: u32,
}

fn tick_state(s: TickState) -> i32 {
    match s {
        TickState::Runnable => 0,
        TickState::Waiting => 1,
        TickState::Exited => 2,
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_tick(vm: u64, out_state: *mut i32) -> i32 {
    clear_error();
    match with_host_mut(vm, |mut host| {
        host.tick()
            .map(tick_state)
            .map_err(|e| format!("tick failed: {e:#}"))
    }) {
        Ok(state) => {
            if !out_state.is_null() {
                *out_state = state;
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
pub unsafe extern "C" fn aos_vm_tick_n(vm: u64, n: u32, out_state: *mut i32) -> i32 {
    clear_error();
    match with_host_mut(vm, |mut host| {
        let mut last = 1i32; // waiting default
        for _ in 0..n {
            last = host
                .tick()
                .map(tick_state)
                .map_err(|e| format!("tick failed: {e:#}"))?;
            if last != 0 {
                break;
            }
        }
        Ok(last)
    }) {
        Ok(state) => {
            if !out_state.is_null() {
                *out_state = state;
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
pub unsafe extern "C" fn aos_vm_send_input(vm: u64, data: *const u8, len: usize) -> i32 {
    clear_error();
    let bytes = if len == 0 {
        &[][..]
    } else {
        if data.is_null() {
            set_error("aos_vm_send_input: null data");
            return -1;
        }
        std::slice::from_raw_parts(data, len)
    };
    match with_host_mut(vm, |mut host| {
        host.send_input(bytes)
            .map_err(|e| format!("send_input failed: {e:#}"))
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_take_output(vm: u64, buf: *mut u8, cap: usize) -> i32 {
    clear_error();
    match with_vm(vm, |entry| {
        // Drain combined primary out (legacy).
        let mut data = drain_arc(&entry.out);
        // Also fold stream sinks if primary empty path used tees that only fill streams.
        if data.is_empty() {
            data.extend(drain_arc(&entry.out_stdout));
            data.extend(drain_arc(&entry.out_stderr));
            data.extend(drain_arc(&entry.out_log));
        } else {
            // Keep stream buffers in sync when combined was used.
            let _ = drain_arc(&entry.out_stdout);
            let _ = drain_arc(&entry.out_stderr);
            let _ = drain_arc(&entry.out_log);
        }
        Ok(data)
    }) {
        Ok(data) => {
            if cap == 0 || buf.is_null() {
                return data.len() as i32;
            }
            let n = data.len().min(cap);
            if n > 0 {
                std::ptr::copy_nonoverlapping(data.as_ptr(), buf, n);
            }
            // Put remainder back into out if truncated.
            if data.len() > n {
                if let Ok(entry) = with_vm(vm, |e| Ok(e.out.clone())) {
                    if let Ok(mut g) = entry.lock() {
                        let rest = &data[n..];
                        g.splice(0..0, rest.iter().copied());
                    }
                }
            }
            n as i32
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_take_output_ex(vm: u64, stream_mask: i32, out: *mut AosBuf) -> i32 {
    clear_error();
    if out.is_null() {
        set_error("aos_vm_take_output_ex: null out");
        return -1;
    }
    match with_vm(vm, |entry| {
        let mut data = Vec::new();
        if stream_mask & 1 != 0 {
            data.extend(drain_arc(&entry.out_stdout));
        }
        if stream_mask & 2 != 0 {
            data.extend(drain_arc(&entry.out_stderr));
        }
        if stream_mask & 4 != 0 {
            data.extend(drain_arc(&entry.out_log));
        }
        if stream_mask == 0 {
            data = drain_arc(&entry.out);
        }
        Ok(data)
    }) {
        Ok(data) => fill_buf(out, &data),
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_status(vm: u64, out: *mut AosVmStatus) -> i32 {
    clear_error();
    if out.is_null() {
        set_error("aos_vm_status: null out");
        return -1;
    }
    match with_host_mut(vm, |mut host| {
        let exit = host.exit_code();
        let inflight = host.inflight_egress().unwrap_or(0);
        let pending = host.pending_commits().unwrap_or(0);
        Ok((
            host.bytes_written(),
            exit,
            host.at_prompt(),
            host.workers(),
            host.has_worker_entry(),
            inflight,
            pending,
        ))
    }) {
        Ok((bw, exit, prompt, workers, has_we, inflight, pending)) => {
            let o = &mut *out;
            o.bytes_written = bw;
            o.exit_code = exit.unwrap_or(i32::MIN);
            o.at_prompt = if prompt { 1 } else { 0 };
            o.workers = workers.max(0) as u32;
            o.has_worker_entry = if has_we { 1 } else { 0 };
            o.inflight_egress = inflight.max(0) as u32;
            o.pending_commits = pending.max(0) as u32;
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}
