//! Host FS control + svc_call.

use std::os::raw::c_char;

use crate::buf::{fill_buf, AosBuf};
use crate::error::{clear_error, cstr_to_str, set_error};
use crate::table::with_host_mut;

#[repr(C)]
pub struct AosStat {
    pub size: u64,
    pub is_dir: i32,
    pub is_symlink: i32,
    pub nlink: u32,
    pub mode: u32,
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_svc_call(
    vm: u64,
    service: *const c_char,
    req: *const u8,
    req_len: usize,
    out_status: *mut i32,
    out_body: *mut AosBuf,
) -> i32 {
    clear_error();
    if vm == 0 || service.is_null() {
        set_error("aos_vm_svc_call: invalid args");
        return -1;
    }
    let service = match cstr_to_str(service) {
        Ok(s) => s,
        Err(()) => {
            set_error("service not utf8");
            return -1;
        }
    };
    let body = if req_len == 0 || req.is_null() {
        &[][..]
    } else {
        std::slice::from_raw_parts(req, req_len)
    };
    match with_host_mut(vm, |mut host| {
        host.service_call(service, body)
            .map_err(|e| format!("svc_call failed: {e:#}"))
    }) {
        Ok(r) => {
            if !out_status.is_null() {
                *out_status = r.status;
            }
            if !out_body.is_null() {
                let _ = fill_buf(out_body, &r.body);
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
pub unsafe extern "C" fn aos_vm_read_file(vm: u64, path: *const c_char, out: *mut AosBuf) -> i32 {
    clear_error();
    if vm == 0 || path.is_null() || out.is_null() {
        set_error("aos_vm_read_file: invalid args");
        return -1;
    }
    let path = match cstr_to_str(path) {
        Ok(s) => s,
        Err(()) => {
            set_error("path not utf8");
            return -1;
        }
    };
    match with_host_mut(vm, |mut host| {
        host.read_file(path)
            .map_err(|e| format!("read_file failed: {e:#}"))
    }) {
        Ok(data) => fill_buf(out, &data),
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_write_file(
    vm: u64,
    path: *const c_char,
    data: *const u8,
    len: usize,
) -> i32 {
    clear_error();
    if vm == 0 || path.is_null() {
        set_error("aos_vm_write_file: invalid args");
        return -1;
    }
    let path = match cstr_to_str(path) {
        Ok(s) => s,
        Err(()) => {
            set_error("path not utf8");
            return -1;
        }
    };
    let bytes = if len == 0 || data.is_null() {
        &[][..]
    } else {
        std::slice::from_raw_parts(data, len)
    };
    match with_host_mut(vm, |mut host| {
        host.write_file(path, bytes)
            .map_err(|e| format!("write_file failed: {e:#}"))
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_readdir(
    vm: u64,
    path: *const c_char,
    out_encoded: *mut AosBuf,
) -> i32 {
    clear_error();
    if vm == 0 || path.is_null() || out_encoded.is_null() {
        set_error("aos_vm_readdir: invalid args");
        return -1;
    }
    let path = match cstr_to_str(path) {
        Ok(s) => s,
        Err(()) => {
            set_error("path not utf8");
            return -1;
        }
    };
    match with_host_mut(vm, |mut host| {
        host.readdir(path)
            .map_err(|e| format!("readdir failed: {e:#}"))
    }) {
        Ok(entries) => {
            let mut s = String::from("[");
            for (i, e) in entries.iter().enumerate() {
                if i > 0 {
                    s.push(',');
                }
                let ty = if e.is_dir {
                    "directory"
                } else if e.is_symlink {
                    "symlink"
                } else {
                    "file"
                };
                s.push_str(&format!(
                    "{{\"name\":{:?},\"type\":{:?}}}",
                    e.name, ty
                ));
            }
            s.push(']');
            fill_buf(out_encoded, s.as_bytes())
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_stat(vm: u64, path: *const c_char, out: *mut AosStat) -> i32 {
    clear_error();
    if vm == 0 || path.is_null() || out.is_null() {
        set_error("aos_vm_stat: invalid args");
        return -1;
    }
    let path = match cstr_to_str(path) {
        Ok(s) => s,
        Err(()) => {
            set_error("path not utf8");
            return -1;
        }
    };
    match with_host_mut(vm, |mut host| {
        host.stat(path).map_err(|e| format!("stat failed: {e:#}"))
    }) {
        Ok(st) => {
            let o = &mut *out;
            o.size = st.size;
            o.is_dir = if st.is_dir { 1 } else { 0 };
            o.is_symlink = if st.is_symlink { 1 } else { 0 };
            o.nlink = st.nlink;
            o.mode = st.mode;
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_readlink(vm: u64, path: *const c_char, out: *mut AosBuf) -> i32 {
    clear_error();
    if vm == 0 || path.is_null() || out.is_null() {
        set_error("aos_vm_readlink: invalid args");
        return -1;
    }
    let path = match cstr_to_str(path) {
        Ok(s) => s,
        Err(()) => {
            set_error("path not utf8");
            return -1;
        }
    };
    match with_host_mut(vm, |mut host| {
        host.readlink(path)
            .map_err(|e| format!("readlink failed: {e:#}"))
    }) {
        Ok(s) => fill_buf(out, s.as_bytes()),
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

macro_rules! path_void {
    ($name:ident, $method:ident, $err:expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $name(vm: u64, path: *const c_char) -> i32 {
            clear_error();
            if vm == 0 || path.is_null() {
                set_error(concat!(stringify!($name), ": invalid args"));
                return -1;
            }
            let path = match cstr_to_str(path) {
                Ok(s) => s,
                Err(()) => {
                    set_error("path not utf8");
                    return -1;
                }
            };
            match with_host_mut(vm, |mut host| {
                host.$method(path).map_err(|e| format!("{}: {e:#}", $err))
            }) {
                Ok(()) => 0,
                Err(e) => {
                    set_error(e);
                    -1
                }
            }
        }
    };
}

path_void!(aos_vm_mkdir, mkdir, "mkdir failed");
path_void!(aos_vm_unlink, unlink, "unlink failed");
path_void!(aos_vm_unmount, unmount, "unmount failed");

#[no_mangle]
pub unsafe extern "C" fn aos_vm_chmod(vm: u64, path: *const c_char, mode: u32) -> i32 {
    clear_error();
    if vm == 0 || path.is_null() {
        set_error("aos_vm_chmod: invalid args");
        return -1;
    }
    let path = match cstr_to_str(path) {
        Ok(s) => s,
        Err(()) => {
            set_error("path not utf8");
            return -1;
        }
    };
    match with_host_mut(vm, |mut host| {
        host.chmod(path, mode)
            .map_err(|e| format!("chmod failed: {e:#}"))
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_symlink(
    vm: u64,
    target: *const c_char,
    link_path: *const c_char,
) -> i32 {
    clear_error();
    if vm == 0 || target.is_null() || link_path.is_null() {
        set_error("aos_vm_symlink: invalid args");
        return -1;
    }
    let target = match cstr_to_str(target) {
        Ok(s) => s,
        Err(()) => {
            set_error("target not utf8");
            return -1;
        }
    };
    let link_path = match cstr_to_str(link_path) {
        Ok(s) => s,
        Err(()) => {
            set_error("link not utf8");
            return -1;
        }
    };
    match with_host_mut(vm, |mut host| {
        host.symlink(target, link_path)
            .map_err(|e| format!("symlink failed: {e:#}"))
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_mount(vm: u64, path: *const c_char, read_only: i32) -> i32 {
    clear_error();
    if vm == 0 || path.is_null() {
        set_error("aos_vm_mount: invalid args");
        return -1;
    }
    let path = match cstr_to_str(path) {
        Ok(s) => s,
        Err(()) => {
            set_error("path not utf8");
            return -1;
        }
    };
    match with_host_mut(vm, |mut host| {
        host.mount(path, read_only != 0)
            .map_err(|e| format!("mount failed: {e:#}"))
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}
