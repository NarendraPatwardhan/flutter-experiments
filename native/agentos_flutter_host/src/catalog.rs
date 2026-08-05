//! `aos_vm_inject_catalog` — JSON catalog blob → `host::inject_catalog`.
//!
//! # Catalog blob schema (UTF-8 JSON, versioned by field presence)
//!
//! ```json
//! {
//!   "tools": ["group-a"],
//!   "host_tools": [
//!     {
//!       "address": "tool.greet",
//!       "description": "…",
//!       "binding_name": "greet",
//!       "args_mode": "json",
//!       "input_schema": "{…}",
//!       "output_schema": "{…}",
//!       "annotations": "{…}"
//!     }
//!   ],
//!   "connections": [
//!     {
//!       "reference": "integration.owner.name",
//!       "tools": ["group-a"],
//!       "spec": {
//!         "kind": "bytes" | "path" | "url" | "none",
//!         "payload": "…",
//!         "format": "openapi",
//!         "source_format": "json",
//!         "base_url": "https://…",
//!         "endpoint": "https://…"
//!       }
//!     }
//!   ]
//! }
//! ```
//!
//! - `tools` / `host_tools` / `connections` may be omitted (default empty).
//! - Spec `kind` `"none"` or omitted `spec` means no source document.
//! - Spec `payload` is UTF-8 text (OpenAPI/YAML/JSON/URL/path). Binary payloads
//!   may use `payload_hex` (even-length hex) instead of `payload`.
//!
//! # Status blob (out_status_encoded)
//!
//! JSON object: `{"generation":N,"digest":"hex","tools":N}` or empty when the
//! host returns no apply status.

use std::path::PathBuf;

use host::{
    CatalogConnection, CatalogInjectOptions, CatalogSpecSource, HostToolDef, KernelHost,
};
use json::{parse as json_parse, to_string as json_to_string, Json, JsonError};

use crate::buf::{fill_buf, AosBuf};
use crate::error::{clear_error, set_error};
use crate::table::with_host_mut;

/// # Safety: pointers valid for the given lengths when non-null and len > 0.
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
    if compiler_len > 0 && compiler_wasm.is_null() {
        set_error("aos_vm_inject_catalog: compiler_wasm null with non-zero len");
        return -1;
    }
    if catalog_len > 0 && catalog_blob.is_null() {
        set_error("aos_vm_inject_catalog: catalog_blob null with non-zero len");
        return -1;
    }

    let compiler = if compiler_len == 0 {
        Vec::new()
    } else {
        std::slice::from_raw_parts(compiler_wasm, compiler_len).to_vec()
    };
    let catalog = if catalog_len == 0 {
        &[][..]
    } else {
        std::slice::from_raw_parts(catalog_blob, catalog_len)
    };

    match inject(vm, compiler, generation, catalog) {
        Ok(status_bytes) => {
            if !out_status_encoded.is_null() {
                if let Err(rc) = fill_buf_result(out_status_encoded, &status_bytes) {
                    return rc;
                }
            }
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

fn fill_buf_result(out: *mut AosBuf, bytes: &[u8]) -> Result<(), i32> {
    let rc = unsafe { fill_buf(out, bytes) };
    if rc != 0 {
        Err(rc)
    } else {
        Ok(())
    }
}

fn inject(
    vm: u64,
    compiler_wasm: Vec<u8>,
    generation: u64,
    catalog: &[u8],
) -> Result<Vec<u8>, String> {
    let opts = parse_catalog_blob(catalog, compiler_wasm, generation)?;
    with_host_mut(vm, |mut host: std::sync::MutexGuard<'_, KernelHost>| {
        let status = host
            .inject_catalog(opts)
            .map_err(|e| format!("inject_catalog failed: {e:#}"))?;
        Ok(encode_status(status))
    })
}

fn encode_status(status: Option<host::CatalogApplyStatus>) -> Vec<u8> {
    let Some(s) = status else {
        return Vec::new();
    };
    let obj = Json::Obj(vec![
        ("generation".into(), Json::Num(s.generation as f64)),
        ("digest".into(), Json::Str(s.digest)),
        ("tools".into(), Json::Num(s.tools as f64)),
    ]);
    json_to_string(&obj).into_bytes()
}

fn parse_catalog_blob(
    catalog: &[u8],
    compiler_wasm: Vec<u8>,
    generation: u64,
) -> Result<CatalogInjectOptions, String> {
    if catalog.is_empty() {
        return Ok(CatalogInjectOptions {
            compiler_wasm,
            connections: Vec::new(),
            tools: Vec::new(),
            host_tools: Vec::new(),
            generation,
        });
    }
    let text = std::str::from_utf8(catalog).map_err(|_| {
        "aos_vm_inject_catalog: catalog_blob must be UTF-8 JSON".to_string()
    })?;
    let root = json_parse(text).map_err(json_err("catalog_blob"))?;
    let obj = root
        .as_obj()
        .ok_or_else(|| "aos_vm_inject_catalog: catalog_blob root must be a JSON object".to_string())?;

    let tools = match get_field(obj, "tools") {
        None | Some(Json::Null) => Vec::new(),
        Some(v) => string_array(v, "tools")?,
    };
    let host_tools = match get_field(obj, "host_tools") {
        None | Some(Json::Null) => Vec::new(),
        Some(v) => parse_host_tools(v)?,
    };
    let connections = match get_field(obj, "connections") {
        None | Some(Json::Null) => Vec::new(),
        Some(v) => parse_connections(v)?,
    };

    Ok(CatalogInjectOptions {
        compiler_wasm,
        connections,
        tools,
        host_tools,
        generation,
    })
}

fn parse_host_tools(v: &Json) -> Result<Vec<HostToolDef>, String> {
    let arr = v
        .as_arr()
        .ok_or_else(|| "host_tools must be a JSON array".to_string())?;
    let mut out = Vec::with_capacity(arr.len());
    for (i, item) in arr.iter().enumerate() {
        let o = item
            .as_obj()
            .ok_or_else(|| format!("host_tools[{i}] must be an object"))?;
        let address = require_str(o, "address", &format!("host_tools[{i}]"))?;
        let description = opt_str(o, "description").unwrap_or_default();
        let binding_name = require_str(o, "binding_name", &format!("host_tools[{i}]"))?;
        let args_mode = opt_str(o, "args_mode").unwrap_or_else(|| "json".into());
        out.push(HostToolDef {
            address,
            description,
            binding_name,
            args_mode,
            input_schema: opt_str(o, "input_schema"),
            output_schema: opt_str(o, "output_schema"),
            annotations: opt_str(o, "annotations"),
        });
    }
    Ok(out)
}

fn parse_connections(v: &Json) -> Result<Vec<CatalogConnection>, String> {
    let arr = v
        .as_arr()
        .ok_or_else(|| "connections must be a JSON array".to_string())?;
    let mut out = Vec::with_capacity(arr.len());
    for (i, item) in arr.iter().enumerate() {
        let o = item
            .as_obj()
            .ok_or_else(|| format!("connections[{i}] must be an object"))?;
        let reference = require_str(o, "reference", &format!("connections[{i}]"))?;
        let tools = match get_field(o, "tools") {
            None | Some(Json::Null) => Vec::new(),
            Some(t) => string_array(t, &format!("connections[{i}].tools"))?,
        };
        let spec = match get_field(o, "spec") {
            None | Some(Json::Null) => None,
            Some(s) => Some(parse_spec(s, i)?),
        };
        // Flatten Option<Option> — parse_spec returns None for kind "none".
        let spec = spec.flatten();
        out.push(CatalogConnection {
            reference,
            spec,
            tools,
        });
    }
    Ok(out)
}

fn parse_spec(v: &Json, i: usize) -> Result<Option<CatalogSpecSource>, String> {
    let o = v
        .as_obj()
        .ok_or_else(|| format!("connections[{i}].spec must be an object"))?;
    let kind = opt_str(o, "kind").unwrap_or_else(|| "none".into());
    let format = opt_str(o, "format");
    let source_format = opt_str(o, "source_format");
    let base_url = opt_str(o, "base_url");
    let endpoint = opt_str(o, "endpoint");
    match kind.as_str() {
        "none" => Ok(None),
        "bytes" => {
            let bytes = payload_bytes(o, i)?;
            Ok(Some(CatalogSpecSource::Bytes {
                bytes,
                format,
                source_format,
                base_url,
                endpoint,
            }))
        }
        "path" => {
            let path = require_payload_string(o, i)?;
            Ok(Some(CatalogSpecSource::Path {
                path: PathBuf::from(path),
                format,
                source_format,
                base_url,
                endpoint,
            }))
        }
        "url" => {
            let url = require_payload_string(o, i)?;
            Ok(Some(CatalogSpecSource::Url {
                url,
                format,
                source_format,
                base_url,
                endpoint,
            }))
        }
        other => Err(format!(
            "connections[{i}].spec.kind unknown {other:?} (want none|bytes|path|url)"
        )),
    }
}

fn payload_bytes(o: &[(String, Json)], i: usize) -> Result<Vec<u8>, String> {
    if let Some(hex) = opt_str(o, "payload_hex") {
        return decode_hex(&hex)
            .map_err(|e| format!("connections[{i}].spec.payload_hex: {e}"));
    }
    if let Some(s) = opt_str(o, "payload") {
        return Ok(s.into_bytes());
    }
    Err(format!(
        "connections[{i}].spec kind=bytes requires payload or payload_hex"
    ))
}

fn require_payload_string(o: &[(String, Json)], i: usize) -> Result<String, String> {
    opt_str(o, "payload").ok_or_else(|| {
        format!("connections[{i}].spec requires string field \"payload\"")
    })
}

fn decode_hex(s: &str) -> Result<Vec<u8>, String> {
    let s = s.trim();
    if s.len() % 2 != 0 {
        return Err("odd length".into());
    }
    let mut out = Vec::with_capacity(s.len() / 2);
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let hi = hex_nibble(bytes[i])?;
        let lo = hex_nibble(bytes[i + 1])?;
        out.push((hi << 4) | lo);
        i += 2;
    }
    Ok(out)
}

fn hex_nibble(b: u8) -> Result<u8, String> {
    match b {
        b'0'..=b'9' => Ok(b - b'0'),
        b'a'..=b'f' => Ok(b - b'a' + 10),
        b'A'..=b'F' => Ok(b - b'A' + 10),
        _ => Err(format!("invalid hex digit {:?}", b as char)),
    }
}

fn string_array(v: &Json, label: &str) -> Result<Vec<String>, String> {
    let arr = v
        .as_arr()
        .ok_or_else(|| format!("{label} must be a JSON array of strings"))?;
    let mut out = Vec::with_capacity(arr.len());
    for (i, item) in arr.iter().enumerate() {
        let s = item
            .as_str()
            .ok_or_else(|| format!("{label}[{i}] must be a string"))?;
        out.push(s.to_string());
    }
    Ok(out)
}

fn get_field<'a>(obj: &'a [(String, Json)], key: &str) -> Option<&'a Json> {
    obj.iter().find(|(k, _)| k == key).map(|(_, v)| v)
}

fn opt_str(obj: &[(String, Json)], key: &str) -> Option<String> {
    match get_field(obj, key) {
        None | Some(Json::Null) => None,
        Some(Json::Str(s)) if s.is_empty() => None,
        Some(Json::Str(s)) => Some(s.clone()),
        Some(_) => None, // shape errors caught by require_str when needed
    }
}

fn require_str(obj: &[(String, Json)], key: &str, ctx: &str) -> Result<String, String> {
    match get_field(obj, key) {
        Some(Json::Str(s)) if !s.is_empty() => Ok(s.clone()),
        Some(Json::Str(_)) => Err(format!("{ctx}.{key} must be a non-empty string")),
        Some(_) => Err(format!("{ctx}.{key} must be a string")),
        None => Err(format!("{ctx} missing required string field {key:?}")),
    }
}

fn json_err(label: &str) -> impl Fn(JsonError) -> String + '_ {
    move |e| match e {
        JsonError::Parse => format!("aos_vm_inject_catalog: {label} is not valid JSON"),
        JsonError::Shape => format!("aos_vm_inject_catalog: {label} has unexpected shape"),
    }
}
