# AgentOS Flutter host — C ABI sketch

Working notes for expanding `libagentos_flutter_host` toward Elixir NIF parity.

**This document is not sacred.** It is not `SYSTEM.md`. Alpha code and this sketch may both change. Prefer a clean break over shims when the design is wrong.

Related:

- Permanent rules: `SYSTEM.md`, `AGENTS.md`
- Current first-cut surface: `docs/native-host-ffi.md`, `native/agentos_flutter_host/include/agentos_flutter_host.h`
- Elixir reference: `AgentOS.Host.Nif` over `host::KernelHost` (agent-os pin)

---

## 1. Role of the C ABI

| Role | Elixir | Flutter product |
|------|--------|-----------------|
| Real host | `KernelHost` (Rust / wasmtime) | same `@agent-os` `KernelHost` |
| Thin adapter | `libhost_nif.so` (Rustler) | `libagentos_flutter_host.so` (C ABI) |
| Owner / policy | `AgentOS.Vm` GenServer | Dart session owner (one worker isolate) |

Rules:

1. The adapter does **not** reimplement the host.
2. C is the stable language boundary (Dart, tests, later mobile).
3. Errors are values (no panic across FFI).
4. One owner per VM handle; serialize all access.
5. Ghostty / paint / window chrome stay **out** of this `.so`.

---

## 2. Coverage today vs Elixir NIF

### Present (first cut)

| Elixir | Flutter C today | Notes |
|--------|-----------------|--------|
| `boot(wasm, base, opts)` | `aos_vm_boot(kernel, image)` | Single base image; **no opts** |
| `tick` | `aos_vm_tick` | runnable / waiting / exited |
| `send_input` | `aos_vm_send_input` | Exists; UI barely uses it |
| `take_output` | `aos_vm_take_output` | stdout+stderr+log merged |
| `exec` | `aos_vm_exec` | No cwd / env / stdin |
| resource drop | `aos_vm_close` | Explicit close |
| `{:error, reason}` | `aos_last_error` | Thread-local string |

### Missing (major clusters)

| Cluster | Elixir examples | Product need |
|---------|-----------------|--------------|
| Boot policy | layers, deterministic, contract, workers, net, connections, host_call, persist, tool_approval | Real capabilities; default deny |
| Restore | `restore` | Session resume / fork |
| Argv run | `run`, `run_start` | Safer than shell string |
| Async jobs | `exec_start`, `exec_poll`, `exec_stdout_peek`, `exec_cancel` | Non-blocking UI |
| Autocomplete | `autocomplete` | Shell UX |
| Services | `svc_call` | Resident services |
| Host FS control | `read_file`, `write_file`, `readdir`, `stat`, … | Control UI without shell |
| Layers | `commit_layer` | Persist CoW overlay |
| Status | `status` (`at_prompt`, workers, egress, …) | Drive terminal chrome |
| Snapshots | `snapshot`, `snapshot_incremental` | Save / restore machine |
| Catalog | `inject_catalog` | Tools / connections |
| Relay | `relay_next` + respond family | Egress; without respond, modes hang |
| Perf | `set_perf_enabled`, `take_command_perf` | Diagnostics |

We have the **terminal smoke core**, not the full control plane.

---

## 3. Design principles (C shape)

1. **Same host, same semantics** — each entry maps to `KernelHost` (or tiny pure glue).
2. **Caller-owned buffers** — fill `ptr`/`cap`; set `len` (or required size on overflow).
3. **Capabilities at boot** — net / host_call / persist default **deny** for desktop until opted in.
4. **Relay is pull + respond** — drain events in Dart; answer through C. No arbitrary callbacks into the UI isolate from Rust threads.
5. **Prefer versioned blobs for complex data** — connections, relay frames, catalog status as length-prefixed CBOR/JSON rather than dozens of C structs forever.
6. **Alpha may rename** — use `AOS_API_VERSION` when the surface stabilizes; until then, break cleanly.

---

## 4. Ideal C API sketch

Conceptual. Names and packing can change.

### 4.1 Core types

```c
#define AOS_API_VERSION 1

typedef uint64_t aos_vm_t;   /* 0 invalid */

typedef enum {
  AOS_OK = 0,
  AOS_ERR = -1,
} aos_status_t;

typedef enum {
  AOS_TICK_RUNNABLE = 0,
  AOS_TICK_WAITING  = 1,
  AOS_TICK_EXITED   = 2,
} aos_tick_state_t;

/* Caller-owned byte buffer. */
typedef struct {
  uint8_t *ptr;
  size_t   cap;
  size_t   len;   /* out: written, or required if too small */
} aos_buf_t;

/* Library-allocated blob; free with aos_bytes_free. */
typedef struct {
  uint8_t *ptr;
  size_t   len;
} aos_bytes_t;

void aos_bytes_free(aos_bytes_t *b);

const char *aos_last_error(void);
int aos_api_version(void);
const char *aos_version(void);
```

Short-term errors may stay `int` + `aos_last_error()`. Ideal multi-worker: optional per-call error buffer so TLS is not the only channel.

### 4.2 Lifecycle and boot

```c
typedef enum {
  AOS_NET_DENY = 0,
  AOS_NET_RELAY = 1,
  AOS_NET_REAL = 2,
} aos_net_mode_t;

typedef enum {
  AOS_CAP_DENY = 0,
  AOS_CAP_RELAY = 1,
} aos_cap_mode_t;

typedef struct {
  size_t size;   /* sizeof — versioning */

  /* Image: base_image XOR layers (same exclusivity as NIF). */
  const uint8_t *base_image;
  size_t base_image_len;
  const uint8_t *const *layers;
  const size_t *layer_lens;
  size_t layer_count;

  int deterministic;
  int has_contract;
  int32_t contract_tier;
  int32_t contract_budget_mib;
  int64_t contract_fuel;

  uint32_t workers;   /* 0 = default */

  aos_net_mode_t net;
  aos_cap_mode_t host_call;
  int host_call_sidecar_only;
  aos_cap_mode_t persist;
  aos_cap_mode_t tool_approval;

  /* Connections / policies: opaque blobs compiled by Dart. */
  const uint8_t *connections_blob;
  size_t connections_len;
  const uint8_t *connection_policies_blob;
  size_t connection_policies_len;
} aos_boot_opts_t;

int aos_vm_boot(
    const uint8_t *kernel, size_t kernel_len,
    const aos_boot_opts_t *opts,
    aos_vm_t *out_vm);

int aos_vm_restore(
    const uint8_t *kernel, size_t kernel_len,
    const uint8_t *snapshot, size_t snapshot_len,
    const aos_boot_opts_t *opts,
    aos_vm_t *out_vm);

int aos_vm_close(aos_vm_t vm);
```

**Flutter terminal default:** `net/host_call/persist/tool_approval = deny`, single loom base image.

### 4.3 Terminal I/O (session spine)

```c
int aos_vm_tick(aos_vm_t vm, aos_tick_state_t *out_state);
int aos_vm_tick_n(aos_vm_t vm, uint32_t n, aos_tick_state_t *out_state);

int aos_vm_send_input(aos_vm_t vm, const uint8_t *data, size_t len);

int aos_vm_take_output(aos_vm_t vm, aos_buf_t *out);

typedef enum {
  AOS_STREAM_STDOUT = 1,
  AOS_STREAM_STDERR = 2,
  AOS_STREAM_LOG    = 4,
} aos_stream_mask_t;

int aos_vm_take_output_ex(aos_vm_t vm, int mask, aos_buf_t *out);
```

Product TTY may keep one “paint stream”; keep streams separable for structured jobs.

### 4.4 Structured process API

```c
typedef struct {
  size_t size;
  const char *cwd;
  const uint8_t *env_blob;
  size_t env_blob_len;
  const uint8_t *stdin_data;
  size_t stdin_len;
  uint64_t max_ticks;   /* 0 = default */
} aos_exec_opts_t;

int aos_vm_exec(
    aos_vm_t vm, const char *cmd,
    const aos_exec_opts_t *opts,
    aos_buf_t *stdout_b, aos_buf_t *stderr_b,
    int32_t *out_exit);

int aos_vm_run(
    aos_vm_t vm, const char *program,
    const char *const *argv, size_t argc,
    const aos_exec_opts_t *opts,
    aos_buf_t *stdout_b, aos_buf_t *stderr_b,
    int32_t *out_exit);

int aos_vm_exec_start(aos_vm_t vm, const char *cmd,
                      const aos_exec_opts_t *opts, int64_t *out_job);
int aos_vm_run_start(/* … */, int64_t *out_job);
int aos_vm_exec_poll(aos_vm_t vm, int64_t job,
                     int *out_done, int32_t *out_exit,
                     aos_buf_t *stdout_b, aos_buf_t *stderr_b);
int aos_vm_exec_stdout_peek(aos_vm_t vm, int64_t job, aos_buf_t *out);
int aos_vm_exec_cancel(aos_vm_t vm, int64_t job);
```

### 4.5 Shell UX

```c
int aos_vm_autocomplete(
    aos_vm_t vm,
    const char *source, size_t cursor_byte,
    const aos_exec_opts_t *opts,
    aos_buf_t *out_encoded);
```

### 4.6 Control-plane FS and services

```c
int aos_vm_svc_call(aos_vm_t vm, const char *service,
                    const uint8_t *req, size_t req_len,
                    int32_t *out_status, aos_buf_t *out_body);

int aos_vm_read_file(aos_vm_t vm, const char *path, aos_buf_t *out);
int aos_vm_write_file(aos_vm_t vm, const char *path,
                      const uint8_t *data, size_t len);
int aos_vm_readdir(aos_vm_t vm, const char *path, aos_buf_t *out_encoded);
int aos_vm_stat(aos_vm_t vm, const char *path, aos_stat_t *out);
int aos_vm_readlink(/* … */);
int aos_vm_mkdir(/* … */);
int aos_vm_unlink(/* … */);
int aos_vm_chmod(/* … */);
int aos_vm_symlink(/* … */);
int aos_vm_mount(aos_vm_t vm, const char *path, int read_only);
int aos_vm_unmount(aos_vm_t vm, const char *path);
```

Secondary for pure TTY; part of full NIF parity.

### 4.7 Snapshot, layer, status

```c
int aos_vm_snapshot(aos_vm_t vm, aos_bytes_t *out);
int aos_vm_snapshot_into(aos_vm_t vm, aos_buf_t *out);
int aos_vm_snapshot_incremental(
    aos_vm_t vm,
    const uint8_t *base, size_t base_len,
    aos_bytes_t *out);

int aos_vm_commit_layer(
    aos_vm_t vm, aos_bytes_t *out_tar, aos_buf_t *out_digest_hex);

typedef struct {
  size_t size;
  uint64_t bytes_written;
  int32_t exit_code;     /* sentinel = none */
  int at_prompt;
  uint32_t workers;
  int has_worker_entry;
  uint32_t inflight_egress;
  uint32_t pending_commits;
} aos_vm_status_t;

int aos_vm_status(aos_vm_t vm, aos_vm_status_t *out);
```

`at_prompt` is especially useful for terminal chrome.

### 4.8 Relay

Pull + respond, same as Elixir. Prefer **one versioned frame blob** + Dart decoder over a permanent forest of C structs.

```c
typedef enum {
  AOS_RELAY_NONE = 0,
  AOS_RELAY_HTTP,
  AOS_RELAY_HOST_CALL,
  AOS_RELAY_HOST_CALL_CLOSE,
  AOS_RELAY_PERSIST_GET,
  AOS_RELAY_PERSIST_PUT,
  AOS_RELAY_PERSIST_DELETE,
  AOS_RELAY_PERSIST_LIST,
  AOS_RELAY_WS_CONNECT,
  AOS_RELAY_WS_SEND,
  AOS_RELAY_WS_CLOSE,
  AOS_RELAY_TOOL_APPROVAL,
} aos_relay_kind_t;

int aos_vm_relay_next(aos_vm_t vm, aos_buf_t *out_frame);
int aos_vm_relay_next_sidecar(aos_vm_t vm, aos_buf_t *out_frame);

int aos_vm_relay_http_respond(
    aos_vm_t vm, int64_t handle, int ok,
    const uint8_t *head, size_t head_len,
    const uint8_t *body, size_t body_len);
int aos_vm_relay_host_call_respond(
    aos_vm_t vm, int64_t handle, int ok,
    const uint8_t *result, size_t len);
int aos_vm_relay_persist_respond(/* … */);
int aos_vm_relay_tool_approval_respond(
    aos_vm_t vm, int64_t handle, int allow, int remember_session);
int aos_vm_relay_ws_open(aos_vm_t vm, int64_t handle, int ok);
int aos_vm_relay_ws_push(
    aos_vm_t vm, int64_t handle, const uint8_t *data, size_t len);
int aos_vm_relay_ws_close(aos_vm_t vm, int64_t handle);
```

### 4.9 Catalog and perf (later)

```c
int aos_vm_inject_catalog(
    aos_vm_t vm,
    const uint8_t *compiler_wasm, size_t compiler_len,
    uint64_t generation,
    const uint8_t *catalog_blob, size_t catalog_len,
    aos_buf_t *out_status_encoded);

int aos_vm_set_perf_enabled(aos_vm_t vm, int on);
int aos_vm_scrub_perf(aos_vm_t vm);
int aos_vm_take_command_perf(aos_vm_t vm, aos_buf_t *out_encoded);
```

---

## 5. What does **not** belong in this `.so`

| Concern | Where |
|---------|--------|
| Ghostty VT, paint, key encode | Flutter + `libghostty-vt` |
| Window, focus, theme | Flutter |
| Approval UI | Dart; only **answers** cross C |
| BEAM process trees / DirtyCpu | Elixir only |
| Reimplementing wasmtime / KernelHost | Forbidden |

---

## 6. Ideal Dart usage patterns

### Interactive terminal (product spine)

```text
boot(deny caps, loom)
loop:
  relay_next → if any, handle in Dart → respond
  tick
  take_output → vt_write → paint
  on key → send_input
status → at_prompt for chrome
close
```

### Structured tool

```text
run_start / exec_start → poll + peek → cancel
```

or blocking `run` on a worker isolate.

### Resume

```text
restore(kernel, snapshot, opts) → same loop
```

---

## 7. Phased expansion

Expand by product need. Do not land the full NIF in one PR.

| Phase | C surface | Unlocks |
|-------|-----------|---------|
| **T0** (now) | boot / tick / send_input / take_output / exec / close | Smoke demo |
| **T1** Session | boot_opts (deny defaults), optional take_output_ex, **status** | Live TTY, honest caps |
| **T2** Jobs | run, exec opts, exec_start / poll / peek / cancel | Non-blocking tools |
| **T3** Relay core | relay_next + host_call + http respond | Real egress / tools |
| **T4** Relay rest | persist, WS, tool_approval | Full production modes |
| **T5** Identity | snapshot*, restore, commit_layer, layers boot | Machine over time |
| **T6** Control UX | FS helpers, svc_call, catalog, autocomplete | Beyond pure TTY |
| **T7** Perf | perf_* | Diagnostics |

**Real terminal demo:** T1 (+ UI session loop) is enough.  
**AgentOS machine that can call out:** T3.

---

## 8. Done-enough checklist

When expanded and “good enough” for product:

1. Header is self-contained (version, errors, buffers, threading).
2. Boot is capability-explicit (no silent real-net).
3. Session loop works without `exec` (exec is optional).
4. Relay is complete for every enabled capability.
5. Snapshots round-trip through restore.
6. Buffer overflow returns required size; no orphan malloc.
7. Dart `AgentOsVm` stays a thin map; policy stays in Dart.
8. A parity table (NIF → C → status) is kept next to the code and updated when the surface moves.

---

## 9. Bottom line

Ideal is **not** “copy every Elixir name into C once.”

Ideal is a **versioned C control plane over `KernelHost`**: explicit capabilities, caller-owned buffers, a small relay envelope, and a terminal-first subset (T0–T2) that can grow without permanent shims.

Update this file when the real header diverges. If policy conflicts with `SYSTEM.md`, fix **this** file or the code — not permanent system rules — unless intent itself changed.
