# Agent rules — zero local analysis

## Only allowed build command

```bash
git push origin HEAD
bb remote build --run_from_branch=main //:app.web
bb remote test  --run_from_branch=main //:widget_test
```

| Command | Allowed? |
|---------|----------|
| `bb remote build` / `bb remote test` | **Yes** — Bazel client + analysis on BuildBuddy remote runner |
| `bb build` / `bazel build` | **No** — analysis on this host |
| Host `flutter build` | **No** |

`--run_from_branch=main` (or `--run_from_commit=<sha>`) makes the remote runner check out GitHub, not upload a local analysis tree.

## After push

Watch: https://app.buildbuddy.io/

Optional CI: `buildbuddy.yaml` (GitHub app must be connected).
