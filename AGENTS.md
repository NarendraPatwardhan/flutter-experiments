# Agent rules — zero local analysis

Product intent: **machine notebook** on one AgentOS guest (terminal cells + NL agent + Ctrl+K control plane). See `SYSTEM.md` and `docs/ui-northstar.md`. Permanent engineering rules below.

## Only allowed build path

```bash
git push origin HEAD
bb remote --run_from_branch=main --os=linux --timeout=2h --script '…'
# Fetch artifacts from the BuildBuddy invocation (bytestream / UI).
# Stage under dist/ for local run only — never commit dist/ or *.tar.gz.
```

Primary ship target: **`//:linux_product_bundle`**. Also: `//:app.linux`, `//:agentos_native_bundle`. Optional: `//:app.web`, `//:widget_test`.

| Command | Allowed? |
|---------|----------|
| `bb remote` (+ remote script `bazel build`) | **Yes** — client + analysis on BuildBuddy runner |
| `bb build` / `bazel build` on this host | **No** |
| Host `flutter build` | **No** |

`--run_from_branch=main` (or `--run_from_commit=<sha>`) makes the remote runner check out GitHub; do not rely on uploading a local analysis tree.

## AgentOS

- Pin only via `bazel_dep` + `git_override` in `MODULE.bazel` (commit SHA).
- Do **not** use `local_path_override` for agent-os as the permanent pin.
- Do **not** substitute GitHub release zips for `@agent-os//…` labels.
- Patches live under `third_party/agent-os/`.
- Root re-hosts `hermetic_cc` → `@zig_sdk`.
- **Native host only.** Never use the AgentOS JS/browser path (`sdk-js`, `mc-core.mjs`, browserify). See SYSTEM.md §2.4.
- FFI: C ABI over `KernelHost` (`//native/agentos_flutter_host`), not the Rustler NIF. See `docs/native-host-ffi.md`.

## Alpha — break and refactor freely

This product is **alpha**. Shipping a path once does **not** freeze it.

- Implemented code is not sacred. Prefer the right shape over preserving last week’s demo.
- You may delete, rewrite, or replace subsystems (FFI surface, VT paint, main smoke flow, packaging) when that advances the vision.
- Do **not** refuse a better design because “we already implemented X.”
- Do **not** pile compatibility shims around dead demo structure. Replace it.
- Still respect permanent constraints (zero local analysis, AgentOS pin model, native host only, lib-vt only for terminal, single-machine-timeline default, no commit of `dist/` / tarballs).

## Artifacts

- Stage runnables under `dist/` (gitignored).
- Do **not** commit `linux_bundle.tar.gz`, `dist/`, or `bb-out/`.

## After each implementation phase

`flutter analyze` is **not** a substitute for a product build.

1. Commit source (never `dist/`, tarballs, `bb-out/`).
2. `git push origin HEAD`
3. Run `bb remote` for `//:linux_product_bundle` (script in README).
4. Download `linux_product.tar.gz`, stage under `dist/linux/`, make the binary executable.
5. Tell the user the staged path and how to run it.

## After push

Watch: https://app.buildbuddy.io/

Optional CI: `buildbuddy.yaml` (GitHub app must be connected).
