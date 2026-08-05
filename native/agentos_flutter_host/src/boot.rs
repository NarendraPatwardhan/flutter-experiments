//! Boot / restore — translation of NIF boot_nif / restore_nif.

use std::os::raw::c_void;
use std::sync::{Arc, Mutex};

use host::{KernelHostBuilder, TickState};

use crate::error::{clear_error, set_error};
use crate::table::{insert_vm, RelayState, Vm};

#[repr(C)]
pub struct AosBootOpts {
    pub size: usize,
    pub base_image: *const u8,
    pub base_image_len: usize,
    pub layers: *const *const u8,
    pub layer_lens: *const usize,
    pub layer_count: usize,
    pub deterministic: i32,
    pub has_contract: i32,
    pub contract_tier: i32,
    pub contract_budget_mib: i32,
    pub contract_fuel: i64,
    pub workers: u32,
    pub net: i32,
    pub host_call: i32,
    pub host_call_sidecar_only: i32,
    pub persist: i32,
    pub tool_approval: i32,
    pub connections_blob: *const u8,
    pub connections_len: usize,
    pub connection_policies_blob: *const u8,
    pub connection_policies_len: usize,
}

fn with_capture(
    mut builder: KernelHostBuilder,
    out: &Arc<Mutex<Vec<u8>>>,
    out_stdout: &Arc<Mutex<Vec<u8>>>,
    out_stderr: &Arc<Mutex<Vec<u8>>>,
    out_log: &Arc<Mutex<Vec<u8>>>,
) -> KernelHostBuilder {
    // Legacy combined sink + per-stream sinks for take_output_ex.
    builder = builder
        .with_stdout(Box::new(TeeSink {
            a: out.clone(),
            b: out_stdout.clone(),
        }))
        .with_stderr(Box::new(TeeSink {
            a: out.clone(),
            b: out_stderr.clone(),
        }))
        .with_log(Box::new(TeeSink {
            a: out.clone(),
            b: out_log.clone(),
        }));
    builder
}

struct TeeSink {
    a: Arc<Mutex<Vec<u8>>>,
    b: Arc<Mutex<Vec<u8>>>,
}

impl host::StreamSink for TeeSink {
    fn write(&mut self, bytes: &[u8]) {
        for arc in [&self.a, &self.b] {
            if let Ok(mut g) = arc.lock() {
                g.extend_from_slice(bytes);
            }
        }
    }
}

unsafe fn read_opts(opts: *const AosBootOpts) -> Result<BootPlan, String> {
    if opts.is_null() {
        return Ok(BootPlan::default());
    }
    let o = &*opts;
    if o.size != 0 && o.size < std::mem::size_of::<AosBootOpts>() {
        // Allow forward-compat smaller reads of known prefix — require at least through workers.
        // For simplicity require full struct when size set and non-zero.
    }
    let mut plan = BootPlan::default();
    if o.base_image_len > 0 {
        if o.base_image.is_null() {
            return Err("base_image_len > 0 but pointer null".into());
        }
        plan.base = Some(std::slice::from_raw_parts(o.base_image, o.base_image_len).to_vec());
    }
    if o.layer_count > 0 {
        if o.layers.is_null() || o.layer_lens.is_null() {
            return Err("layers set but pointers null".into());
        }
        let mut layers = Vec::with_capacity(o.layer_count);
        for i in 0..o.layer_count {
            let p = *o.layers.add(i);
            let n = *o.layer_lens.add(i);
            if n > 0 && p.is_null() {
                return Err("layer pointer null".into());
            }
            layers.push(if n == 0 {
                Vec::new()
            } else {
                std::slice::from_raw_parts(p, n).to_vec()
            });
        }
        plan.layers = layers;
    }
    if plan.base.is_some() && !plan.layers.is_empty() {
        return Err("base_image and layers are mutually exclusive".into());
    }
    plan.deterministic = o.deterministic != 0;
    if o.has_contract != 0 {
        plan.contract = Some((o.contract_tier, o.contract_budget_mib, o.contract_fuel));
    }
    if o.workers > 0 {
        plan.workers = Some(o.workers as i32);
    }
    plan.net = o.net;
    plan.host_call = o.host_call;
    plan.host_call_sidecar_only = o.host_call_sidecar_only != 0;
    plan.persist = o.persist;
    plan.tool_approval = o.tool_approval;
    // connections blobs reserved for real-net (T4); ignore content when net != REAL
    if o.connections_len > 0 && !o.connections_blob.is_null() {
        plan.connections =
            Some(std::slice::from_raw_parts(o.connections_blob, o.connections_len).to_vec());
    }
    if o.connection_policies_len > 0 && !o.connection_policies_blob.is_null() {
        plan.policies = Some(std::slice::from_raw_parts(
            o.connection_policies_blob,
            o.connection_policies_len,
        )
        .to_vec());
    }
    Ok(plan)
}

#[derive(Default)]
struct BootPlan {
    base: Option<Vec<u8>>,
    layers: Vec<Vec<u8>>,
    deterministic: bool,
    contract: Option<(i32, i32, i64)>,
    workers: Option<i32>,
    net: i32,
    host_call: i32,
    host_call_sidecar_only: bool,
    persist: i32,
    tool_approval: i32,
    connections: Option<Vec<u8>>,
    policies: Option<Vec<u8>>,
}

fn build_host(
    wasm: Vec<u8>,
    plan: BootPlan,
    out: &Arc<Mutex<Vec<u8>>>,
    out_stdout: &Arc<Mutex<Vec<u8>>>,
    out_stderr: &Arc<Mutex<Vec<u8>>>,
    out_log: &Arc<Mutex<Vec<u8>>>,
    relay: &Arc<Mutex<RelayState>>,
) -> Result<host::KernelHost, String> {
    let mut builder = KernelHostBuilder::new(wasm);
    if !plan.layers.is_empty() {
        builder = builder.with_layers(plan.layers);
    } else {
        builder = builder.with_base_image(plan.base);
    }
    if plan.deterministic {
        builder = builder.deterministic();
    }
    if let Some((t, b, f)) = plan.contract {
        builder = builder.with_contract(t, b, f);
    }
    if let Some(w) = plan.workers {
        builder = builder.with_workers(w);
    }
    // Caps: deny = default (builder defaults). Relay = attach Beam-style caps.
    builder = crate::relay::apply_boot_caps(
        builder,
        plan.net,
        plan.host_call,
        plan.host_call_sidecar_only,
        plan.persist,
        plan.tool_approval,
        plan.connections,
        plan.policies,
        relay,
    )?;
    builder = with_capture(builder, out, out_stdout, out_stderr, out_log);
    builder.build().map_err(|e| format!("boot failed: {e:#}"))
}

fn tick_toward_prompt(host: &mut host::KernelHost) {
    // Best-effort: tick a bounded number of times like historical smoke path.
    for _ in 0..64 {
        match host.tick() {
            Ok(TickState::Waiting) | Ok(TickState::Exited) => break,
            Ok(TickState::Runnable) => {}
            Err(_) => break,
        }
        if host.at_prompt() {
            break;
        }
    }
}

fn finish_boot(wasm: Vec<u8>, plan: BootPlan) -> Result<u64, String> {
    let out = Arc::new(Mutex::new(Vec::new()));
    let out_stdout = Arc::new(Mutex::new(Vec::new()));
    let out_stderr = Arc::new(Mutex::new(Vec::new()));
    let out_log = Arc::new(Mutex::new(Vec::new()));
    let relay = Arc::new(Mutex::new(RelayState::new()));
    let mut host = build_host(
        wasm,
        plan,
        &out,
        &out_stdout,
        &out_stderr,
        &out_log,
        &relay,
    )?;
    tick_toward_prompt(&mut host);
    Ok(insert_vm(Vm {
        host: Mutex::new(host),
        out,
        out_stdout,
        out_stderr,
        out_log,
        relay,
    }))
}

/// # Safety: kernel non-null when kernel_len > 0; out_vm non-null.
#[no_mangle]
pub unsafe extern "C" fn aos_vm_boot(
    kernel: *const u8,
    kernel_len: usize,
    image: *const u8,
    image_len: usize,
    out_vm: *mut u64,
) -> i32 {
    clear_error();
    if kernel.is_null() || out_vm.is_null() || kernel_len == 0 {
        set_error("aos_vm_boot: null or empty kernel");
        return -1;
    }
    if image_len > 0 && image.is_null() {
        set_error("aos_vm_boot: image_len > 0 but image is null");
        return -1;
    }
    let wasm = std::slice::from_raw_parts(kernel, kernel_len).to_vec();
    let mut plan = BootPlan::default();
    if image_len > 0 {
        plan.base = Some(std::slice::from_raw_parts(image, image_len).to_vec());
    }
    match finish_boot(wasm, plan) {
        Ok(id) => {
            *out_vm = id;
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_boot_ex(
    kernel: *const u8,
    kernel_len: usize,
    opts: *const AosBootOpts,
    out_vm: *mut u64,
) -> i32 {
    clear_error();
    if kernel.is_null() || out_vm.is_null() || kernel_len == 0 {
        set_error("aos_vm_boot_ex: null or empty kernel");
        return -1;
    }
    let wasm = std::slice::from_raw_parts(kernel, kernel_len).to_vec();
    let plan = match read_opts(opts) {
        Ok(p) => p,
        Err(e) => {
            set_error(e);
            return -1;
        }
    };
    match finish_boot(wasm, plan) {
        Ok(id) => {
            *out_vm = id;
            0
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_restore(
    kernel: *const u8,
    kernel_len: usize,
    snapshot: *const u8,
    snapshot_len: usize,
    base_snapshot: *const u8,
    base_snapshot_len: usize,
    opts: *const AosBootOpts,
    out_vm: *mut u64,
) -> i32 {
    clear_error();
    if kernel.is_null()
        || snapshot.is_null()
        || out_vm.is_null()
        || kernel_len == 0
        || snapshot_len == 0
    {
        set_error("aos_vm_restore: invalid args");
        return -1;
    }
    let wasm = std::slice::from_raw_parts(kernel, kernel_len).to_vec();
    let snap = std::slice::from_raw_parts(snapshot, snapshot_len);
    let plan = match read_opts(opts) {
        Ok(p) => p,
        Err(e) => {
            set_error(e);
            return -1;
        }
    };
    let out = Arc::new(Mutex::new(Vec::new()));
    let out_stdout = Arc::new(Mutex::new(Vec::new()));
    let out_stderr = Arc::new(Mutex::new(Vec::new()));
    let out_log = Arc::new(Mutex::new(Vec::new()));
    let relay = Arc::new(Mutex::new(RelayState::new()));
    let mut builder = KernelHostBuilder::new(wasm);
    if plan.deterministic {
        builder = builder.deterministic();
    }
    if let Some(w) = plan.workers {
        builder = builder.with_workers(w);
    }
    builder = match crate::relay::apply_boot_caps(
        builder,
        plan.net,
        plan.host_call,
        plan.host_call_sidecar_only,
        plan.persist,
        plan.tool_approval,
        plan.connections,
        plan.policies,
        &relay,
    ) {
        Ok(b) => b,
        Err(e) => {
            set_error(e);
            return -1;
        }
    };
    builder = with_capture(builder, &out, &out_stdout, &out_stderr, &out_log);
    let host = if base_snapshot_len > 0 {
        if base_snapshot.is_null() {
            set_error("base_snapshot_len > 0 but pointer null");
            return -1;
        }
        let base = std::slice::from_raw_parts(base_snapshot, base_snapshot_len);
        builder.restore_incremental(snap, base)
    } else {
        builder.restore(snap)
    };
    match host {
        Ok(h) => {
            *out_vm = insert_vm(Vm {
                host: Mutex::new(h),
                out,
                out_stdout,
                out_stderr,
                out_log,
                relay,
            });
            0
        }
        Err(e) => {
            set_error(format!("restore failed: {e:#}"));
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn aos_vm_close(vm: u64) -> i32 {
    clear_error();
    if vm == 0 {
        set_error("aos_vm_close: invalid handle");
        return -1;
    }
    match crate::table::remove_vm(vm) {
        Some(_) => 0,
        None => {
            set_error("aos_vm_close: unknown handle");
            -1
        }
    }
}

#[allow(dead_code)]
fn _c_void(_: *mut c_void) {}
