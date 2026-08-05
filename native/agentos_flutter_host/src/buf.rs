//! Caller-owned aos_buf_t / library aos_bytes_t helpers.

/// Mirrors C `aos_buf_t`.
#[repr(C)]
pub struct AosBuf {
    pub ptr: *mut u8,
    pub cap: usize,
    pub len: usize,
}

/// Mirrors C `aos_bytes_t`.
#[repr(C)]
pub struct AosBytes {
    pub ptr: *mut u8,
    pub len: usize,
}

/// Copy `src` into caller buffer.
///
/// On success: `len = src.len()`, returns 0.
/// If the buffer is too small (or null ptr with non-empty src): sets `len` to the
/// required size and returns -1 so the caller can reallocate.
pub unsafe fn fill_buf(out: *mut AosBuf, src: &[u8]) -> i32 {
    if out.is_null() {
        return -1;
    }
    let b = &mut *out;
    b.len = src.len();
    if src.is_empty() {
        return 0;
    }
    if b.cap < src.len() || b.ptr.is_null() {
        return -1;
    }
    std::ptr::copy_nonoverlapping(src.as_ptr(), b.ptr, src.len());
    0
}

pub fn alloc_bytes(src: &[u8]) -> AosBytes {
    if src.is_empty() {
        return AosBytes {
            ptr: std::ptr::null_mut(),
            len: 0,
        };
    }
    unsafe {
        let layout = std::alloc::Layout::from_size_align(src.len(), 1).expect("layout");
        let p = std::alloc::alloc(layout);
        if p.is_null() {
            return AosBytes {
                ptr: std::ptr::null_mut(),
                len: 0,
            };
        }
        std::ptr::copy_nonoverlapping(src.as_ptr(), p, src.len());
        AosBytes {
            ptr: p,
            len: src.len(),
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_bytes_free(b: *mut AosBytes) {
    if b.is_null() {
        return;
    }
    let b = &mut *b;
    if !b.ptr.is_null() && b.len > 0 {
        let layout = std::alloc::Layout::from_size_align(b.len, 1).expect("layout");
        std::alloc::dealloc(b.ptr, layout);
    }
    b.ptr = std::ptr::null_mut();
    b.len = 0;
}

pub unsafe fn copy_out(src: &[u8], buf: *mut u8, cap: usize, out_len: *mut usize) {
    let n = src.len().min(cap);
    if !out_len.is_null() {
        *out_len = n;
    }
    if n > 0 && !buf.is_null() {
        std::ptr::copy_nonoverlapping(src.as_ptr(), buf, n);
    }
}

/// Read optional env blob: KEY\\0VAL\\0 pairs.
pub fn parse_env_blob(blob: &[u8]) -> Result<Vec<(String, String)>, String> {
    if blob.is_empty() {
        return Ok(Vec::new());
    }
    let mut out = Vec::new();
    let mut i = 0;
    while i < blob.len() {
        let key_end = blob[i..]
            .iter()
            .position(|&c| c == 0)
            .ok_or_else(|| "env blob: missing key NUL".to_string())?;
        let key = std::str::from_utf8(&blob[i..i + key_end])
            .map_err(|_| "env blob: key not utf8".to_string())?
            .to_string();
        i += key_end + 1;
        if i >= blob.len() {
            return Err("env blob: missing value".into());
        }
        let val_end = blob[i..]
            .iter()
            .position(|&c| c == 0)
            .ok_or_else(|| "env blob: missing value NUL".to_string())?;
        let val = std::str::from_utf8(&blob[i..i + val_end])
            .map_err(|_| "env blob: value not utf8".to_string())?
            .to_string();
        i += val_end + 1;
        out.push((key, val));
    }
    Ok(out)
}

