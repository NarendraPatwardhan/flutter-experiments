//! VM handle table, shared sinks, relay state placeholder.

use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

use host::KernelHost;

use crate::error::{clear_error, set_error};

pub struct SharedSink(pub Arc<Mutex<Vec<u8>>>);

impl host::StreamSink for SharedSink {
    fn write(&mut self, bytes: &[u8]) {
        if let Ok(mut buf) = self.0.lock() {
            buf.extend_from_slice(bytes);
        }
    }
}

/// Relay queue + slots (translation of NIF RelayState). Extended by relay module.
#[derive(Default)]
pub struct RelayState {
    pub next: i32,
    pub events: VecDeque<EgressRelayEvent>,
    pub http: HashMap<i32, HttpSlot>,
    pub host_calls: HashMap<i32, HostCallSlot>,
    pub persist: HashMap<i32, PersistSlot>,
    pub ws: HashMap<i32, WsSlot>,
    pub pending_tool_approvals:
        HashMap<i32, std::sync::mpsc::Sender<ToolApprovalDecision>>,
}

impl RelayState {
    pub fn new() -> Self {
        Self {
            next: 1,
            ..Default::default()
        }
    }

    pub fn alloc_handle(&mut self) -> i32 {
        if self.next <= 0 {
            self.next = 1;
        }
        let handle = self.next;
        self.next = self.next.wrapping_add(1).max(1);
        handle
    }
}

#[derive(Clone, Debug)]
pub struct ToolApprovalDecision {
    pub allow: bool,
    pub remember_session: bool,
}

pub enum EgressRelayEvent {
    HttpRequest { handle: i32, request: Vec<u8> },
    HostCall {
        handle: i32,
        name: String,
        body: Vec<u8>,
    },
    HostCallClose { handle: i32, sidecar: bool },
    PersistGet { handle: i32, key: Vec<u8> },
    PersistPut {
        handle: i32,
        key: Vec<u8>,
        value: Vec<u8>,
    },
    PersistDelete { handle: i32, key: Vec<u8> },
    PersistList { handle: i32, prefix: Vec<u8> },
    WsConnect { handle: i32, url: String },
    WsSend { handle: i32, data: Vec<u8> },
    WsClose { handle: i32 },
    ToolApproval {
        handle: i32,
        connection: String,
        method: String,
        url: String,
        origin: String,
        args_digest: Option<String>,
    },
}

#[derive(Default)]
pub struct HttpSlot {
    pub done: bool,
    pub failed: bool,
    pub head: Vec<u8>,
    pub body: Vec<u8>,
    pub body_pos: usize,
}

#[derive(Default)]
pub struct HostCallSlot {
    pub dispatched: bool,
    pub sidecar: bool,
    pub done: bool,
    pub failed: bool,
    pub result: Vec<u8>,
    pub offset: usize,
}

#[derive(Default)]
pub struct PersistSlot {
    pub done: bool,
    pub failed: bool,
    pub result: Vec<u8>,
    pub offset: usize,
}

#[derive(Default)]
pub struct WsSlot {
    pub open: bool,
    pub failed: bool,
    pub incoming: VecDeque<Vec<u8>>,
    pub incoming_pos: usize,
    pub queued_bytes: usize,
}

pub struct Vm {
    pub host: Mutex<KernelHost>,
    pub out: Arc<Mutex<Vec<u8>>>,
    pub out_stdout: Arc<Mutex<Vec<u8>>>,
    pub out_stderr: Arc<Mutex<Vec<u8>>>,
    pub out_log: Arc<Mutex<Vec<u8>>>,
    pub relay: Arc<Mutex<RelayState>>,
}

static NEXT_ID: OnceLock<Mutex<u64>> = OnceLock::new();
static VMS: OnceLock<Mutex<HashMap<u64, Vm>>> = OnceLock::new();

fn next_id() -> u64 {
    let m = NEXT_ID.get_or_init(|| Mutex::new(1));
    let mut g = m.lock().unwrap_or_else(|e| e.into_inner());
    let id = *g;
    *g = g.wrapping_add(1).max(1);
    id
}

pub fn vms() -> &'static Mutex<HashMap<u64, Vm>> {
    VMS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub fn insert_vm(vm: Vm) -> u64 {
    let id = next_id();
    if let Ok(mut map) = vms().lock() {
        map.insert(id, vm);
    }
    id
}

pub fn remove_vm(id: u64) -> Option<Vm> {
    vms().lock().ok().and_then(|mut m| m.remove(&id))
}

/// Run `f` with exclusive access to the VM entry.
pub fn with_vm<R>(
    vm: u64,
    f: impl FnOnce(&Vm) -> Result<R, String>,
) -> Result<R, String> {
    if vm == 0 {
        return Err("invalid handle".into());
    }
    let map = vms()
        .lock()
        .map_err(|_| "vm table lock poisoned".to_string())?;
    let entry = map.get(&vm).ok_or_else(|| "unknown handle".to_string())?;
    f(entry)
}

pub fn with_host_mut<R>(
    vm: u64,
    f: impl FnOnce(MutexGuard<'_, KernelHost>) -> Result<R, String>,
) -> Result<R, String> {
    with_vm(vm, |entry| {
        let host = entry
            .host
            .lock()
            .map_err(|_| "host lock poisoned".to_string())?;
        f(host)
    })
}

pub fn take_merged_output(entry: &Vm) -> Vec<u8> {
    let mut out = Vec::new();
    for arc in [&entry.out, &entry.out_stdout, &entry.out_stderr, &entry.out_log] {
        if let Ok(mut g) = arc.lock() {
            out.extend_from_slice(&g);
            g.clear();
        }
    }
    // Prefer primary out sink (legacy combined).
    out
}

pub fn drain_arc(arc: &Arc<Mutex<Vec<u8>>>) -> Vec<u8> {
    match arc.lock() {
        Ok(mut g) => {
            let v = g.clone();
            g.clear();
            v
        }
        Err(_) => Vec::new(),
    }
}

pub fn c_err(msg: impl Into<String>) -> i32 {
    set_error(msg);
    -1
}

pub fn c_ok() -> i32 {
    clear_error();
    0
}
