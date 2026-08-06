# SYSTEM.md

This document states the purpose, design rules, and work rules for this project.

Write and review project text in **ASD-STE100 Simplified Technical English** when you can. Use short sentences. Use one idea in each sentence. Use the same word for the same meaning. Do not use slang. Do not use jokes in system documents.

---

## 1. Purpose

This project builds a **desktop application for Linux**.

The application is a **host**. The host shows a graphical window. The host runs a **Flutter** user interface.

The product is a **computer in a terminal**, presented as a **machine notebook**:

1. **AgentOS** is the guest machine (kernel, image, capabilities). One guest is the default world.
2. **libghostty-vt** is the terminal emulator core (parse, grid, encode, effects) for **terminal cells**.
3. **Flutter** presents the notebook (cells, bars, control plane, agent chrome), paints the terminal surface, and routes input.

Three equal entry paths (detail in **[docs/ui-northstar.md](docs/ui-northstar.md)**):

1. **Terminal cell** — type into the guest (default).
2. **Natural language** — agent operates the **same** guest.
3. **Control plane (Ctrl+K)** — reshape the machine (mounts, image, snapshot / restore / fork, relay).

The primary product today is the **Linux binary**. The Linux binary is not a web page. The Linux binary is not a “Hello World” end goal. A closed PTY loop is **required infrastructure**, not the final product shape.

The host will later support **mobile** platforms.

---

## 2. Product goals

### 2.1 Primary goal

Deliver a **self-contained Linux desktop application** that:

1. Starts as a normal window on a Linux desktop (for example under Hyprland).
2. Uses **Flutter** for the shell UI.
3. Builds with **Bazel** and **rules_flutter**.
4. Builds on **BuildBuddy remote** runners with **zero local Bazel analysis**.
5. Stages run artifacts under `dist/` for local execution only.
6. Ships a **product bundle**: Flutter app + `libagentos_flutter_host.so` + `libghostty-vt.so` + kernel + guest image.

### 2.2 End goal

1. Load AgentOS runtime parts from the Bazel graph (kernel, guest images).
2. Run the guest as a live session (tick, input, output).
3. Present a Ghostty-quality terminal experience (libghostty-vt embed) as the **default notebook cell**.
4. Ship a **machine notebook** UI: terminal cells, natural-language turns on the same guest, thin status bars, single machine timeline.
5. Ship a **control plane** (Ctrl+K and short-lived sheets): mounts, catalog, snapshots, restore, fork, relay, session lifecycle.
6. Run an **agent spine** on that guest: thin loop, guest-first tools, multi-agent work (parallel / background / persistent) without split-brain REPLs; isolation via snapshot/fork when required.
7. Use more of the AgentOS surface as product needs it (jobs, caps, mouse into guest, long-lived VM ownership).
8. Carry the same product model to **mobile**.

Product design detail: **[docs/ui-northstar.md](docs/ui-northstar.md)**, **[docs/control-plane-palette.md](docs/control-plane-palette.md)**, **[docs/agent-spine.md](docs/agent-spine.md)**.

### 2.3 Non-goals (current phase)

Do not treat these as the primary product:

- A web-only application as the main delivery.
- A stock `flutter create` project with no Bazel remote path.
- AgentOS as a prebuilt release download that replaces Bazel labels.
- Local full Flutter SDK analysis and large host-side Bazel analysis.
- The full Ghostty **application** (GTK/macOS app, config UI). Use **libghostty-vt** only.
- A second VT parser in pure Dart or inside AgentOS.
- A **host IPython** (or other host REPL) as the agent’s real computer. **AgentOS is the guest computer.**
- **N isolated REPLs** or one private machine per cell/sub-agent by default.
- Permanent **IDE chrome** (always-on file tree, multi-column IDE shell).
- A **second production agent loop** beside the documented agent spine.
- Nested-terminal capability theater (tmux/truecolor doctor as product core).

### 2.4 Host path: native only (no JavaScript AgentOS host)

This product is a **native** host (Flutter on Linux, later mobile).

- Do **not** use the AgentOS **JavaScript / browser** host path.
- Do **not** depend on `@agent-os//memcontainers/sdk-js/…`, `mc-core.mjs`, or browserify of the JS core.
- Do **not** copy search-experience’s browser worker packaging as the model for this host.
- Integrate AgentOS through the **native** host contract (kernel Wasm, guests, C ABI, Dart FFI).

search-experience may use JS. This repository does not.

### 2.5 Dual-host architecture

| Concern | Owner | Library |
|---------|--------|---------|
| Guest machine, caps, tools, snapshots | AgentOS | `libagentos_flutter_host` → `KernelHost` |
| Escape sequences, grid, styles, scrollback, input encoding | Ghostty | `libghostty-vt` |
| Window, notebook UI, control plane chrome, agent chrome, paint, input routing | Flutter | `lib/` |
| Agent loop, harness state, LLM transport | Agent spine (host library) | See `docs/agent-spine.md` — not inside VT |

Rules:

1. AgentOS must not grow a second VT parser.
2. Flutter must not invent CSI / Kitty encodings when libghostty-vt provides encoders.
3. Ghostty / paint / window chrome stay **out** of `libagentos_flutter_host.so`.
4. The agent loop must not own VT parse/encode. Terminal cells use libghostty-vt.
5. Default agent tools and sub-agents act on the **same AgentOS guest** as the terminal cells. Isolation is **control-plane fork/snapshot**, not a silent second machine.

### 2.6 Native AgentOS FFI

The Elixir control plane wraps **`host::KernelHost`** through a thin NIF. This product does the same for Flutter:

- C ABI cdylib over `KernelHost` (`//native/agentos_flutter_host`)
- Dart `dart:ffi` (`lib/agent_os/`) with isolate-serialized calls
- Kernel Wasm and images from `@agent-os//…` (git pin)

See **[docs/native-host-ffi.md](docs/native-host-ffi.md)** and **[docs/aos-c-api.md](docs/aos-c-api.md)**.

### 2.7 Ghostty lib-vt embed

Terminal semantics come from **libghostty-vt** (pin via `MODULE.bazel` / `//third_party/ghostty`).

- Dart embed: `lib/vt/*`
- Live session owner: `lib/session/product_session.dart` (evolves with notebook ownership)
- Design notes: **[docs/ghostty-vt-embed.md](docs/ghostty-vt-embed.md)**

Only **one live VT** at a time for the focused terminal cell. Completed terminal cells freeze for notebook history (see ui-northstar).

---

## 3. System shape

### 3.1 Layers

| Layer | Role |
|-------|------|
| **Flutter host** | Window, notebook UI, control plane, agent chrome, paint, platform integration (Linux GTK first). |
| **Product session** | Owns AgentOS VM + live terminal cell loop; grows into notebook timeline ownership. |
| **Agent spine** | LLM transport, thin agent loop, harness store, guest-first tools. Outside VT. |
| **AgentOS native host** | C ABI over `KernelHost`. |
| **libghostty-vt** | Virtual terminal core (embed only; live terminal cell). |
| **Bazel product graph** | App targets, pins, ship packaging. |
| **BuildBuddy remote** | Analysis and compile. Host does not run product analysis. |
| **Local `dist/`** | Staged run bundles. Not source of truth. |

### 3.2 Dependency rule for AgentOS

AgentOS is a **git-pinned Bazel module**. It is not a local sibling tree as the permanent pin.

Follow the product pattern used in `../search-experience`:

1. Declare `bazel_dep(name = "agent-os", version = "0.0.0")`.
2. Pin with `git_override` to `https://github.com/NarendraPatwardhan/agent-os.git` and a **commit SHA**.
3. Apply product patches from `//third_party/agent-os:…` when the nested module needs them.
4. Depend on labels of the form `@agent-os//…`.
5. Build guests with AgentOS macros when the product needs guests.
6. Re-host root-only module extensions that AgentOS needs (for example `hermetic_cc_toolchain` / `@zig_sdk`) in **this** root `MODULE.bazel`.

Do **not** use these as the permanent AgentOS integration model:

- `local_path_override` to a developer machine path as the only pin.
- GitHub Release zips of kernel (or other runtime artifacts) as a substitute for `@agent-os//…` build labels.
- Copy of the full AgentOS monorepo into this repository.
- The AgentOS **JS/sdk-js** host stack (see §2.4).

### 3.3 What “built from the pin” means

Runtime parts that come from AgentOS (kernel, catalog compiler, base image pieces, guest glue, and related tools) must come from the **Bazel graph** over the git pin.

libghostty-vt comes from the **Ghostty git pin** via `//third_party/ghostty`, not from a vendored copy of the full Ghostty app.

The product may stage files under `dist/` after a remote build. Staging is for run and test. Staging is not the definition of the dependency.

### 3.4 Flutter host rules (Linux)

- Primary ship target: product bundle (GTK + native libs + assets).
- Match the Flutter version that the remote pin supports (today: Flutter **3.24** via rules_flutter).
- Do not connect signals or call APIs that the pin does not provide (example: `FlView` `first-frame` is invalid on 3.24).
- Prefer compositor-owned window decorations on non-GNOME desktops (plain title; header bar only when GNOME is clear).
- On window close, quit the GTK application cleanly; free native hosts without use-after-free under in-flight ticks.

### 3.5 Product targets

| Target | Role |
|--------|------|
| `//:linux_product_bundle` | **Ship tree** — app + host `.so` + `libghostty-vt.so` + `kernel.wasm` + guest image. |
| `//:app.linux` | Flutter Linux app only. |
| `//:agentos_flutter_host` | Opt + stripped C ABI host. |
| `//:agentos_kernel` | Kernel wasm from pin. |
| `//:agentos_loom` | Loom guest image from pin. |
| `//:app.web` | Optional web artifact. |
| `//:widget_test` | Automated UI tests when configured. |

---

## 4. Build and execution policy

### 4.1 Zero local analysis

**Requirement:** Product Bazel **analysis** and **compile** for the app must run on BuildBuddy remote runners.

| Action | Allowed? |
|--------|----------|
| `git push` then `bb remote` with a remote script that runs `bazel build` | **Yes** |
| `bb build` / `bazel build` on the developer host for product analysis | **No** |
| Host `flutter build` for product release | **No** |
| Download of remote artifacts to the host for run/test | **Yes** |
| Local run of `dist/linux/…` after stage | **Yes** |

Use `--run_from_branch=…` or `--run_from_commit=…` so the remote runner checks out GitHub. Do not rely on upload of a full local analysis tree as the main path.

### 4.2 Artifact rules

| Path / form | In git? | Role |
|-------------|---------|------|
| Source (`lib/`, `linux/`, `native/`, `MODULE.bazel`, …) | **Yes** | Source of truth. |
| `dist/` | **No** | Local stage of run bundles. |
| `*.tar.gz` Linux bundles | **No** | Transfer form only. |
| `bb-out/`, Bazel caches | **No** | Tool output. |
| `.bb-remote-invocation-id` | **No** | Local helper file. |

Do not commit build outputs. Do not commit downloaded release trees.

### 4.3 How to run the Linux app

After a successful remote build and stage:

1. Change directory to the bundle root (example: `dist/linux`).
2. Run the binary next to `data/` and `lib/` (example: `./flutter_bazel_hello`).
3. Do not move the binary alone without its `data/` and `lib/` tree.

Expected assets next to the binary:

- `lib/libagentos_flutter_host.so`
- `lib/libghostty-vt.so`
- `data/kernel.wasm`
- `data/loom.tar` (or other guest image shipped by the bundle)

### 4.4 Remote script expectations (Linux)

A remote Linux build script must:

1. Install GTK and build tools on the runner when they are missing.
2. Run `bazel build //:linux_product_bundle` (or `//:app.linux` when packaging is not required) with remote download of top-level outputs as needed.
3. Package / copy the ship tarball for download.
4. Upload artifacts in the location BuildBuddy expects for the session.

The developer host then downloads the package and stages `dist/linux`.

---

## 5. Repository layout (intent)

| Path | Intent |
|------|--------|
| `MODULE.bazel` | Product module. AgentOS pin. Ghostty pin. Toolchain root extensions. |
| `BUILD.bazel` | Product targets and ship packaging. |
| `.bazelrc` | Remote and bzlmod settings. |
| `AGENTS.md` | Short agent work rules (must match this document). |
| `README.md` | Human operator guide for build and run. |
| `SYSTEM.md` | This document — system intent and permanent rules. |
| `docs/` | Product design and implementation notes (see below). |
| `lib/` | Dart/Flutter application source (`agent_os/`, `vt/`, `session/`, `main.dart`). |
| `linux/` | Linux runner and CMake shell for Flutter. |
| `native/agentos_flutter_host/` | C ABI host over `KernelHost`. |
| `third_party/agent-os/` | Patches for the AgentOS git pin. |
| `third_party/ghostty/` | Pin adapter for libghostty-vt. |
| `LICENSE` | Apache-2.0 for this product (opyt.cloud). |
| `dist/` | Local stage only (gitignored). |

### 5.1 Documents under `docs/`

| Kind | Examples | Role |
|------|----------|------|
| **Product design** | `ui-northstar.md`, `notebook-components.md`, `control-plane-palette.md`, `agent-spine.md`, `ui-toolkit.md`, `agentos-capabilities.md` | Product intent for UI, control plane, and agent spine. Keep aligned with this file on permanent rules. |
| **Implementation sketches** | `aos-c-api.md`, `ghostty-vt-embed.md`, `native-host-ffi.md` | Status and embed detail. May lag on status; must not contradict permanent rules here. |

Do not keep a second “old approach” tree in this repository. One product tree only.

---

## 6. Work rules for agents and humans

### 6.1 Commands and disk safety

1. Do not run recursive `find` or wide filesystem scans unless the user **asks**.
2. When the user gives a path, use that path. Open named files. Use narrow search.
3. Do not fill the disk with local Flutter SDK or Bazel analysis caches for this product path.
4. Prefer BuildBuddy remote execution for product builds.

### 6.2 Source control

1. Commit source and policy documents.
2. Do not commit `dist/`, tarballs, or tool caches.
3. Push before remote builds that use `--run_from_branch` / `--run_from_commit`.

### 6.3 Documentation

1. Keep `README.md`, `AGENTS.md`, and `SYSTEM.md` aligned on build and pin policy.
2. If permanent policy changes, update `SYSTEM.md` first, then agent and operator docs.
3. Prefer STE100 in system and agent policy text.
4. When product design under `docs/` conflicts with this file on **permanent** rules, fix the design doc or change system intent explicitly.
5. When implementation sketches lag on **status**, update the sketch.

### 6.4 Quality bar for the Linux host

1. The window must start without GLib critical errors on supported desktops.
2. Window close must not SIGSEGV or leave GObject CRITICAL spam from bad teardown.
3. The binary must run from the staged bundle directory with host `.so`, VT `.so`, kernel, and image present.
4. The remote build must be the path that produces the binary that users run.
5. Terminal paint must use mono grid pitch equal to the live face advance (no letter holes).
6. Keys, focus, and paste must go through Ghostty encoders (no permanent hand-rolled CSI fallback).

### 6.5 Alpha and refactor

This product is **alpha**. Shipping a path once does **not** freeze it.

- Prefer the right shape over preserving demo structure.
- You may rewrite FFI, VT paint, session loop, notebook chrome, or packaging when that advances the vision.
- Do not pile compatibility shims around dead code.
- Permanent constraints stay: zero local analysis, AgentOS pin model, native host only, lib-vt only for terminal, single-machine-timeline default, no commit of `dist/` / tarballs.

---

## 7. Phases

| Phase | Outcome | Status |
|-------|---------|--------|
| **A — Host proven** | rules_flutter Linux app builds on BuildBuddy; runs from `dist/linux`. | **Done** |
| **B — Repo clean** | Only the Bazel remote approach remains; docs match practice. | **Done** |
| **C — AgentOS pin** | `git_override` pin + patches; root hermetic_cc; kernel from pin. | **Done** |
| **D — Native FFI host** | C ABI over `KernelHost` + full Dart `AgentOsVm`; opt+strip host. | **Done** |
| **E — Guest / image** | Loom (or product image) + kernel in `//:linux_product_bundle`. | **Done** |
| **F — Terminal UX** | libghostty-vt embed G1–G4; live dual-host PTY loop in `ProductSession`. | **Done** |
| **H1 — Notebook spine** | Terminal-first machine notebook: cell list, one live VT + freeze path, top/bottom bars, Shift+Tab NL surface (agent may stub). | **In tree** (`lib/notebook/*`; polish continues) |
| **H2 — Control plane** | Ctrl+K palette + sheets: snapshot / restore / fork, mounts, catalog; destructive confirms. | **Open** |
| **H3 — Agent spine** | Thin agent loop, guest-first tools, multi-block turns; harness state; multi-agent on same guest (fork for isolation). | **Open** |
| **H4 — Machine depth** | Deeper AgentOS wiring: relay, mouse into guest, TTY size policy, long-lived VM isolate ownership, jobs as needed. | **Open** |
| **G — Mobile** | Same product idea on mobile platforms. | **Open** |

Do not skip the pin model in phase C. Do not replace phase C with a permanent local path override.

Phase C smoke target: `//:agentos_kernel` → `@agent-os//memcontainers/kernel/rust:kernel`.

H1–H3 may overlap in small slices. Prefer durable session and terminal quality over multi-agent dashboards. Detail: `docs/ui-northstar.md`, `docs/agent-spine.md`, `docs/control-plane-palette.md`.

### 7.1 Coupling today (honest)

**Tight (PTY loop):** guest `take_output` → `vt_write` → paint; Ghostty key/focus/paste encode and WRITE_PTY → `send_input`; effects to chrome (title, pwd, bell, clipboard, progress).

**Open for H1–H4:** notebook cell model and freezes; Ctrl+K and control-plane product wiring; agent loop on guest; relay drain/respond; mouse tracking → guest; TTY size policy; worker-isolate VM owner as documented ideal.

The AgentOS C/Dart surface is complete for control-plane calls. The live UI session still uses the PTY subset. That is product depth, not a missing ABI.

---

## 8. License note

This product repository states its own license in `LICENSE` when present.

AgentOS is under **Business Source License 1.1** (BSL 1.1) upstream. Fetch and link of `@agent-os` must follow upstream license terms. The product license does not replace the AgentOS license.

Ghostty / libghostty-vt follows upstream license terms for the pin.

---

## 9. Success criteria

The system is on the correct path when all of these are true:

1. A developer can push git and get a Linux product bundle from BuildBuddy without local product analysis.
2. The developer can run the staged Linux binary in a desktop session with kernel, guest image, AgentOS host `.so`, and libghostty-vt `.so`.
3. AgentOS is a **git commit pin** in `MODULE.bazel`, not a local monorepo path.
4. Product targets use `@agent-os//…` labels for AgentOS build outputs.
5. No release tarball of AgentOS replaces the Bazel graph as the source of those outputs.
6. Terminal I/O is a closed loop: AgentOS output → libghostty-vt → paint; encoded input → AgentOS.
7. The **UI target** is a **terminal-first machine notebook** on one AgentOS guest (not a permanent raw-PTY-only demo, and not a chat app that hides the machine).
8. Control plane and agent work treat AgentOS as the computer; default path does not create N isolated machines.
9. Web targets, if any, stay optional.
10. This product ships under Apache-2.0 (opyt.cloud). AgentOS remains BSL 1.1 upstream.

---

## 10. Related documents

| Document | Content |
|----------|---------|
| `AGENTS.md` | Short allowed-command table for automated agents. |
| `README.md` | Build, fetch, and run steps for operators. |
| `docs/ui-northstar.md` | Machine notebook UI: cells, Ctrl+K, bars, contracts. |
| `docs/notebook-components.md` | Notebook component system: CellChrome, ActiveSlot, freeze, overflow. |
| `docs/control-plane-palette.md` | Ctrl+K control plane palette (kinds, modes, scorer). |
| `docs/agent-spine.md` | Agent loop, multi-agent, continual harness on AgentOS. |
| `docs/ui-toolkit.md` | Forui hybrid vs invent for host chrome. |
| `docs/agentos-capabilities.md` | AgentOS capability inventory for product UI. |
| `docs/native-host-ffi.md` | Native host FFI model. |
| `docs/aos-c-api.md` | AgentOS C ABI sketch and status. |
| `docs/ghostty-vt-embed.md` | libghostty-vt embed design and status. |
| `../search-experience` | Reference product for AgentOS-as-Bazel-module via `git_override`. |

When this document and another document disagree on **permanent rules**, fix the other document to match **SYSTEM.md**, unless the user changes system intent.

---

## 11. One-line summary

**Ship a remote-built Linux Flutter host that runs AgentOS as a computer-in-a-terminal machine notebook: libghostty-vt for terminal cells, one guest timeline, control plane and agent spine on that machine, AgentOS as a git-pinned Bazel module and native C ABI host — not a local tree, not a prebuilt substitute for the graph, not a JS host, and not a host REPL as the computer.**
