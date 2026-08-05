# flutter-bazel-hello

Minimal Flutter + rules_flutter with **zero local Bazel analysis**.

## Build (only path)

```bash
bb login   # once

git push origin main
bb remote build --run_from_branch=main //:app.web
bb remote test  --run_from_branch=main //:widget_test
```

That runs the Bazel client on BuildBuddy’s remote runner (analysis + Flutter SDK fetch + RBE spawns). This laptop is not the coordinator.

Do **not** use plain `bb build` / `bazel build` here.

## Targets

- `//:app.web` — hermetic web  
- `//:widget_test` — tests  
