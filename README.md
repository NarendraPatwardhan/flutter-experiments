# flutter-bazel-hello

Minimal Flutter app built with [rules_flutter](https://github.com/SpencerC/rules_flutter) and **BuildBuddy RBE only**.

## Policy

1. **Push to GitHub first**
2. **Build with `bb` only** (remote spawns; no local compile)

```bash
bb login   # once per machine / repo

git push -u origin main
bb build //:app.web
bb test  //:widget_test
```

Local `bazel build` without credentials will fail remote execution (by design).

## Targets

| Target | Notes |
|--------|--------|
| `//:app.web` | Hermetic web (primary) |
| `//:widget_test` | Widget tests |
| `//:app.linux` | Manual; needs desktop deps on the *worker* story later |

## Config

- `.bazelrc` — remote cache + executor always on; `no-local` on all actions
- `buildbuddy.yaml` — optional BuildBuddy Workflows after GitHub app is connected
- Output root: `/mnt/workspace/.cache/bazel-flutter-hello`
