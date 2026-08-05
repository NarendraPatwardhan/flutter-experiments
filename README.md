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
| `//:linux_product_bundle` | **Ship tree** — Flutter Linux app + stripped host `.so` + `kernel.wasm` |
| `//:app.linux` | Flutter Linux app only |
| `//:agentos_native_bundle` | `kernel.wasm` + `libagentos_flutter_host.so` |
| `//:agentos_flutter_host` | Opt + genrule-stripped C ABI host |
| `//:agentos_kernel` | Kernel wasm from pin |

## Build (zero local analysis)

```bash
bb login   # once
git push origin main

bb remote --run_from_branch=main --os=linux --timeout=2h --script '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if ! pkg-config --exists gtk+-3.0 2>/dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
fi
bazel build //:linux_product_bundle --remote_download_toplevel
mkdir -p /home/buildbuddy/workspace/artifacts/command-0
cp bazel-bin/linux_product.tar.gz /home/buildbuddy/workspace/artifacts/command-0/
'

# Download linux_product.tar.gz from the invocation, then:
rm -rf dist/linux && mkdir -p dist/linux
tar -C dist/linux -xzf linux_product.tar.gz
chmod +x dist/linux/flutter_bazel_hello
cd dist/linux && ./flutter_bazel_hello
```

In the app: **Smoke boot + exec** loads `lib/libagentos_flutter_host.so` and `data/kernel.wasm`.

`dist/`, `bb-out/`, and `*.tar.gz` are **local artifacts only** — never commit them.

## Policy

See [AGENTS.md](AGENTS.md) and [SYSTEM.md](SYSTEM.md): only `bb remote` (no host `bazel` / `flutter build`). Native host only — no AgentOS JS path.
