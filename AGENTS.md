# Agent rules — zero local analysis

## Only allowed build command

```bash
git push origin HEAD
bb remote --run_from_branch=main --os=linux build //:app.web
# Stage for local serve (download only — not local compile):
rm -rf dist/web && mkdir -p dist/web
cp -a bb-out/bazel-out/k8-fastbuild/bin/app.web_build_artifacts/. dist/web/
python3 -m http.server 8080 --directory dist/web
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
