# Agent rules for this repo

## Build policy (non-negotiable)

1. **Push first.** Never start a BuildBuddy / RBE build until `main` (or the branch) is pushed to `origin`.
2. **Always remote.** Use `bb`, not bare `bazel`. Spawns must run on RBE; do not run local compiles.
3. **Do not** use local `flutter build` / host SDK as the product build path.

```bash
# Correct sequence
git status   # clean
git push -u origin HEAD
bb build //:app.web
bb test  //:widget_test
```

`.bazelrc` forces remote spawns by default (`spawn_strategy=remote`, `local_resources=0`, `no-local` on all actions, `remote_local_fallback=false`).

Coordinator-only work (analysis, repo fetches) still runs where `bb` is invoked; **compile/link/test actions must not run on the agent host.**
