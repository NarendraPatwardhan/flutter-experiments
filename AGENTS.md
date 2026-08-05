# Agent rules

## Builds are fully remote. No local Bazel.

| Forbidden on agent host | Required |
|-------------------------|----------|
| `bazel build` / `bazel test` | Push → BuildBuddy Workflows |
| `bb build` / `bb test` (local coordinator) | `git push` then watch BuildBuddy UI |
| Host `flutter build` | Workflow job on BuildBuddy runners |

**Why:** `bb build` still runs **analysis + Flutter SDK repo fetch on the machine that invokes it**. That is local. This repo uses **BuildBuddy Workflows** so the remote runner is the coordinator (analysis + fetches + RBE spawns).

## Correct sequence

```bash
git add -A && git commit -m "..."
git push origin HEAD
# Preferred CI path: BuildBuddy Workflows (push-triggered)
# Interactive full-remote path (remote coordinator, not this host):
bb remote build //:app.web
bb remote test  //:widget_test
```

Never: bare `bb build` / `bazel build` on the agent host (that is local analysis).

## One-time: connect the repo

BuildBuddy dashboard → GitHub app → enable workflows for `NarendraPatwardhan/flutter-experiments`.

Config: `buildbuddy.yaml` (checked in).