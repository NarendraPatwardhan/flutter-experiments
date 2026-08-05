# flutter-bazel-hello

Minimal Flutter app (same “Hello, Linux” UI as `flutter-app`) built with
[SpencerC/rules_flutter](https://github.com/SpencerC/rules_flutter) under Bazel,
using the **BuildBuddy remote pattern** from `opencascade-bazel`.

## One-time setup

```bash
# BuildBuddy CLI auth (API key stays in local git config — not committed)
bb login
```

## Remote build (preferred on this host)

```bash
bb build --config=buildbuddy //:app.web
bb test  --config=buildbuddy //:widget_test
```

- Coordinator: analysis on this machine (outputs under `/mnt/workspace/.cache/bazel-flutter-hello`)
- RBE: compile/spawn actions (`spawn_strategy=remote`, no local fallback)
- UI: https://app.buildbuddy.io/

## Local build (stronger machines)

```bash
bazel build //:app.web
bazel test //:widget_test
# optional desktop (needs GTK/clang on host):
bazel build //:app.linux
```

## Layout

| Path | Role |
|------|------|
| `MODULE.bazel` | bzlmod + rules_flutter pin + Flutter 3.41.7 toolchain |
| `.bazelrc` | defaults + `--config=buildbuddy` (cache, RBE, BES) |
| `buildbuddy.yaml` | optional CI after BuildBuddy GitHub app |
| `//:app.web` | hermetic web release (RBE-friendly) |
| `//:app.linux` | desktop, tagged `manual` |

## Notes

- No secrets in the tree; use `bb`, not bare `bazel`, with `--config=buildbuddy`.
- `rules_flutter` is not on BCR yet — pinned via `git_override` to v0.2.1.
