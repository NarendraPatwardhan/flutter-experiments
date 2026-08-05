//! Relay queues — translation of NIF BeamNet / BeamHostCall / BeamPersist.
//!
//! Egress frames use the contract-generated `ctl_rust::RelayEvent` wire codec
//! (same bytes as the Elixir NIF `relay_next`). Dart should decode with that
//! schema (`control.kdl` message `RelayEvent` id=8 version=1).

use std::sync::{Arc, Mutex};

use ctl_rust::RelayEvent as WireRelayEvent;
use host::{
    derive_connection_origins, ConnectionCredential, ConnectionPolicyAction, ConnectionPolicyOwner,
    ConnectionPolicyRule, ConnectionRegistry, HostCallCapability, KernelHostBuilder,
    NetCapability, PersistCapability, RealNet, ToolApprovalDecision as HostToolApprovalDecision,
    ToolApprovalFacts, ToolApprover,
};
use json::{parse as json_parse, Json};

use crate::buf::{fill_buf, AosBuf};
use crate::error::{clear_error, set_error};
use crate::table::{
    with_vm, EgressRelayEvent, HostCallSlot, HttpSlot, PersistSlot, RelayState, ToolApprovalDecision,
    WsSlot,
};

const WS_SEND_MARK: usize = 256 * 1024;

/// Must match `sidecar_rust::SIDECAR_HOST_BINDING` / `sidecar.gen.rs`.
const SIDECAR_HOST_BINDING: &str = "mc.sidecar";

/// net/host_call/persist: 0=deny (builder default), 1=relay, 2=real net (net only).
pub fn apply_boot_caps(
    mut builder: KernelHostBuilder,
    net: i32,
    host_call: i32,
    host_call_sidecar_only: bool,
    persist: i32,
    tool_approval: i32,
    connections: Option<Vec<u8>>,
    policies: Option<Vec<u8>>,
    relay: &Arc<Mutex<RelayState>>,
) -> Result<KernelHostBuilder, String> {
    match net {
        0 => {
            if connections.as_ref().is_some_and(|b| !b.is_empty())
                || policies.as_ref().is_some_and(|b| !b.is_empty())
                || tool_approval != 0
            {
                return Err(
                    "connections, connection_policies, and tool_approval require AOS_NET_REAL (net=2)"
                        .into(),
                );
            }
        }
        1 => {
            if connections.as_ref().is_some_and(|b| !b.is_empty())
                || policies.as_ref().is_some_and(|b| !b.is_empty())
            {
                return Err(
                    "connection credentials/policies require AOS_NET_REAL (net=2); use relay for app-owned HTTP"
                        .into(),
                );
            }
            if tool_approval != 0 {
                return Err(
                    "tool_approval requires AOS_NET_REAL (net=2); relay net does not run the gate"
                        .into(),
                );
            }
            builder = builder.with_net(Box::new(FlutterNet {
                relay: relay.clone(),
            }));
        }
        2 => {
            let registry = parse_connections_blob(connections.as_deref().unwrap_or(&[]))?;
            let rules = parse_policies_blob(policies.as_deref().unwrap_or(&[]))?;
            let mut net = RealNet::new()
                .with_connections(registry)
                .with_connection_policies(rules)
                .map_err(|e| format!("invalid connection policies: {e:#}"))?;
            if tool_approval != 0 {
                net = net.with_tool_approver(Arc::new(FlutterToolApprover {
                    relay: relay.clone(),
                }));
            }
            builder = builder.with_net(Box::new(net));
        }
        other => {
            return Err(format!(
                "unknown net capability {other} (0=deny, 1=relay, 2=real)"
            ));
        }
    }

    if host_call == 1 {
        builder = builder.with_host_call(Box::new(FlutterHostCall {
            relay: relay.clone(),
            sidecar_only: host_call_sidecar_only,
        }));
    } else if host_call != 0 {
        return Err(format!(
            "unknown host_call capability {host_call} (0=deny, 1=relay)"
        ));
    }

    if persist == 1 {
        builder = builder.with_persist(Box::new(FlutterPersist {
            relay: relay.clone(),
        }));
    } else if persist != 0 {
        return Err(format!(
            "unknown persist capability {persist} (0=deny, 1=relay)"
        ));
    }

    Ok(builder)
}

// ---------- Boot JSON: connections + policies (AOS_NET_REAL) ----------

/// Connections blob: JSON array of
/// `{ "reference", "kind": "none|bearer|header|query", "a", "b", "origins": [] }`.
fn parse_connections_blob(blob: &[u8]) -> Result<ConnectionRegistry, String> {
    let mut registry = ConnectionRegistry::new();
    if blob.is_empty() {
        return Ok(registry);
    }
    let text = std::str::from_utf8(blob)
        .map_err(|_| "connections_blob must be UTF-8 JSON".to_string())?;
    let root = json_parse(text).map_err(|_| "connections_blob is not valid JSON".to_string())?;
    let arr = root
        .as_arr()
        .ok_or_else(|| "connections_blob must be a JSON array".to_string())?;
    for (i, item) in arr.iter().enumerate() {
        let o = item
            .as_obj()
            .ok_or_else(|| format!("connections[{i}] must be an object"))?;
        let reference = obj_require_str(o, "reference", i)?;
        let kind = obj_opt_str(o, "kind").unwrap_or_else(|| "none".into());
        let a = obj_opt_str(o, "a").unwrap_or_default();
        let b = obj_opt_str(o, "b").unwrap_or_default();
        let credential = build_credential(&kind, a, b)
            .map_err(|e| format!("connections[{i}]: {e}"))?;
        let origins = match obj_get(o, "origins") {
            None | Some(Json::Null) => Vec::new(),
            Some(v) => string_array(v, &format!("connections[{i}].origins"))?,
        };
        let origins = if origins.is_empty() {
            derive_connection_origins(&reference)
        } else {
            origins
        };
        registry
            .insert(reference.clone(), credential, origins)
            .map_err(|e| format!("connections[{i}] {reference:?}: {e:?}"))?;
    }
    Ok(registry)
}

/// Policies blob: JSON array of `{ "owner": "org|user", "pattern", "action": "approve|require_approval|block" }`.
fn parse_policies_blob(blob: &[u8]) -> Result<Vec<ConnectionPolicyRule>, String> {
    if blob.is_empty() {
        return Ok(Vec::new());
    }
    let text = std::str::from_utf8(blob)
        .map_err(|_| "connection_policies_blob must be UTF-8 JSON".to_string())?;
    let root =
        json_parse(text).map_err(|_| "connection_policies_blob is not valid JSON".to_string())?;
    let arr = root
        .as_arr()
        .ok_or_else(|| "connection_policies_blob must be a JSON array".to_string())?;
    let mut out = Vec::with_capacity(arr.len());
    for (i, item) in arr.iter().enumerate() {
        let o = item
            .as_obj()
            .ok_or_else(|| format!("policies[{i}] must be an object"))?;
        let owner = match obj_require_str(o, "owner", i)?.as_str() {
            "org" => ConnectionPolicyOwner::Org,
            "user" => ConnectionPolicyOwner::User,
            other => {
                return Err(format!(
                    "policies[{i}].owner unknown {other:?} (want org|user)"
                ))
            }
        };
        let pattern = obj_require_str(o, "pattern", i)?;
        let action = match obj_require_str(o, "action", i)?.as_str() {
            "approve" => ConnectionPolicyAction::Approve,
            "require_approval" => ConnectionPolicyAction::RequireApproval,
            "block" => ConnectionPolicyAction::Block,
            other => {
                return Err(format!(
                    "policies[{i}].action unknown {other:?} (want approve|require_approval|block)"
                ))
            }
        };
        out.push(ConnectionPolicyRule {
            owner,
            pattern,
            action,
        });
    }
    Ok(out)
}

fn build_credential(kind: &str, a: String, b: String) -> Result<ConnectionCredential, String> {
    match kind {
        "none" => Ok(ConnectionCredential::None),
        "bearer" => Ok(ConnectionCredential::Bearer { token: a }),
        "header" => Ok(ConnectionCredential::Header { name: a, value: b }),
        "query" => Ok(ConnectionCredential::Query { name: a, value: b }),
        other => Err(format!(
            "unknown credential kind {other:?} (want none|bearer|header|query)"
        )),
    }
}

fn obj_get<'a>(obj: &'a [(String, Json)], key: &str) -> Option<&'a Json> {
    obj.iter().find(|(k, _)| k == key).map(|(_, v)| v)
}

fn obj_opt_str(obj: &[(String, Json)], key: &str) -> Option<String> {
    match obj_get(obj, key) {
        Some(Json::Str(s)) if !s.is_empty() => Some(s.clone()),
        _ => None,
    }
}

fn obj_require_str(obj: &[(String, Json)], key: &str, i: usize) -> Result<String, String> {
    match obj_get(obj, key) {
        Some(Json::Str(s)) if !s.is_empty() => Ok(s.clone()),
        Some(Json::Str(_)) => Err(format!("item[{i}].{key} must be non-empty")),
        Some(_) => Err(format!("item[{i}].{key} must be a string")),
        None => Err(format!("item[{i}] missing {key:?}")),
    }
}

fn string_array(v: &Json, label: &str) -> Result<Vec<String>, String> {
    let arr = v
        .as_arr()
        .ok_or_else(|| format!("{label} must be a JSON array of strings"))?;
    let mut out = Vec::with_capacity(arr.len());
    for (j, item) in arr.iter().enumerate() {
        let s = item
            .as_str()
            .ok_or_else(|| format!("{label}[{j}] must be a string"))?;
        out.push(s.to_string());
    }
    Ok(out)
}

// ---------- Relay caps ----------

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
struct FlutterToolApprover {
    relay: Arc<Mutex<RelayState>>,
}

impl ToolApprover for FlutterToolApprover {
    fn approve(&self, facts: ToolApprovalFacts) -> HostToolApprovalDecision {
        let deny = HostToolApprovalDecision {
            allow: false,
            remember_session: false,
        };
        let rx = {
            let Ok(mut relay) = self.relay.lock() else {
                return deny;
            };
            let handle = relay.alloc_handle();
            let (tx, rx) = std::sync::mpsc::channel();
            relay.pending_tool_approvals.insert(handle, tx);
            relay.events.push_back(EgressRelayEvent::ToolApproval {
                handle,
                connection: facts.connection,
                method: facts.method,
                url: facts.url,
                origin: facts.origin,
                args_digest: facts.args_digest,
            });
            rx
        };
        match rx.recv() {
            Ok(d) => HostToolApprovalDecision {
                allow: d.allow,
                remember_session: d.remember_session,
            },
            Err(_) => deny,
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
        let nul = req.iter().position(|&b| b == 0).unwrap_or(req.len());
        let name = String::from_utf8_lossy(&req[..nul]).into_owned();
        if self.sidecar_only && name != SIDECAR_HOST_BINDING {
            return -1;
        }
        let body = if nul < req.len() {
            req[nul + 1..].to_vec()
        } else {
            Vec::new()
        };
        let Ok(mut relay) = self.relay.lock() else {
            return -1;
        };
        let handle = relay.alloc_handle();
        relay.host_calls.insert(
            handle,
            HostCallSlot {
                sidecar: name == SIDECAR_HOST_BINDING,
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

// ---------- Wire: ctl_rust::RelayEvent (NIF parity) ----------

fn relay_frame(kind: &str, handle: i32) -> WireRelayEvent {
    WireRelayEvent {
        kind: kind.to_string(),
        handle,
        request: None,
        name: None,
        body: None,
        key: None,
        value: None,
        prefix: None,
        url: None,
        data: None,
        connection: None,
        method: None,
        origin: None,
        args_digest: None,
    }
}

fn wire_relay_event(relay: &mut RelayState, event: EgressRelayEvent) -> WireRelayEvent {
    match event {
        EgressRelayEvent::HttpRequest { handle, request } => {
            let mut frame = relay_frame("http", handle);
            frame.request = Some(request);
            frame
        }
        EgressRelayEvent::HostCall { handle, name, body } => {
            let mut frame = relay_frame("host_call", handle);
            frame.name = Some(name);
            frame.body = Some(body);
            frame
        }
        EgressRelayEvent::HostCallClose { handle, sidecar } => {
            let mut frame = relay_frame("host_call_close", handle);
            if sidecar {
                frame.name = Some(SIDECAR_HOST_BINDING.to_string());
            }
            frame
        }
        EgressRelayEvent::PersistGet { handle, key } => {
            let mut frame = relay_frame("persist_get", handle);
            frame.key = Some(key);
            frame
        }
        EgressRelayEvent::PersistPut { handle, key, value } => {
            let mut frame = relay_frame("persist_put", handle);
            frame.key = Some(key);
            frame.value = Some(value);
            frame
        }
        EgressRelayEvent::PersistDelete { handle, key } => {
            let mut frame = relay_frame("persist_delete", handle);
            frame.key = Some(key);
            frame
        }
        EgressRelayEvent::PersistList { handle, prefix } => {
            let mut frame = relay_frame("persist_list", handle);
            frame.prefix = Some(prefix);
            frame
        }
        EgressRelayEvent::WsConnect { handle, url } => {
            let mut frame = relay_frame("ws_connect", handle);
            frame.url = Some(url);
            frame
        }
        EgressRelayEvent::WsSend { handle, data } => {
            if let Some(slot) = relay.ws.get_mut(&handle) {
                slot.queued_bytes = slot.queued_bytes.saturating_sub(data.len());
            }
            let mut frame = relay_frame("ws_send", handle);
            frame.data = Some(data);
            frame
        }
        EgressRelayEvent::WsClose { handle } => relay_frame("ws_close", handle),
        EgressRelayEvent::ToolApproval {
            handle,
            connection,
            method,
            url,
            origin,
            args_digest,
        } => {
            let mut frame = relay_frame("tool_approval", handle);
            frame.connection = Some(connection);
            frame.method = Some(method);
            frame.url = Some(url);
            frame.origin = Some(origin);
            frame.args_digest = args_digest;
            frame
        }
    }
}

fn dispatch_relay_event(relay: &mut RelayState, event: EgressRelayEvent) -> Vec<u8> {
    if let EgressRelayEvent::HostCall { handle, .. } = &event {
        if let Some(slot) = relay.host_calls.get_mut(handle) {
            slot.dispatched = true;
        }
    }
    wire_relay_event(relay, event).encode()
}

fn is_sidecar_event(event: &EgressRelayEvent) -> bool {
    matches!(
        event,
        EgressRelayEvent::HostCall { name, .. } if name == SIDECAR_HOST_BINDING
    ) || matches!(event, EgressRelayEvent::HostCallClose { sidecar: true, .. })
}

fn pop_event(vm: u64, sidecar_only: bool) -> Result<Option<Vec<u8>>, String> {
    with_vm(vm, |entry| {
        let mut relay = entry
            .relay
            .lock()
            .map_err(|_| "relay lock poisoned".to_string())?;
        if sidecar_only {
            let pos = relay.events.iter().position(is_sidecar_event);
            if let Some(i) = pos {
                let ev = relay.events.remove(i).unwrap();
                return Ok(Some(dispatch_relay_event(&mut relay, ev)));
            }
            return Ok(None);
        }
        Ok(relay
            .events
            .pop_front()
            .map(|ev| dispatch_relay_event(&mut relay, ev)))
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
        set_error("aos_vm_relay_host_call_respond: invalid args");
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
        set_error("aos_vm_relay_persist_respond: invalid args");
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
        set_error("aos_vm_relay_tool_approval_respond: invalid args");
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
    if vm == 0 || handle <= 0 {
        set_error("aos_vm_relay_ws_open: invalid args");
        return -1;
    }
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
    if vm == 0 || handle <= 0 {
        set_error("aos_vm_relay_ws_push: invalid args");
        return -1;
    }
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
    if vm == 0 || handle <= 0 {
        set_error("aos_vm_relay_ws_close: invalid args");
        return -1;
    }
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
