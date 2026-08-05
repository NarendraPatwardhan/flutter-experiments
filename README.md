# flutter-bazel-hello

Minimal Flutter + rules_flutter with **zero local Bazel analysis**.

## Build (zero local analysis) + fetch outputs for local run

```bash
bb login   # once
git push origin main

bb remote --run_from_branch=main --os=linux build //:app.web
# Outputs land under bb-out/… then stage for a short path:
rm -rf dist/web && mkdir -p dist/web
cp -a bb-out/bazel-out/k8-fastbuild/bin/app.web_build_artifacts/. dist/web/

# Run locally (static server only — not a local Flutter/Bazel build)
python3 -m http.server 8080 --directory dist/web
# open http://127.0.0.1:8080/
```

Bazel analysis/build runs on BuildBuddy. Fetching `//:app.web` outputs to this machine is intentional so you can serve them.

## Targets

- `//:app.web` — hermetic web  
- `//:widget_test` — tests  
