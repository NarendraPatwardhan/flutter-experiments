# SYSTEM.md

This document states the purpose, design rules, and work rules for this project.

Write and review project text in **ASD-STE100 Simplified Technical English** when you can. Use short sentences. Use one idea in each sentence. Use the same word for the same meaning. Do not use slang. Do not use jokes in system documents.

---

## 1. Purpose

This project builds a **desktop application for Linux**.

The application is a **host**. The host shows a graphical window. The host runs a **Flutter** user interface.

The long-term product is a **computer in a terminal**. The host will run **AgentOS** guest software. The host will give the user a terminal-like experience. The host will later support **mobile** platforms.

The primary product today is the **Linux binary**. The Linux binary is not a web page. The Linux binary is not a demo that stops at “Hello World” as the end goal.

---

## 2. Product goals

### 2.1 Primary goal

Deliver a **self-contained Linux desktop application** that:

1. Starts as a normal window on a Linux desktop (for example under Hyprland).
2. Uses **Flutter** for the shell UI.
3. Builds with **Bazel** and **rules_flutter**.
4. Builds on **BuildBuddy remote** runners with **zero local Bazel analysis**.
5. Stages run artifacts under `dist/` for local execution only.

### 2.2 End goal

Integrate **AgentOS** so that the application can:

1. Load AgentOS runtime parts that this product needs (for example kernel and related assets).
2. Run product guest programs and images as Bazel graph outputs.
3. Present a terminal-style “computer” experience to the user.
4. Grow toward the same model on mobile.

### 2.3 Non-goals (current phase)

Do not treat these as the primary product:

- A web-only application as the main delivery.
- A stock `flutter create` project with no Bazel remote path.
- AgentOS as a prebuilt release download that replaces Bazel labels.
- Local full Flutter SDK analysis and large host-side Bazel analysis.

---

## 3. System shape

### 3.1 Layers

| Layer | Role |
|-------|------|
| **Flutter host** | Window, UI shell, platform integration (Linux GTK first). |
| **Bazel product graph** | Defines app targets, dependencies, and release packaging. |
| **AgentOS module** | External Bazel module. Source of guest macros and runtime artifacts. |
| **BuildBuddy remote** | Runs analysis and compile. Host does not run product analysis. |
| **Local `dist/`** | Holds downloaded run bundles for manual test. Not source of truth. |

### 3.2 Dependency rule for AgentOS

AgentOS is a **git-pinned Bazel module**. It is not a local sibling tree as the permanent pin.

Follow the product pattern used in `../search-experience`:

1. Declare `bazel_dep(name = "agent-os", version = "0.0.0")`.
2. Pin with `git_override` to `https://github.com/NarendraPatwardhan/agent-os.git` and a **commit SHA**.
3. Apply product patches from `//third_party/agent-os:…` when the nested module needs them.
4. Depend on labels of the form `@agent-os//…`.
5. Build guests with AgentOS macros (for example `mc_rust_program`, `mc_service_layer`) when the product needs guests.
6. Re-host root-only module extensions that AgentOS needs (for example `hermetic_cc_toolchain` / `@zig_sdk`) in **this** root `MODULE.bazel`.

Do **not** use these as the permanent AgentOS integration model:

- `local_path_override` to a developer machine path as the only pin.
- GitHub Release zips of kernel or mc-core as a substitute for `@agent-os//…` build labels.
- Copy of the full AgentOS monorepo into this repository.

### 3.3 What “built from the pin” means

Runtime parts that come from AgentOS (kernel, catalog compiler, base image pieces, guest glue, and related tools) must come from the **Bazel graph** over the git pin.

The product may stage files under `dist/` after a remote build. Staging is for run and test. Staging is not the definition of the dependency.

### 3.4 Flutter host rules (Linux)

- Primary target: Linux desktop bundle (GTK).
- Match the Flutter version that the remote pin supports (today: Flutter **3.24** via rules_flutter).
- Do not connect signals or call APIs that the pin does not provide (example: `FlView` `first-frame` is invalid on 3.24).
- Prefer compositor-owned window decorations on non-GNOME desktops (plain title; header bar only when GNOME is clear).

### 3.5 Optional targets

These targets may exist. They are not the primary product:

| Target | Role |
|--------|------|
| `//:app.linux` | **Primary** — Linux release bundle. |
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
| Source (`lib/`, `linux/`, `MODULE.bazel`, …) | **Yes** | Source of truth. |
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

### 4.4 Remote script expectations (Linux)

A remote Linux build script must:

1. Install GTK and build tools on the runner when they are missing.
2. Run `bazel build //:app.linux` (or the current primary target) with remote download of top-level outputs as needed.
3. Package the Flutter Linux bundle for download.
4. Upload artifacts in the location BuildBuddy expects for the session.

The developer host then downloads the package and stages `dist/linux`.

---

## 5. Repository layout (intent)

| Path | Intent |
|------|--------|
| `MODULE.bazel` | Product module. AgentOS pin. Toolchain root extensions. |
| `BUILD.bazel` | Product targets (`//:app.linux`, tests, later AgentOS packaging). |
| `.bazelrc` | Remote and bzlmod settings. |
| `AGENTS.md` | Short agent work rules (must match this document). |
| `README.md` | Human operator guide for build and run. |
| `SYSTEM.md` | This document — system intent and permanent rules. |
| `lib/` | Dart/Flutter application source. |
| `linux/` | Linux runner and CMake shell for Flutter. |
| `third_party/agent-os/` | Patches for the git pin (when AgentOS is wired). |
| `dist/` | Local stage only (gitignored). |

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

1. Keep `README.md`, `AGENTS.md`, and `SYSTEM.md` aligned.
2. If policy changes, update all three.
3. Prefer STE100 in system and agent policy text.

### 6.4 Quality bar for the Linux host

1. The window must start without GLib critical errors on supported desktops.
2. The binary must run from the staged bundle directory.
3. The remote build must be the path that produces the binary that users run.

---

## 7. Phases (planned order)

| Phase | Outcome |
|-------|---------|
| **A — Host proven** | rules_flutter Linux app builds on BuildBuddy; runs from `dist/linux`. |
| **B — Repo clean** | Only the Bazel remote approach remains; docs match practice. |
| **C — AgentOS pin** | `git_override` pin + patches; `@agent-os//…` labels resolve in the graph. |
| **D — Runtime assets** | Product packages needed AgentOS runtime outputs with the host. |
| **E — Guest / image** | Product guests and image layers as required for the terminal computer. |
| **F — Terminal UX** | Terminal UI (for example libghostty integration) in the Flutter host. |
| **G — Mobile** | Same product idea on mobile platforms. |

Do not skip the pin model in phase C. Do not replace phase C with a permanent local path override.

---

## 8. License note

This product repository states its own license in `LICENSE` when present.

AgentOS is under **Business Source License 1.1** (BSL 1.1) upstream. Fetch and link of `@agent-os` must follow upstream license terms. The product license does not replace the AgentOS license.

---

## 9. Success criteria

The system is on the correct path when all of these are true:

1. A developer can push git and get a Linux bundle from BuildBuddy without local product analysis.
2. The developer can run the staged Linux binary in a desktop session.
3. AgentOS (when integrated) is a **git commit pin** in `MODULE.bazel`, not a local monorepo path.
4. Product code uses `@agent-os//…` labels for AgentOS build outputs.
5. No release tarball of AgentOS replaces the Bazel graph as the source of those outputs.
6. Web targets, if any, stay optional.

---

## 10. Related documents

| Document | Content |
|----------|---------|
| `AGENTS.md` | Short allowed-command table for automated agents. |
| `README.md` | Build, fetch, and run steps for operators. |
| `../search-experience` | Reference product for AgentOS-as-Bazel-module via `git_override`. |

When this document and another document disagree, fix the other document to match **SYSTEM.md**, unless the user changes system intent.

---

## 11. One-line summary

**Ship a remote-built Linux Flutter host that becomes an AgentOS terminal computer, with AgentOS as a git-pinned Bazel module, not a local tree and not a prebuilt substitute for the graph.**
