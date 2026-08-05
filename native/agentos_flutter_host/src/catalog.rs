//! inject_catalog — thin wrap; blob format is host/NIF-defined.

use crate::buf::{fill_buf, AosBuf};
use crate::error::{clear_error, set_error};
use crate::table::with_host_mut;

/// Catalog injection. When the pin exposes `inject_catalog`, wire it here.
/// Until a stable blob schema is locked, returns a clear error if call shape mismatches.
#[no_mangle]
pub unsafe extern "C" fn aos_vm_inject_catalog(
    vm: u64,
    compiler_wasm: *const u8,
    compiler_len: usize,
    generation: u64,
    catalog_blob: *const u8,
    catalog_len: usize,
    out_status_encoded: *mut AosBuf,
) -> i32 {
    clear_error();
    if vm == 0 {
        set_error("aos_vm_inject_catalog: invalid handle");
        return -1;
    }
    let _compiler = if compiler_len == 0 || compiler_wasm.is_null() {
        &[][..]
    } else {
        std::slice::from_raw_parts(compiler_wasm, compiler_len)
    };
    let _catalog = if catalog_len == 0 || catalog_blob.is_null() {
        &[][..]
    } else {
        std::slice::from_raw_parts(catalog_blob, catalog_len)
    };
    let _ = generation;

    // Prefer host API when available. Pin may use a structured inject_catalog;
    // probe via with_host_mut calling method if it compiles.
    match try_inject(vm, _compiler, generation, _catalog) {
        Ok(status_json) => {
            if !out_status_encoded.is_null() {
                let _ = fill_buf(out_status_encoded, status_json.as_bytes());
            }
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

fn try_inject(
    vm: u64,
    _compiler: &[u8],
    _generation: u64,
    _catalog: &[u8],
) -> Result<String, String> {
    // Without a stable C blob → NIF connection/tool structs mapping, surface as pin-gap
    // until product needs catalog. Keep symbol exported.
    let _ = with_host_mut(vm, |_host| Ok(()))?;
    Err(
        "aos_vm_inject_catalog: structured catalog inject not wired for flutter blob format yet (pin supports inject_catalog with typed args; see docs/aos-c-api.md)"
            .into(),
    )
}
