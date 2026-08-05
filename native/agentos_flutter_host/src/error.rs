//! Thread-local last error + C string export.

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::OnceLock;

thread_local! {
    static LAST_ERROR: RefCell<String> = const { RefCell::new(String::new()) };
    static LAST_ERROR_C: RefCell<Option<CString>> = const { RefCell::new(None) };
}

static VERSION: OnceLock<CString> = OnceLock::new();

pub fn set_error(msg: impl Into<String>) {
    LAST_ERROR.with(|e| *e.borrow_mut() = msg.into());
}

pub fn clear_error() {
    LAST_ERROR.with(|e| e.borrow_mut().clear());
}

#[no_mangle]
pub extern "C" fn aos_api_version() -> i32 {
    1
}

#[no_mangle]
pub extern "C" fn aos_version() -> *const c_char {
    VERSION
        .get_or_init(|| CString::new("agentos_flutter_host/1").expect("version"))
        .as_ptr()
}

#[no_mangle]
pub extern "C" fn aos_last_error() -> *const c_char {
    LAST_ERROR.with(|e| {
        let s = e.borrow();
        LAST_ERROR_C.with(|slot| {
            let c = if s.is_empty() {
                CString::new("").expect("empty")
            } else {
                CString::new(s.as_str()).unwrap_or_else(|_| {
                    CString::new("invalid error string").expect("fallback")
                })
            };
            let ptr = c.as_ptr();
            *slot.borrow_mut() = Some(c);
            ptr
        })
    })
}

/// Safety: `p` must be a valid NUL-terminated C string or null.
pub unsafe fn cstr_to_str<'a>(p: *const c_char) -> Result<&'a str, ()> {
    if p.is_null() {
        return Err(());
    }
    CStr::from_ptr(p).to_str().map_err(|_| ())
}
