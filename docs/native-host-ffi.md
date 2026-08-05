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

## First-cut C ABI

| C | Role |
|---|------|
| `aos_vm_boot` | Boot from kernel bytes; tick to prompt |
| `aos_vm_tick` | One fuel quantum; state runnable/waiting/exited |
| `aos_vm_send_input` | Terminal input bytes |
| `aos_vm_take_output` | Drain capture buffer |
| `aos_vm_close` | Drop host |
| `aos_last_error` | Last error string |

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
