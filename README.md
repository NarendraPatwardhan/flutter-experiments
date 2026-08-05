# flutter-bazel-hello

Minimal Flutter + rules_flutter. **All builds run on BuildBuddy remote runners** (Workflows). Agent hosts do not run Bazel analysis or compiles.

## How to build

```bash
git push origin main
```

Then open [app.buildbuddy.io](https://app.buildbuddy.io/) for the workflow invocation.

Do **not** run `bb build` or `bazel build` on a laptop/agent for product builds — analysis (including Flutter SDK fetch) would run locally.

## Setup (once)

1. [BuildBuddy](https://app.buildbuddy.io/) GitHub app on `NarendraPatwardhan/flutter-experiments`
2. Workflows enabled for this repo
3. `buildbuddy.yaml` in tree (already)

## Targets (run only in Workflows)

- `//:app.web` — hermetic web
- `//:widget_test` — tests

`.bazelrc` still forces remote **spawns** (RBE) when Bazel runs on the workflow runner.
