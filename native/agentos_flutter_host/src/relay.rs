//! Relay queues — translation of NIF BeamNet / BeamHostCall / BeamPersist.

use std::sync::{Arc, Mutex};

use host::{HostCallCapability, KernelHostBuilder, NetCapability, PersistCapability};

use crate::buf::{fill_buf, AosBuf};
use crate::error::{clear_error, set_error};
use crate::table::{
    with_vm, EgressRelayEvent, HostCallSlot, HttpSlot, PersistSlot, RelayState, ToolApprovalDecision,
    WsSlot,
};

const WS_SEND_MARK: usize = 256 * 1024;

/// net/host_call/persist: 0=deny (builder default), 1=relay. net=2 real unsupported.
pub fn apply_boot_caps(
    mut builder: KernelHostBuilder,
    net: i32,
    host_call: i32,
    host_call_sidecar_only: bool,
    persist: i32,
    _tool_approval: i32,
    _connections: Option<Vec<u8>>,
    _policies: Option<Vec<u8>>,
    relay: &Arc<Mutex<RelayState>>,
) -> Result<KernelHostBuilder, String> {
    if net == 2 {
        return Err(
            "AOS_NET_REAL not supported in flutter host yet (use DENY or RELAY)".into(),
        );
    }
    if net == 1 {
        builder = builder.with_net(Box::new(FlutterNet {
            relay: relay.clone(),
        }));
    }
    if host_call == 1 {
        builder = builder.with_host_call(Box::new(FlutterHostCall {
            relay: relay.clone(),
            sidecar_only: host_call_sidecar_only,
        }));
    }
    if persist == 1 {
        builder = builder.with_persist(Box::new(FlutterPersist {
            relay: relay.clone(),
        }));
    }
    Ok(builder)
}

#[derive(Clone)]
struct FlutterNet {
    relay: Arc<Mutex<RelayState>>,
}

impl NetCapability for FlutterNet {
    fn http_request(&mut self, req: &[u8]) -> i32 {
        let Ok(mut relay) = self.relay.lock() else {
            return -1;
        };
        let handle = relay.alloc_handle();
        relay.http.insert(handle, HttpSlot::default());
        relay.events.push_back(EgressRelayEvent::HttpRequest {
            handle,
            request: req.to_vec(),
        });
        handle
    }

    fn http_poll(&mut self, handle: i32, buf: &mut [u8]) -> i32 {
        let Ok(relay) = self.relay.lock() else {
            return -1;
        };
        let Some(slot) = relay.http.get(&handle) else {
            return -1;
        };
        if !slot.done {
            return 0;
        }
        if slot.failed {
            return -1;
        }
        let n = slot.head.len().min(buf.len());
        buf[..n].copy_from_slice(&slot.head[..n]);
        n as i32
    }

    fn http_body(&mut self, handle: i32, buf: &mut [u8]) -> i32 {
        let Ok(mut relay) = self.relay.lock() else {
            return -1;
        };
        let Some(slot) = relay.http.get_mut(&handle) else {
            return -1;
        };
        if !slot.done {
            return 0;
        }
        if slot.failed {
            return -1;
        }
        let start = slot.body_pos.min(slot.body.len());
        let n = (slot.body.len() - start).min(buf.len());
        buf[..n].copy_from_slice(&slot.body[start..start + n]);
        slot.body_pos += n;
        n as i32
    }

    fn http_close(&mut self, handle: i32) {
        if let Ok(mut relay) = self.relay.lock() {
            relay.http.remove(&handle);
        }
    }

    fn ws_connect(&mut self, url: &str) -> i32 {
        let Ok(mut relay) = self.relay.lock() else {
            return -1;
        };
        let handle = relay.alloc_handle();
        relay.ws.insert(handle, WsSlot::default());
        relay.events.push_back(EgressRelayEvent::WsConnect {
            handle,
            url: url.to_string(),
        });
        handle
    }

    fn ws_send(&mut self, handle: i32, data: &[u8]) -> i32 {
        let Ok(mut relay) = self.relay.lock() else {
            return -1;
        };
        let Some(slot) = relay.ws.get_mut(&handle) else {
            return -1;
        };
        if slot.failed {
            return -1;
        }
        if data.len() > WS_SEND_MARK {
            return -1;
        }
        if !slot.open || slot.queued_bytes + data.len() > WS_SEND_MARK {
            return -1;
        }
        slot.queued_bytes += data.len();
        relay.events.push_back(EgressRelayEvent::WsSend {
            handle,
            data: data.to_vec(),
        });
        data.len() as i32
    }

    fn ws_ready(&mut self, handle: i32) -> i32 {
        let Ok(relay) = self.relay.lock() else {
            return 1;
        };
        let Some(slot) = relay.ws.get(&handle) else {
            return 1;
        };
        if slot.failed || (slot.open && slot.queued_bytes < WS_SEND_MARK) {
            1
        } else {
            0
        }
    }

    fn ws_recv(&mut self, handle: i32, buf: &mut [u8]) -> i32 {
        let Ok(mut relay) = self.relay.lock() else {
            return -1;
        };
        let Some(slot) = relay.ws.get_mut(&handle) else {
            return -1;
        };
        if slot.failed {
            return -1;
        }
        let Some(front) = slot.incoming.front() else {
            return 0;
        };
        let n = (front.len() - slot.incoming_pos).min(buf.len());
        buf[..n].copy_from_slice(&front[slot.incoming_pos..slot.incoming_pos + n]);
        slot.incoming_pos += n;
        if slot.incoming_pos >= front.len() {
            slot.incoming.pop_front();
            slot.incoming_pos = 0;
        }
        n as i32
    }

    fn ws_close(&mut self, handle: i32) {
        if let Ok(mut relay) = self.relay.lock() {
            relay.ws.remove(&handle);
            relay.events.push_back(EgressRelayEvent::WsClose { handle });
        }
    }
}

#[derive(Clone)]
struct FlutterHostCall {
    relay: Arc<Mutex<RelayState>>,
    sidecar_only: bool,
}

impl HostCallCapability for FlutterHostCall {
    fn start(&mut self, req: &[u8]) -> i32 {
        // req is name\0body
        let (name, body) = match req.iter().position(|&b| b == 0) {
            Some(i) => (
                String::from_utf8_lossy(&req[..i]).into_owned(),
                req[i + 1..].to_vec(),
            ),
            None => (String::from_utf8_lossy(req).into_owned(), Vec::new()),
        };
        let Ok(mut relay) = self.relay.lock() else {
            return -1;
        };
        let handle = relay.alloc_handle();
        relay.host_calls.insert(
            handle,
            HostCallSlot {
                sidecar: self.sidecar_only,
                ..Default::default()
            },
        );
        relay.events.push_back(EgressRelayEvent::HostCall {
            handle,
            name,
            body,
        });
        handle
    }

    fn poll(&mut self, handle: i32) -> i32 {
        let Ok(relay) = self.relay.lock() else {
            return -1;
        };
        let Some(slot) = relay.host_calls.get(&handle) else {
            return -1;
        };
        if slot.failed {
            return -1;
        }
        if slot.done {
            1
        } else {
            0
        }
    }

    fn body(&mut self, handle: i32, buf: &mut [u8]) -> i32 {
        let Ok(mut relay) = self.relay.lock() else {
            return -1;
        };
        let Some(slot) = relay.host_calls.get_mut(&handle) else {
            return -1;
        };
        if !slot.done {
            return 0;
        }
        if slot.failed {
            return -1;
        }
        let remaining = slot.result.len().saturating_sub(slot.offset);
        if remaining == 0 {
            return 0;
        }
        let n = remaining.min(buf.len());
        buf[..n].copy_from_slice(&slot.result[slot.offset..slot.offset + n]);
        slot.offset += n;
        n as i32
    }

    fn close(&mut self, handle: i32) {
        if let Ok(mut relay) = self.relay.lock() {
            let sidecar = relay
                .host_calls
                .get(&handle)
                .map(|s| s.sidecar)
                .unwrap_or(false);
            relay.host_calls.remove(&handle);
            relay.events.push_back(EgressRelayEvent::HostCallClose {
                handle,
                sidecar,
            });
        }
    }
}

#[derive(Clone)]
struct FlutterPersist {
    relay: Arc<Mutex<RelayState>>,
}

impl PersistCapability for FlutterPersist {
    fn start(&mut self, req: &[u8]) -> i32 {
        // Op-tagged request: [op:u32 LE][key_len:u32][key][value…]
        if req.len() < 8 {
            return -1;
        }
        let op = u32::from_le_bytes(req[0..4].try_into().unwrap());
        let key_len = u32::from_le_bytes(req[4..8].try_into().unwrap()) as usize;
        if req.len() < 8 + key_len {
            return -1;
        }
        let key = req[8..8 + key_len].to_vec();
        let value = req[8 + key_len..].to_vec();
        let Ok(mut relay) = self.relay.lock() else {
            return -1;
        };
        let handle = relay.alloc_handle();
        relay.persist.insert(handle, PersistSlot::default());
        let ev = match op {
            0 => EgressRelayEvent::PersistGet { handle, key },
            1 => EgressRelayEvent::PersistPut {
                handle,
                key,
                value,
            },
            2 => EgressRelayEvent::PersistDelete { handle, key },
            3 => EgressRelayEvent::PersistList {
                handle,
                prefix: key,
            },
            _ => return -1,
        };
        relay.events.push_back(ev);
        handle
    }

    fn poll(&mut self, handle: i32) -> i32 {
        let Ok(relay) = self.relay.lock() else {
            return -1;
        };
        let Some(slot) = relay.persist.get(&handle) else {
            return -1;
        };
        if slot.failed {
            return -1;
        }
        if slot.done {
            1
        } else {
            0
        }
    }

    fn body(&mut self, handle: i32, buf: &mut [u8]) -> i32 {
        let Ok(mut relay) = self.relay.lock() else {
            return -1;
        };
        let Some(slot) = relay.persist.get_mut(&handle) else {
            return -1;
        };
        if !slot.done {
            return 0;
        }
        if slot.failed {
            return -1;
        }
        let remaining = slot.result.len().saturating_sub(slot.offset);
        if remaining == 0 {
            return 0;
        }
        let n = remaining.min(buf.len());
        buf[..n].copy_from_slice(&slot.result[slot.offset..slot.offset + n]);
        slot.offset += n;
        n as i32
    }

    fn close(&mut self, handle: i32) {
        if let Ok(mut relay) = self.relay.lock() {
            relay.persist.remove(&handle);
        }
    }
}

fn encode_event(ev: &EgressRelayEvent) -> Vec<u8> {
    let s = match ev {
        EgressRelayEvent::HttpRequest { handle, request } => format!(
            "{{\"kind\":\"http\",\"handle\":{},\"request_len\":{}}}",
            handle,
            request.len()
        ),
        EgressRelayEvent::HostCall { handle, name, body } => format!(
            "{{\"kind\":\"host_call\",\"handle\":{},\"name\":{:?},\"body_len\":{}}}",
            handle, name, body.len()
        ),
        EgressRelayEvent::HostCallClose { handle, sidecar } => format!(
            "{{\"kind\":\"host_call_close\",\"handle\":{},\"sidecar\":{}}}",
            handle, sidecar
        ),
        EgressRelayEvent::PersistGet { handle, key } => {
            format!(
                "{{\"kind\":\"persist_get\",\"handle\":{},\"key_len\":{}}}",
                handle,
                key.len()
            )
        }
        EgressRelayEvent::PersistPut { handle, key, value } => format!(
            "{{\"kind\":\"persist_put\",\"handle\":{},\"key_len\":{},\"value_len\":{}}}",
            handle,
            key.len(),
            value.len()
        ),
        EgressRelayEvent::PersistDelete { handle, key } => format!(
            "{{\"kind\":\"persist_delete\",\"handle\":{},\"key_len\":{}}}",
            handle,
            key.len()
        ),
        EgressRelayEvent::PersistList { handle, prefix } => format!(
            "{{\"kind\":\"persist_list\",\"handle\":{},\"prefix_len\":{}}}",
            handle,
            prefix.len()
        ),
        EgressRelayEvent::WsConnect { handle, url } => {
            format!(
                "{{\"kind\":\"ws_connect\",\"handle\":{},\"url\":{:?}}}",
                handle, url
            )
        }
        EgressRelayEvent::WsSend { handle, data } => format!(
            "{{\"kind\":\"ws_send\",\"handle\":{},\"data_len\":{}}}",
            handle,
            data.len()
        ),
        EgressRelayEvent::WsClose { handle } => {
            format!("{{\"kind\":\"ws_close\",\"handle\":{}}}", handle)
        }
        EgressRelayEvent::ToolApproval {
            handle,
            connection,
            method,
            url,
            origin,
            args_digest,
        } => format!(
            "{{\"kind\":\"tool_approval\",\"handle\":{},\"connection\":{:?},\"method\":{:?},\"url\":{:?},\"origin\":{:?},\"args_digest\":{:?}}}",
            handle, connection, method, url, origin, args_digest
        ),
    };
    let mut out = s.into_bytes();
    out.push(0);
    match ev {
        EgressRelayEvent::HttpRequest { request, .. } => out.extend_from_slice(request),
        EgressRelayEvent::HostCall { body, .. } => out.extend_from_slice(body),
        EgressRelayEvent::PersistGet { key, .. }
        | EgressRelayEvent::PersistDelete { key, .. } => out.extend_from_slice(key),
        EgressRelayEvent::PersistPut { key, value, .. } => {
            out.extend_from_slice(&(key.len() as u32).to_le_bytes());
            out.extend_from_slice(key);
            out.extend_from_slice(value);
        }
        EgressRelayEvent::PersistList { prefix, .. } => out.extend_from_slice(prefix),
        EgressRelayEvent::WsSend { data, .. } => out.extend_from_slice(data),
        _ => {}
    }
    out
}

fn pop_event(vm: u64, sidecar_only: bool) -> Result<Option<Vec<u8>>, String> {
    with_vm(vm, |entry| {
        let mut relay = entry
            .relay
            .lock()
            .map_err(|_| "relay lock poisoned".to_string())?;
        if sidecar_only {
            let pos = relay.events.iter().position(|e| {
                matches!(
                    e,
                    EgressRelayEvent::HostCall { handle, .. }
                        if relay.host_calls.get(handle).map(|s| s.sidecar).unwrap_or(false)
                )
            });
            if let Some(i) = pos {
                let ev = relay.events.remove(i).unwrap();
                return Ok(Some(encode_event(&ev)));
            }
            return Ok(None);
        }
        Ok(relay.events.pop_front().map(|ev| encode_event(&ev)))
    })
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_relay_next(vm: u64, out_frame: *mut AosBuf) -> i32 {
    clear_error();
    if out_frame.is_null() {
        set_error("aos_vm_relay_next: null out");
        return -1;
    }
    match pop_event(vm, false) {
        Ok(None) => {
            (*out_frame).len = 0;
            0
        }
        Ok(Some(bytes)) => fill_buf(out_frame, &bytes),
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_relay_next_sidecar(vm: u64, out_frame: *mut AosBuf) -> i32 {
    clear_error();
    if out_frame.is_null() {
        set_error("aos_vm_relay_next_sidecar: null out");
        return -1;
    }
    match pop_event(vm, true) {
        Ok(None) => {
            (*out_frame).len = 0;
            0
        }
        Ok(Some(bytes)) => fill_buf(out_frame, &bytes),
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_relay_http_respond(
    vm: u64,
    handle: i64,
    ok: i32,
    head: *const u8,
    head_len: usize,
    body: *const u8,
    body_len: usize,
) -> i32 {
    clear_error();
    if vm == 0 || handle <= 0 {
        set_error("aos_vm_relay_http_respond: invalid args");
        return -1;
    }
    let head = if head_len == 0 || head.is_null() {
        Vec::new()
    } else {
        std::slice::from_raw_parts(head, head_len).to_vec()
    };
    let body = if body_len == 0 || body.is_null() {
        Vec::new()
    } else {
        std::slice::from_raw_parts(body, body_len).to_vec()
    };
    match with_vm(vm, |entry| {
        let mut relay = entry
            .relay
            .lock()
            .map_err(|_| "relay lock poisoned".to_string())?;
        let slot = relay
            .http
            .get_mut(&(handle as i32))
            .ok_or_else(|| "unknown http handle".to_string())?;
        slot.done = true;
        slot.failed = ok == 0;
        slot.head = head;
        slot.body = body;
        slot.body_pos = 0;
        Ok(())
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_relay_host_call_respond(
    vm: u64,
    handle: i64,
    ok: i32,
    result: *const u8,
    result_len: usize,
) -> i32 {
    clear_error();
    if vm == 0 || handle <= 0 {
        set_error("invalid args");
        return -1;
    }
    let result = if result_len == 0 || result.is_null() {
        Vec::new()
    } else {
        std::slice::from_raw_parts(result, result_len).to_vec()
    };
    match with_vm(vm, |entry| {
        let mut relay = entry
            .relay
            .lock()
            .map_err(|_| "relay lock poisoned".to_string())?;
        let slot = relay
            .host_calls
            .get_mut(&(handle as i32))
            .ok_or_else(|| "unknown host_call handle".to_string())?;
        slot.done = true;
        slot.failed = ok == 0;
        slot.result = result;
        slot.offset = 0;
        Ok(())
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_relay_persist_respond(
    vm: u64,
    handle: i64,
    ok: i32,
    body: *const u8,
    body_len: usize,
) -> i32 {
    clear_error();
    if vm == 0 || handle <= 0 {
        set_error("invalid args");
        return -1;
    }
    let body = if body_len == 0 || body.is_null() {
        Vec::new()
    } else {
        std::slice::from_raw_parts(body, body_len).to_vec()
    };
    match with_vm(vm, |entry| {
        let mut relay = entry
            .relay
            .lock()
            .map_err(|_| "relay lock poisoned".to_string())?;
        let slot = relay
            .persist
            .get_mut(&(handle as i32))
            .ok_or_else(|| "unknown persist handle".to_string())?;
        slot.done = true;
        slot.failed = ok == 0;
        slot.result = body;
        slot.offset = 0;
        Ok(())
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_relay_tool_approval_respond(
    vm: u64,
    handle: i64,
    allow: i32,
    remember_session: i32,
) -> i32 {
    clear_error();
    if vm == 0 || handle <= 0 {
        set_error("invalid args");
        return -1;
    }
    match with_vm(vm, |entry| {
        let mut relay = entry
            .relay
            .lock()
            .map_err(|_| "relay lock poisoned".to_string())?;
        if let Some(tx) = relay.pending_tool_approvals.remove(&(handle as i32)) {
            let _ = tx.send(ToolApprovalDecision {
                allow: allow != 0,
                remember_session: remember_session != 0,
            });
        }
        Ok(())
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_relay_ws_open(vm: u64, handle: i64, ok: i32) -> i32 {
    clear_error();
    match with_vm(vm, |entry| {
        let mut relay = entry
            .relay
            .lock()
            .map_err(|_| "relay lock poisoned".to_string())?;
        let slot = relay
            .ws
            .get_mut(&(handle as i32))
            .ok_or_else(|| "unknown ws handle".to_string())?;
        slot.open = ok != 0;
        slot.failed = ok == 0;
        Ok(())
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_relay_ws_push(
    vm: u64,
    handle: i64,
    data: *const u8,
    len: usize,
) -> i32 {
    clear_error();
    let data = if len == 0 || data.is_null() {
        Vec::new()
    } else {
        std::slice::from_raw_parts(data, len).to_vec()
    };
    match with_vm(vm, |entry| {
        let mut relay = entry
            .relay
            .lock()
            .map_err(|_| "relay lock poisoned".to_string())?;
        let slot = relay
            .ws
            .get_mut(&(handle as i32))
            .ok_or_else(|| "unknown ws handle".to_string())?;
        slot.incoming.push_back(data);
        Ok(())
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_relay_ws_close(vm: u64, handle: i64) -> i32 {
    clear_error();
    match with_vm(vm, |entry| {
        let mut relay = entry
            .relay
            .lock()
            .map_err(|_| "relay lock poisoned".to_string())?;
        if let Some(slot) = relay.ws.get_mut(&(handle as i32)) {
            slot.open = false;
        }
        Ok(())
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}
