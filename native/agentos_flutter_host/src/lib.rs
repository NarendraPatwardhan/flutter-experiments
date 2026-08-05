//! Product C ABI over AgentOS `host::KernelHost` (wasmtime).
//! Mirrors the *role* of the Elixir NIF: thin wrapper, not a second host.
//! See docs/native-host-ffi.md.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use host::{ExecOptions, KernelHost, KernelHostBuilder, StreamSink, TickState};

struct SharedSink(Arc<Mutex<Vec<u8>>>);

impl StreamSink for SharedSink {
    fn write(&mut self, bytes: &[u8]) {
        if let Ok(mut buf) = self.0.lock() {
            buf.extend_from_slice(bytes);
        }
    }
}

struct Vm {
    host: Mutex<KernelHost>,
    out: Arc<Mutex<Vec<u8>>>,
}

static NEXT_ID: OnceLock<Mutex<u64>> = OnceLock::new();
static VMS: OnceLock<Mutex<HashMap<u64, Vm>>> = OnceLock::new();
thread_local! {
    static LAST_ERROR: std::cell::RefCell<String> = const { std::cell::RefCell::new(String::new()) };
}

fn set_error(msg: impl Into<String>) {
    LAST_ERROR.with(|e| *e.borrow_mut() = msg.into());
}

fn clear_error() {
    LAST_ERROR.with(|e| e.borrow_mut().clear());
}

fn vms() -> &'static Mutex<HashMap<u64, Vm>> {
    VMS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn next_id() -> u64 {
    let m = NEXT_ID.get_or_init(|| Mutex::new(1));
    let mut g = m.lock().unwrap_or_else(|e| e.into_inner());
    let id = *g;
    *g = g.wrapping_add(1).max(1);
    id
}

fn with_capture(builder: KernelHostBuilder, out: &Arc<Mutex<Vec<u8>>>) -> KernelHostBuilder {
    builder
        .with_stdout(Box::new(SharedSink(out.clone())))
        .with_stderr(Box::new(SharedSink(out.clone())))
        .with_log(Box::new(SharedSink(out.clone())))
}

/// # Safety
/// `kernel` must point to `kernel_len` readable bytes.
/// `out_vm` must be a valid writable pointer.
#[no_mangle]
pub unsafe extern "C" fn aos_vm_boot(
    kernel: *const u8,
    kernel_len: usize,
    out_vm: *mut u64,
) -> i32 {
    clear_error();
    if kernel.is_null() || out_vm.is_null() || kernel_len == 0 {
        set_error("aos_vm_boot: null or empty kernel");
        return -1;
    }
    let bytes = std::slice::from_raw_parts(kernel, kernel_len).to_vec();
    let out = Arc::new(Mutex::new(Vec::new()));
    let builder = with_capture(KernelHostBuilder::new(bytes), &out);
    let host = match builder.build() {
        Ok(h) => h,
        Err(e) => {
            set_error(format!("boot failed: {e:#}"));
            return -1;
        }
    };
    let id = next_id();
    if let Ok(mut map) = vms().lock() {
        map.insert(
            id,
            Vm {
                host: Mutex::new(host),
                out,
            },
        );
    } else {
        set_error("vm table lock poisoned");
        return -1;
    }
    *out_vm = id;
    0
}

/// # Safety
/// `out_state` must be a valid writable pointer when non-null.
#[no_mangle]
pub unsafe extern "C" fn aos_vm_tick(vm: u64, out_state: *mut i32) -> i32 {
    clear_error();
    if vm == 0 {
        set_error("aos_vm_tick: invalid handle");
        return -1;
    }
    let map = match vms().lock() {
        Ok(m) => m,
        Err(_) => {
            set_error("vm table lock poisoned");
            return -1;
        }
    };
    let Some(entry) = map.get(&vm) else {
        set_error("aos_vm_tick: unknown handle");
        return -1;
    };
    let mut host = match entry.host.lock() {
        Ok(h) => h,
        Err(_) => {
            set_error("host lock poisoned");
            return -1;
        }
    };
    let state = match host.tick() {
        Ok(TickState::Runnable) => 0,
        Ok(TickState::Waiting) => 1,
        Ok(TickState::Exited) => 2,
        Err(e) => {
            set_error(format!("tick failed: {e:#}"));
            return -1;
        }
    };
    if !out_state.is_null() {
        *out_state = state;
    }
    0
}

/// # Safety
/// `data` must point to `len` readable bytes when `len > 0`.
#[no_mangle]
pub unsafe extern "C" fn aos_vm_send_input(vm: u64, data: *const u8, len: usize) -> i32 {
    clear_error();
    if vm == 0 {
        set_error("aos_vm_send_input: invalid handle");
        return -1;
    }
    let bytes = if len == 0 {
        &[][..]
    } else {
        if data.is_null() {
            set_error("aos_vm_send_input: null data");
            return -1;
        }
        std::slice::from_raw_parts(data, len)
    };
    let map = match vms().lock() {
        Ok(m) => m,
        Err(_) => {
            set_error("vm table lock poisoned");
            return -1;
        }
    };
    let Some(entry) = map.get(&vm) else {
        set_error("aos_vm_send_input: unknown handle");
        return -1;
    };
    let mut host = match entry.host.lock() {
        Ok(h) => h,
        Err(_) => {
            set_error("host lock poisoned");
            return -1;
        }
    };
    if let Err(e) = host.send_input(bytes) {
        set_error(format!("send_input failed: {e:#}"));
        return -1;
    }
    0
}

/// # Safety
/// `buf` must point to `cap` writable bytes when `cap > 0`.
#[no_mangle]
pub unsafe extern "C" fn aos_vm_take_output(vm: u64, buf: *mut u8, cap: usize) -> i32 {
    clear_error();
    if vm == 0 {
        set_error("aos_vm_take_output: invalid handle");
        return -1;
    }
    let map = match vms().lock() {
        Ok(m) => m,
        Err(_) => {
            set_error("vm table lock poisoned");
            return -1;
        }
    };
    let Some(entry) = map.get(&vm) else {
        set_error("aos_vm_take_output: unknown handle");
        return -1;
    };
    let mut out = match entry.out.lock() {
        Ok(o) => o,
        Err(_) => {
            set_error("output lock poisoned");
            return -1;
        }
    };
    if cap == 0 || buf.is_null() {
        return out.len() as i32;
    }
    let n = out.len().min(cap);
    if n > 0 {
        std::ptr::copy_nonoverlapping(out.as_ptr(), buf, n);
        out.drain(..n);
    }
    n as i32
}

#[no_mangle]
pub extern "C" fn aos_vm_close(vm: u64) -> i32 {
    clear_error();
    if vm == 0 {
        set_error("aos_vm_close: invalid handle");
        return -1;
    }
    let mut map = match vms().lock() {
        Ok(m) => m,
        Err(_) => {
            set_error("vm table lock poisoned");
            return -1;
        }
    };
    if map.remove(&vm).is_none() {
        set_error("aos_vm_close: unknown handle");
        return -1;
    }
    0
}

fn copy_out(src: &[u8], buf: *mut u8, cap: usize, out_len: *mut usize) {
    let n = src.len().min(cap);
    if !out_len.is_null() {
        unsafe {
            *out_len = n;
        }
    }
    if n > 0 && !buf.is_null() {
        unsafe {
            std::ptr::copy_nonoverlapping(src.as_ptr(), buf, n);
        }
    }
}

/// # Safety
/// `cmd` is a NUL-terminated C string. Buffer pointers may be null if cap is 0.
#[no_mangle]
pub unsafe extern "C" fn aos_vm_exec(
    vm: u64,
    cmd: *const std::os::raw::c_char,
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
    let cmd = match std::ffi::CStr::from_ptr(cmd).to_str() {
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

    let map = match vms().lock() {
        Ok(m) => m,
        Err(_) => {
            set_error("vm table lock poisoned");
            return -1;
        }
    };
    let Some(entry) = map.get(&vm) else {
        set_error("aos_vm_exec: unknown handle");
        return -1;
    };
    let mut host = match entry.host.lock() {
        Ok(h) => h,
        Err(_) => {
            set_error("host lock poisoned");
            return -1;
        }
    };
    let result = match host.exec(cmd, ticks, ExecOptions::default()) {
        Ok(r) => r,
        Err(e) => {
            set_error(format!("exec failed: {e:#}"));
            return -1;
        }
    };
    copy_out(&result.stdout, stdout_buf, stdout_cap, stdout_len);
    copy_out(&result.stderr, stderr_buf, stderr_cap, stderr_len);
    if !out_exit.is_null() {
        *out_exit = result.exit_code;
    }
    0
}

thread_local! {
    static LAST_ERROR_C: std::cell::RefCell<Option<std::ffi::CString>> =
        const { std::cell::RefCell::new(None) };
}

#[no_mangle]
pub extern "C" fn aos_last_error() -> *const std::os::raw::c_char {
    LAST_ERROR.with(|e| {
        let s = e.borrow();
        LAST_ERROR_C.with(|slot| {
            let c = if s.is_empty() {
                std::ffi::CString::new("").expect("empty cstr")
            } else {
                std::ffi::CString::new(s.as_str()).unwrap_or_else(|_| {
                    std::ffi::CString::new("invalid error string").expect("fallback cstr")
                })
            };
            let ptr = c.as_ptr();
            *slot.borrow_mut() = Some(c);
            ptr
        })
    })
}
