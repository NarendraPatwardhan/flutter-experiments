# flutter-app

Minimal Flutter + [rules_flutter](https://github.com/SpencerC/rules_flutter) with **zero local Bazel analysis**. The primary product is a **Linux desktop** binary built on BuildBuddy and staged under `dist/` for local run only (not committed).

## Build (zero local analysis) + fetch for local run

```bash
bb login   # once
git push origin main

# Remote Linux release build (analysis + compile on BuildBuddy runner)
bb remote --run_from_branch=main --os=linux --timeout=2h --script '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if ! pkg-config --exists gtk+-3.0 2>/dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
fi
bazel build //:app.linux --remote_download_toplevel
tar -C bazel-bin/app.linux_build_artifacts -czf linux_bundle.tar.gz .
mkdir -p /home/buildbuddy/workspace/artifacts/command-0
cp linux_bundle.tar.gz /home/buildbuddy/workspace/artifacts/command-0/
'

# Download the uploaded tarball from the invocation (bytestream), then:
rm -rf dist/linux && mkdir -p dist/linux
tar -C dist/linux -xzf linux_bundle.tar.gz
chmod +x dist/linux/flutter_bazel_hello
```

Run from the bundle directory so `data/` and `lib/` resolve:

```bash
cd dist/linux && ./flutter_bazel_hello
```

`dist/`, `bb-out/`, and `*.tar.gz` bundles are **local artifacts only** — never commit them.

## Targets

| Target | Purpose |
|--------|---------|
| `//:app.linux` | **Primary** — Linux GTK release bundle |
| `//:app.web` | Optional hermetic web |
| `//:widget_test` | Widget tests |

## Policy

See [AGENTS.md](AGENTS.md): only `bb remote` (no host `bazel` / `flutter build`).
