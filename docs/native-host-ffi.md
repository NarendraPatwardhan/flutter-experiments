# Native host FFI (AgentOS ↔ Dart/Flutter)

This product is a **native** Flutter host. It does **not** use the AgentOS JavaScript path (`sdk-js`, `mc-core.mjs`).

## How Elixir does it

```text
kernel.wasm
    ▲
KernelHost  (memcontainers/hosts/wasmtime)   ← real native host
    ▲
host_nif.so (Rustler)                        ← thin BEAM adapter only
    ▲
AgentOS.Host.Nif + AgentOS.Vm GenServer      ← single owner, DirtyCpu, relay
```

| Rule | Meaning |
|------|---------|
| One owner per VM | `wasmtime::Store` is `!Sync`; serialize all access |
| NIF is not a second host | Only wraps `KernelHost` |
| Errors are values | `{:ok, _} \| {:error, msg}` |
| Long work off main scheduler | DirtyCpu NIF |
| Output capture | Shared buffer + `take_output` |
| Egress relay | Rust queues; BEAM answers (`relay_*`) |
| Bazel builds the `.so` | Elixir only loads prebuilt `libhost_nif.so` |

## Flutter analogue

```text
Flutter UI
    → Dart Vm owner (worker isolate serializes FFI)
    → libagentos_flutter_host.so  (C ABI, this repo)
    → @agent-os//memcontainers/hosts/wasmtime:host
    → kernel.wasm
```

**Do not** load the Rustler NIF from Dart. **Do not** reimplement the env bridge.

## C ABI (expanded)

Full surface and phased design: **[aos-c-api.md](aos-c-api.md)**. Header: `native/agentos_flutter_host/include/agentos_flutter_host.h`.

| Area | Examples |
|------|----------|
| Compat core | `aos_vm_boot`, `tick`, `send_input`, `take_output`, `exec`, `close` |
| Session | `boot_ex`, `restore`, `tick_n`, `take_output_ex`, `status` |
| Jobs | `run`, `exec_ex`, `exec_start` / `poll` / `peek` / `cancel`, `autocomplete` |
| Control | `svc_call`, FS (`read_file` … `mount`) |
| Identity | `snapshot`, `snapshot_incremental`, `commit_layer` |
| Relay | `relay_next` (+ sidecar) + respond family |
| Other | `inject_catalog` (JSON catalog blob), perf_* |

Ship tree: `//:linux_product_bundle` → `linux_product.tar.gz` with `lib/libagentos_flutter_host.so` and `data/kernel.wasm` next to the Flutter binary.

## Ownership

1. One Dart object owns one handle.  
2. All FFI for that handle runs on **one** worker isolate.  
3. UI isolate only receives messages/streams.  
4. Host-call policy (later) lives in Dart, not in the kernel.

## Build mode and size

- Opt compile: `agentos_flutter_host_opt` (transition `compilation_mode=opt`).
- Strip: genrule `//native/agentos_flutter_host:agentos_flutter_host` runs after that target (`strip --strip-unneeded`).
- Do not ship a fastbuild/debug wasmtime host — it is larger and much slower to boot.
- Most remaining size is wasmtime + TLS inside `@agent-os` `host`, not the thin C ABI.

## Later (same model)

`exec` / `svc_call` / snapshot / `relay_next` + respond — mirror NIF surface as needed for the terminal product.

Working expansion sketch (not sacred; not SYSTEM.md): **[aos-c-api.md](aos-c-api.md)**.
