//! Snapshot + commit_layer.

use crate::buf::{alloc_bytes, fill_buf, AosBuf, AosBytes};
use crate::error::{clear_error, set_error};
use crate::table::with_host_mut;

#[no_mangle]
pub unsafe extern "C" fn aos_vm_snapshot(vm: u64, out: *mut AosBytes) -> i32 {
    clear_error();
    if vm == 0 || out.is_null() {
        set_error("aos_vm_snapshot: invalid args");
        return -1;
    }
    match with_host_mut(vm, |mut host| {
        host.snapshot()
            .map_err(|e| format!("snapshot failed: {e:#}"))
    }) {
        Ok(bytes) => {
            let ab = alloc_bytes(&bytes);
            if ab.len != bytes.len() && !bytes.is_empty() {
                set_error("snapshot alloc failed");
                return -1;
            }
            *out = ab;
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_snapshot_into(vm: u64, out: *mut AosBuf) -> i32 {
    clear_error();
    if vm == 0 || out.is_null() {
        set_error("aos_vm_snapshot_into: invalid args");
        return -1;
    }
    match with_host_mut(vm, |mut host| {
        host.snapshot()
            .map_err(|e| format!("snapshot failed: {e:#}"))
    }) {
        Ok(bytes) => {
            let b = &mut *out;
            b.len = bytes.len();
            if b.cap < bytes.len() || b.ptr.is_null() {
                return -1; // required size in len
            }
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), b.ptr, bytes.len());
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_snapshot_incremental(
    vm: u64,
    base: *const u8,
    base_len: usize,
    out: *mut AosBytes,
) -> i32 {
    clear_error();
    if vm == 0 || base.is_null() || base_len == 0 || out.is_null() {
        set_error("aos_vm_snapshot_incremental: invalid args");
        return -1;
    }
    let base = std::slice::from_raw_parts(base, base_len);
    match with_host_mut(vm, |mut host| {
        host.snapshot_incremental(base)
            .map_err(|e| format!("snapshot_incremental failed: {e:#}"))
    }) {
        Ok(bytes) => {
            let ab = alloc_bytes(&bytes);
            if ab.len != bytes.len() && !bytes.is_empty() {
                set_error("alloc failed");
                return -1;
            }
            *out = ab;
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_commit_layer(
    vm: u64,
    out_tar: *mut AosBytes,
    out_digest_hex: *mut AosBuf,
) -> i32 {
    clear_error();
    if vm == 0 || out_tar.is_null() {
        set_error("aos_vm_commit_layer: invalid args");
        return -1;
    }
    match with_host_mut(vm, |mut host| {
        host.commit_layer()
            .map_err(|e| format!("commit_layer failed: {e:#}"))
    }) {
        Ok((tar, digest)) => {
            let ab = alloc_bytes(&tar);
            if ab.len != tar.len() && !tar.is_empty() {
                set_error("alloc failed");
                return -1;
            }
            *out_tar = ab;
            if !out_digest_hex.is_null() {
                let _ = fill_buf(out_digest_hex, digest.as_bytes());
            }
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}
