# AgentOS capabilities (deep inventory)

Source: `/mnt/workspace/agent-os/agent-os-develop` (`b9675ed`, same line as product docs). Architecture contract: `SYSTEMS.md`. Public API: `docs/*`. Product pin in flutter-app may lag this SHA slightly; the **capability surface** is this design.

**One-line thesis:** A full Unix-like computer as one Wasm kernel, with host-held authority (tools, credentials, mounts, network), snapshottable guest state, and the same `Vm` API across local JS, browser, remote server, and (via this product) native `KernelHost`.

---

## 1. Architecture layers

| Layer | What it is | Where | Status |
|-------|------------|--------|--------|
| **Contracts / ABI projector** | Single source of truth for syscall, bridge, control, wire; generated into languages | `memcontainers/contracts/` | Built |
| **Kernel (Rust → wasm32)** | OS: tasks, VFS, pipes, services, net, scheduler, wasmi guest runtime | `memcontainers/kernel/rust/` | Built (sole shipped kernel) |
| **Guest programs** | Shell, coreutils, Luau, SQLite, Typst, syntax, git thin client, adapters | `memcontainers/programs/` | Built |
| **Images / packages** | Content-addressed layered rootfs flavors | `memcontainers/images/`, `pkgcore/` | Built |
| **Host: wasmtime** | Native load/tick/effects (`KernelHost`) | `memcontainers/hosts/wasmtime/` | Built |
| **Host: JS (Node/Bun/browser)** | Same `kernel.wasm`, embedded host | `memcontainers/hosts/js/` | Built |
| **SDK** | Public `Vm` / `mc` client surface | `memcontainers/sdk-js/` | Built |
| **Control plane (Elixir)** | Actor-per-VM, NIF, sidecars | `server/` | Built |
| **Web / browser UI** | Sandbox elements, workbench | `web/` | Built |
| **Zig kernel experiment** | Alternate kernel | archived (`feature/zig`) | Not shipped |

Nesting: **host → `kernel.wasm` → wasmi → guest.wasm**.

---

## 2. Runtime hosting modes

| Runtime | Kernel lives in | Artifact loading | Notes |
|---------|-----------------|------------------|--------|
| **local** | Node/Bun process | Files / bytes / store | Default for JS products |
| **browser** | Page | Fetched bytes / OPFS store | No ambient host FS |
| **remote** | Served AgentOS | Server image names / digests | REST + per-VM WebSocket |
| **native product (this app)** | Flutter → C ABI → wasmtime host | Bundle `kernel.wasm` + image tar | Same kernel binary idea |

API shape is one `Vm`; transport and artifact rules differ.

---

## 3. Image flavors (what the guest ships with)

| Flavor | ~Size (README) | Adds | Typical use |
|--------|----------------|------|-------------|
| **minimal** | ~930 KiB | Shell, core services, curated ~15 coreutils | Thin custom harness |
| **posix** | ~1.9 MiB | Full coreutils | File/text automation |
| **loom** | ~5.3 MiB | + Luau, analyzers, Office batteries, structural parse | Default programmable agent workspace |
| **atlas** | ~6.2 MiB | + warm **SQLite** service over loom | Data / retrieval |
| **paper** | ~32 MiB | + warm **Typst**/fonts over loom | Documents / PDF |
| **null / empty root** | — | Empty memfs | Custom from scratch |
| **svc-test** | — | Loom + service proof layer | Tests |

Layers are ordered content-addressed tars (`sha256:…`). Richer flavors stack on lower ones.

---

## 4. Kernel OS capabilities

| Capability | What guests get |
|------------|-----------------|
| **Process model** | Tasks, caps, tiers, cooperative schedule, signals, job control |
| **VFS / namespaces** | Plan-9 style per-process mounts |
| **FS backends** | memfs, cowfs, overlayfs, tarfs, persistfs, procfs, envfs, devfs, netfs, servedfs |
| **Pipes / IPC** | Real pipelines (ring buffers) |
| **Resident services** | Warm engines under `/svc/<name>` (SQLite, Typst, …) |
| **Networking** | Host-terminated HTTP/WS; guest sees `/net` tree, not raw sockets as host |
| **Host-call / proxy** | Opaque host-backed ops; mount/tool proxy ABI |
| **Snapshots** | Full + incremental memory capture; quiescence; seal |
| **Determinism** | Optional pinned clock/RNG; network still nondeterministic |
| **Capabilities** | 8-bit set; **only narrows** at exec: `parent ∩ binary ∩ requested`; default deny |
| **Egress policy** | Bridge effects capability-gated; deny → in-kernel error (e.g. EPERM) |
| **Conformance** | Import purity + tier-fit attestation at build |

---

## 5. Guest userland & languages

| Area | Capability |
|------|------------|
| **Shell** | POSIX-ish `/bin/sh` (Zig shcore) |
| **Coreutils** | Multicall applets, tier-partitioned (minimal vs full) |
| **Luau** | Primary scripting; VFS batteries; `vm.luau()` / interactive Luau |
| **Syntax / analyzers** | Structural Lua/Luau parse & edit (loom) |
| **SQLite** | Resident warm service (atlas) |
| **Typst** | Resident document/PDF engine + fonts (paper) |
| **Adapters** | Shared tool-adapter service for host catalogs |
| **Git (thin)** | Reduced `/bin/git` + host libgit2 engine option |
| **WASI adapter** | WASI → mc syscall shim for C/C++ guests |
| **Any wasm32 guest** | Contract-generated ABI; Rust/Zig/C today |

---

## 6. Public `Vm` control surface (JS SDK — mirrors native C ABI intent)

| Method / surface | Capability |
|------------------|------------|
| `exec` / `run` | Shell command vs argv program |
| `autocomplete` | Shell completion without execute |
| `luau` | One-shot Luau script |
| `serviceCall` | Host path into resident services |
| `shell` | Interactive byte stream (PTY-like) |
| `session` | Framed agent session events |
| `cron` | Client-resident schedules |
| `tool` | Live host-tool catalog inject |
| `mount` / `unmount` | Host FS drivers into guest |
| `snapshot` / `pinBase` | Full / incremental MCSN |
| `fork` | Independent branch (snapshot + reattach attachments) |
| `commit().asLayer()` / `asSnapshot()` | Overlay tar or full snapshot |
| `status` / `inflightEgress` / `memoryBytes` | Operational status |
| `fs.*` | Trusted **host** view of guest FS (not guest caps) |
| `sidecars` / `browsers` | External leased resources (e.g. Chromium) |
| `close` | Dispose host resources + stop loop |

Factories: `mc.create`, `mc.restore`, `mc.use`, `mc.connect`, plus `vm.fork()`.

---

## 7. Host authority (outside the snapshot “value”)

| Attachment | Capability | Guest sees | Host holds |
|------------|------------|------------|------------|
| **Host tools** | Callable catalog entries (`tool()` / `kit()`, Zod schemas) | Address + JSON schema | Closures, secrets, app objects |
| **Connections** | OpenAPI, GraphQL, MS Graph, Google Discovery, remote MCP | Tool catalog + refs | Tokens, origins, specs |
| **Mounts** | `hostDir`, S3, vector store, custom drivers | Normal paths (`cat`/`ls`) | Driver (S3 client, host path, etc.) |
| **Permissions** | FS allow/deny; network allowlist / prompt; `onPermission` | Success/EPERM | Callback policy |
| **Git engine** | Host libgit2 + worktree mount | Thin `/bin/git` | Creds, remotes via connections |
| **Sidecars** | Leased external processes/machines | Grant name + binary protocol | Placement, endpoints, lifecycle |
| **Browser sidecars** | Typed Chromium sessions, pages, input, screenshots | Via grant | Chromium infrastructure |
| **Content store** | Layers, blobs, manifests, snapshots by digest | Names/digests as inputs | Memory / FS / OPFS / custom store |

**Invariant:** attachments rehydrate on restore; snapshots do not contain host closures or credentials.

---

## 8. State, builds, identity

| Capability | Detail |
|------------|--------|
| **Full snapshot** | Entire VM memory/process/FS/service warmth + image contract |
| **Incremental snapshot** | Delta pages vs pinned baseline / store |
| **Layer commit** | CoW overlay as tar digests (FS only, not processes) |
| **Fork** | New VM from snapshot + current tools/mounts; new remote identity |
| **LLB build graphs** | Content-addressed DAG; cache; solver → layer/image/warm snapshot |
| **`record()`** | Live VM ops → LLB definition |
| **Deterministic boot** | Pinned time/RNG; does not freeze the network |
| **Named remote VMs** | Server-side identity (`id` / `mc.connect`) |
| **OPFS / IndexedDB** | Browser durable persist + stores |

---

## 9. Security / policy model

| Mechanism | Behavior |
|-----------|----------|
| **Containment** | Guest never gets host fds, objects, or raw credentials |
| **Default deny** | Net, mounts, tools, persist opt-in |
| **Cap intersection** | Parent ∩ binary tier ∩ requested at exec |
| **Network** | Host-routed; allow / deny / allowlist / per-host approval |
| **Tool approval** | Policy + annotations (read-only, etc.) |
| **Fail-closed** | Missing/broken permission callback → deny |
| **Host vs guest FS** | Operator `vm.fs` can stage inputs even if guest is RO |

---

## 10. Product / integration surfaces

| Surface | Capability |
|---------|------------|
| **JS SDK (`@mc/core`)** | Primary documented product API |
| **Browser elements** | `<mc-sandbox>`, `<mc-terminal>`, `<mc-xterm>`, `<mc-editor>` |
| **Elixir server + NIF** | Multi-VM control, DirtyCpu, relay queues |
| **Native C ABI (this product)** | Flutter maps NIF-parity control plane onto wasmtime host |
| **Browser VM** | Full machine in page without server for execution |
| **Remote product** | Same API against hosted AgentOS |

---

## 11. What AgentOS is *for* (product table from upstream)

| Product class | What AgentOS supplies |
|---------------|------------------------|
| Coding agents | Isolated workspace, POSIX, Luau, analysis, structural edit |
| Tool-using agents | Schema tools discoverable from shell/Luau |
| SaaS automation | OpenAPI/GraphQL/Graph/MCP with host-held creds |
| Data/retrieval | Warm SQLite, S3/vector mounts, pipelines |
| Documents | Office batteries, Typst/PDF |
| Browser sandboxes | In-page VM + OPFS + UI elements |
| Branching agents | Snapshot / fork whole machine |
| Reproducible envs | CA images + LLB |
| Secure automation | Jailed mounts, origin net, approvals |

---

## 12. Relation to this flutter-app (capability use)

| AgentOS capability class | In AgentOS repo | Wired in flutter product session |
|--------------------------|-----------------|----------------------------------|
| Kernel + image boot | Yes | Yes (compat boot + loom) |
| Tick / PTY I/O | Yes | Yes |
| Status | Yes | Partial (`at_prompt`, etc.) |
| Full control plane (relay, FS, jobs, snapshot, tools…) | Yes | **API in Dart; not product UI** |
| JS browser host | Yes | Out of scope (native-only product) |
| Elixir multi-tenant server | Yes | Not this app |

---

## Bottom line

AgentOS is not “a shell in a box.” It is a **capability-gated, snapshottable Wasm Unix** with:

- rich **guest** stack (posix → loom → atlas/paper),
- **host** tools/connections/mounts/sidecars outside the guest value,
- **three runtimes** (local / browser / remote) plus this product’s **native host**,
- and **build/identity** (layers, LLB, stores).

This product’s complete C/Dart host maps that control plane; the live Flutter UI still exercises mainly the **machine + PTY** subset of this table.
