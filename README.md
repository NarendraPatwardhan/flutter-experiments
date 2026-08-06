# flutter-app

Minimal Flutter + [rules_flutter](https://github.com/SpencerC/rules_flutter) with **zero local Bazel analysis**. The primary product is a **Linux desktop** binary with a native AgentOS host (C ABI over `KernelHost`), built on BuildBuddy and staged under `dist/` for local run only (not committed).

## AgentOS pin

AgentOS is **not** vendored and **not** a `local_path_override`. Root `MODULE.bazel` uses:

- `bazel_dep(name = "agent-os", version = "0.0.0")`
- `git_override` → fixed **commit** + patches under `third_party/agent-os/`
- Root re-host of `hermetic_cc_toolchain` → `@zig_sdk`

## Targets

| Target | Purpose |
|--------|---------|
| `//:linux_product_bundle` | **Ship tree** — app + host `.so` + `kernel.wasm` + `loom.tar` |
| `//:app.linux` | Flutter Linux app only |
| `//:agentos_native_bundle` | `kernel.wasm` + `loom.tar` + host `.so` |
| `//:agentos_flutter_host` | Opt + genrule-stripped C ABI host |
| `//:agentos_kernel` | Kernel wasm from pin |
| `//:agentos_loom` | Loom guest image from pin |

## Build (zero local analysis)

```bash
bb login   # once
git push origin HEAD

# One invocation: remote analysis/build + download of toplevel outputs into bb-out/
bb remote --run_from_branch=main --os=linux --timeout=2h \
  build //:linux_product_bundle --remote_download_toplevel

# Stage for local run (never commit dist/ or tarballs)
rm -rf dist/linux && mkdir -p dist/linux
tar -C dist/linux -xzf bb-out/bazel-out/k8-fastbuild/bin/linux_product.tar.gz
chmod +x dist/linux/flutter_bazel_hello
cd dist/linux && ./flutter_bazel_hello
```

Do **not** treat a separate bytestream/API download as the normal path. Fetch is part of `bb remote build … --remote_download_toplevel` (look for `Downloaded artifacts:` in the client log).

On launch the app boots **kernel + loom** and a **libghostty-vt** live session (tick → VT → paint; keys/paste → guest).
Assets: `lib/libagentos_flutter_host.so`, `lib/libghostty-vt.so`, `data/kernel.wasm`, `data/loom.tar`.

`dist/`, `bb-out/`, and `*.tar.gz` are **local artifacts only** — never commit them.

## Policy

See [AGENTS.md](AGENTS.md) and [SYSTEM.md](SYSTEM.md): only `bb remote` (no host `bazel` / `flutter build`). Native host only — no AgentOS JS path.
