# Pipeline report — 2026-10-17 task (run 2026-10-18)

Branch `chore/deploy-dry-run-and-pipeline-2026-10-17` from `origin/main` @ `474251ee`
(Merge PR #1493). Environment: cloud VM, Node v22.22.0, npm 10.9.4, Python 3.13.16.
Output below is pasted from the real runs (long lists trimmed with `…`, never summarised).
No fixes were made outside Deliverable 1; findings are listed in the VERDICT.

> **Context that changes how to read this report:** since the task text was written, #1343
> landed on `main` (10-18): the app is now **Vite 6 + Vitest 3 + ESLint 9** (not CRA/craco/Jest),
> and `package.json` requires **node >=24**. `AGENTS.md` still describes the CRA/Jest setup.

---

## 1. INSTALL — `npm ci`  ❌ FAILED (twice, environmental), fell back to `--ignore-scripts`

```
$ node -v && npm -v
v22.22.0
10.9.4

$ npm ci                      # run 1
npm warn EBADENGINE Unsupported engine {
npm warn EBADENGINE   package: 'webgpu-react-app@0.1.0',
npm warn EBADENGINE   required: { node: '>=24' },
npm warn EBADENGINE   current: { node: 'v22.22.0', npm: '10.9.4' }
npm error code 1
npm error path /home/user/image_video_effects/node_modules/@huggingface/transformers/node_modules/onnxruntime-node
npm error command failed
npm error command sh -c node ./script/install
npm error Error: read ECONNRESET
npm error   errno: -104,  code: 'ECONNRESET',  syscall: 'read'
exit=1

$ npm ci                      # run 2 (the one allowed rerun) — identical failure
npm error path /home/user/image_video_effects/node_modules/@huggingface/transformers/node_modules/onnxruntime-node
npm error Error: read ECONNRESET
exit=1
```

The reset is **not sharp** (as the task anticipated) but `onnxruntime-node`'s postinstall.
The agent-proxy status endpoint shows why — the binary download goes to `api.nuget.org` and the tunnel is cut:

```
2026-10-18T11:39:05Z ws_closed_mid_exchange  api.nuget.org:443
  tunnel closed (code 1006, Connection ended) after 7s; 1568 B sent, 39 B received
```

Retries stopped there. **Deviation:** to keep the remaining stages runnable I used
`npm ci --ignore-scripts` (skips *all* dependency postinstalls, including onnxruntime-node's native
binary; none of the stages below load it):

```
$ npm ci --ignore-scripts
added 413 packages, and audited 414 packages in 11s
exit=0
```

## 2. TYPECHECK + TEST

```
$ npx tsc --noEmit
exit=0    (no output)
```

`npm test -- --watchAll=false --ci` **fails as written** — `npm test` is `vitest` now, which rejects Jest flags:

```
$ CI=true npm test -- --watchAll=false --ci
CACError: Unknown option `--watchAll`
exit=1
```

Used the repo's non-watch script instead (`"test:ci": "vitest run"`):

```
$ npm run test:ci
 Test Files  168 passed (168)
      Tests  1416 passed | 1 skipped (1417)
   Start at  11:40:16
   Duration  57.72s (transform 5.76s, setup 10.31s, collect 14.55s, tests 14.74s, environment 76.81s, prepare 15.96s)
exit=0
```

## 3. BUILD

```
$ SKIP_WASM_BUILD=1 npm run build
[INFO] SKIP_WASM_BUILD=1 — skipping WASM build (emcc not found).
       Use committed artifacts in public/wasm/ or run on a machine with emsdk.
…
build/static/js/main.f654aaf5.js                      1,107.01 kB │ gzip:   310.88 kB │ map: 3,185.10 kB
build/static/js/web-llm.40e14b1d.chunk.js             6,041.01 kB │ gzip: 2,144.45 kB │ map: 7,119.13 kB
(!) Some chunks are larger than 500 kB after minification.
✓ built in 16.92s
exit=0

$ npm run verify:bundle-size
Bundle policy passed:
  main: 302.61 KiB gzip / 325.00 KiB budget
  lazy (excluded): auto-dj.js 6.97 KiB gzip
  lazy (excluded): transformers.js 166.80 KiB gzip
  lazy (excluded): web-llm.js 2092.72 KiB gzip
  lazy (excluded): gpu-encode.js 8.82 KiB gzip
  lazy (excluded): render-worker.js 51.87 KiB gzip
  lazy (excluded): osc.js 2.59 KiB gzip
  lazy (excluded): graph-lab.js 15.58 KiB gzip
  lazy (excluded): graph-lab-canvas.js 59.96 KiB gzip

$ npm run verify:dependency-boundaries
Dependency boundary policy passed:
  TypeScript: 5.9.3 installed (~5.9.3 declared)
  dependency declarations: no duplicate direct or aliased packages
  AI packages: referenced only through their dynamic loader modules
  base-url hygiene: no absolute test-CDN URLs leaked into committed shader lists
```

**Did it move?** Yes: **324.61 → 302.61 KiB (−22.00 KiB, headroom 0.39 → 22.39 KiB)**.
Most likely cause: the CRA→Vite 6 migration (`5dcad15b`, #1343 Phase 2, merged 10-18) landed between
the two measurements. I did not bisect to confirm. Note also that this build ran on Node 22, not the required 24.

## 4. SHADER LISTS

```
$ node scripts/generate_shader_lists.js      → exit=0
Generated … Done. generate-shader-id-aliases: wrote 20 aliases (public + src/utils)

$ npm run build:manifest                     → exit=0
✅ Wrote 1392 shaders (14 categories) to public/shader-manifest-unified.json
sync-readme-catalog-counts: README already up to date (1,392 shaders)

$ git status --short                         ❌ NOT EMPTY
 M README.md
 M public/shader-search-index.json
```

The same two files were already dirtied by the `prebuild` `gen` step in stage 3. Diff (`README.md`):

```
-… a catalog of **1,391** compute shaders across 14 categories.
+… a catalog of **1,392** compute shaders across 14 categories.
-| **generative** | 496 | …
+| **generative** | 497 | …
-| **Total** | **1,391** | 14 canonical categories |
+| **Total** | **1,392** | 14 canonical categories |
```

plus a one-line regeneration of `public/shader-search-index.json` (3 KB diff, single line). I reverted both
files (`git checkout`) so they are **not** in this PR. On the committed tree:

```
$ npm run verify:catalog-counts
  shader-lists:   1392
  README total:   1391
verify:catalog-counts failed:
  - README advertises 1391 shaders but manifest has 1392
$ npm run verify:generated-sync
verify-generated-sync: committed generated files match a fresh regeneration
```

(CI most likely does not catch this: its `Build project` step runs `prebuild`/`gen`, which rewrites the README via `sync-readme-catalog-counts`, before `Verify catalog count SoT` — inferred from the job's step order, not tested.)

```
$ npm run verify:toolchain-foundation        → exit=1
verify:toolchain-foundation: 12/13 gates passed
Failed gates:
  - verify:prelude-migration

=== verify:prelude-migration ===
❌ R2 `bubble-lens` no longer pastes the header — remove it from src/contracts/prelude_migration.json pending
❌ R2 `bubble-chamber` no longer pastes the header — remove it from src/contracts/prelude_migration.json pending
prelude migration: 670 shaders include _prelude.wgsl, 768 still paste it (binding-type 1, eligible 754, renamed-binding 6, struct-field-order 7)
❌ prelude migration check failed (2 error(s))

=== verify:naga-wasm:all ===
naga-wasm (30.0): 1442 file(s) in 6397ms — 1413 valid, 29 invalid (29 known, 0 new)
✓ naga-wasm validation passed
--- verify:naga-wasm:all ok (6.6s)
```

`verify:naga-wasm:all` **passes**; `volumetric-depth-zoom` is not among the 29 known-bad shaders, so the
"commit 440d072 on claude/exciting-faraday-abr9u2" note is not needed on this `main`. The prelude failure is the
only red gate, and it **reproduces in CI**: run 39112377831 (`main` @ `474251ee`), job `wgsl-precommit-gate` step
"Prelude migration ratchet" = failure, and job `test` step "Enforce bundle and dependency boundaries" fails with
`Failed gates: - verify:prelude-migration`. The two prior `main` pushes (runs 2880, 2878) also concluded `failure`; I only read the failure reason for 39112377831.
I did not edit `src/contracts/prelude_migration.json`.

## 5. DEPLOY DRY-RUN (against the `build/` from stage 3)

```
$ python3 tools/deploy/deploy.py --dry-run          → exit 0
🔍 Verifying build integrity…
   ✓ JS bundle OK: main.f654aaf5.js (1.06 MB)
   ✓ CSS bundle OK: main.997aa35f.css (73.3 KB)
DRY RUN — tools/deploy/deploy.py (no network connection opened, nothing written)
  Destination root : test.1ink.us/image_video_effects
  Local build dir  : build
  Manifest         : .deploy_manifest.json (231 tracked files; read-only)

Files to upload (2828):
  asset-manifest.json                                                  1.4 KiB  always
  b3cursor.gif                                                             0 B  new
  cursor.cur                                                             766 B  new
  …
Remote files to delete (13):
  static/js/main.d7ca0e24.js.map
  static/js/main.d7ca0e24.js.LICENSE.txt
  static/js/main.d7ca0e24.js
  static/js/main.503c20e6.js  (+ .LICENSE.txt, .map)
  static/js/main.1ee74a77.js  (+ .LICENSE.txt, .map)
  shaders/spec-histogram-equalize-sg.wgsl
  shaders/pp-sharpen-sg.wgsl
  shaders/rd-on-video-pass1-sg.wgsl
  shaders/slime-mold-on-video-sg.wgsl
Totals:
  upload  : 2828 files, 150.9 MiB (158252933 bytes) — 2 always, 214 hash-changed, 2612 new
  skip    : 2 files unchanged
  delete  : 13 remote files
  note    : remote-size shortcut not evaluated offline: the real run may skip some 'new'/'hash-changed' files whose remote size already matches

$ python3 tools/deploy/deploy_app_only.py --dry-run  → exit 0
DRY RUN — tools/deploy/deploy_app_only.py (no network connection opened, nothing written)
  Destination root : test.1ink.us/image_video_effects
  Manifest         : .deploy_app_manifest.json (431 tracked files; read-only)
  Skipped dirs     : shaders/

Files to upload (1102):
  asset-manifest.json            1.4 KiB  always
  index.html                      527 B  always
  shader-manifest-unified.json   2.1 MiB  hash-changed
  …
Remote files to delete: n/a (this script never deletes remote files)
Totals:
  upload  : 1102 files, 115.8 MiB (121475196 bytes) — 2 always, 112 hash-changed, 988 new
  skip    : 286 files unchanged
  delete  : n/a
  note    : 31 manifest entries point at files no longer in build/ (never deleted remotely by this script)
```

`git status --short` after both runs: unchanged from before (only the two stage-4 generated files);
`git diff --quiet -- .deploy_manifest.json .deploy_app_manifest.json` → clean.

**No socket confirmed, two ways.**
*By code:* the dry-run path is `parse_args → run_dry_run → verify_build_integrity/verify_build → load_manifest →
compute_plan → format_plan`. It never calls `load_credentials()` or `open_sftp()`; `deploy_credentials` is only
imported (it imports `paramiko` lazily inside `open_sftp`), so no credential file/key/prompt is touched.
*By execution:* both scripts were run through their real `__main__` under a harness that makes
`socket.socket.__init__`, `getaddrinfo`, `create_connection`, `getpass.getpass` raise and blocks `import paramiko`:

```
[harness] tools/deploy/deploy.py exited 0; no socket, no paramiko, no getpass
[harness] tools/deploy/deploy_app_only.py exited 0; no socket, no paramiko, no getpass
```

The unit tests (`python3 -m pytest tools/deploy -q` → 12 passed) include the same guard, and a mutation check
(adding `load_credentials()` to the dry run) makes them fail.

## 6. BACKEND

```
$ python -m pytest storage_manager/tests/ -q      # system python, deps not installed
ModuleNotFoundError: No module named 'fastapi' / 'pytest_asyncio'
5 errors in 0.28s            (exit=2 — missing deps in the VM, not a code failure)

$ <venv>/bin/pip install -r storage_manager/requirements.txt   → exit=0
$ <venv>/bin/python -m pytest storage_manager/tests/ -q
104 passed, 50 warnings in 1.75s          (warnings: datetime.utcnow()/utcfromtimestamp() deprecations)

$ curl -sS -m 10 https://ford442-storage-manager.hf.space/api/health
The space is paused, ask a maintainer to restart it
[http_code=503]

$ curl -sS -m 10 -o /dev/null -w "%{http_code}" "https://ford442-storage-manager.hf.space/api/songs?type=image"
503
```

The host **is** reachable from this network (it answered, with Hugging Face's own paused-Space message) — the
backend is down on the HF side, not blocked here. Single attempt each, no retries.

## 7. DEPENDENCY AUDIT

```
$ npm audit --omit=dev
found 0 vulnerabilities

$ <venv>/bin/pip list --outdated        # venv built from storage_manager/requirements.txt
(no output — nothing outdated)
```

Caveat: `requirements.txt` uses only `>=` lower bounds, so a fresh venv resolves to the newest releases and
is trivially "current"; this says nothing about the versions the HF Space actually runs.

## 8. VERDICT

**Issues found; the pipeline is not healthy.** The client builds, typechecks and tests green, and the deploy
dry-run works, but: (1) `main` CI is red (last three pushes concluded `failure`; the latest is confirmed to fail because
`npm run verify:toolchain-foundation` fails `verify:prelude-migration` — `❌ R2 \`bubble-lens\` no longer pastes the
header — remove it from src/contracts/prelude_migration.json pending` (same for `bubble-chamber`), reproduced locally and in
CI run 39112377831); (2) the committed generated files drift from the generators — after `npm run build`,
`git status --short` shows ` M README.md` (1,391 → 1,392 shaders, generative 496 → 497) and
` M public/shader-search-index.json`, and `npm run verify:catalog-counts` on the committed tree reports
`README advertises 1391 shaders but manifest has 1392` (CI likely masks it by regenerating first); (3) the storage backend is down:
`curl https://ford442-storage-manager.hf.space/api/health` → `The space is paused, ask a maintainer to restart it`
`[http_code=503]`, and `/api/songs?type=image` → `503` (104 backend tests pass locally); (4) `npm ci` fails with
`Error: read ECONNRESET` in `onnxruntime-node`'s postinstall (nuget.org tunnel cut, twice) — I used `--ignore-scripts`;
(5) tooling docs are stale after the Vite/Vitest migration — the task's `npm test -- --watchAll=false --ci` errors with
``Unknown option `--watchAll` `` (use `npm run test:ci`: 168 files / 1416 passed, 1 skipped), `AGENTS.md` still describes
CRA/Jest/craco, `README.md:293` says the main budget is 320 KiB while `check-bundle-size.mjs` enforces 325, and
`package.json` demands node >=24 (VM has 22.22.0, `EBADENGINE`). The bundle budget line moved from 324.61 to
`main: 302.61 KiB gzip / 325.00 KiB budget` (−22.00 KiB, most likely the Vite migration). `volumetric-depth-zoom`
passes naga-wasm on this `main`, so no 440d072 note is needed. Pre-existing deploy-script defects found while
reading them (**not fixed**; `--force`/`--fresh` kept byte-for-byte equivalent): in `deploy.py`, `--force` is a no-op
beyond a confirmation prompt (the `manifest = {}` in `__main__` is never seen by `main()`, which reloads the file);
`--fresh` deletes the manifest before `clean_remote()` runs, so it removes nothing remotely; and `main()` swallows
all exceptions and exits 0 even when the upload fails. The committed manifests are also far from the build
(`.deploy_manifest.json` tracks 231 files vs 2,830 in `build/`), so a first real run would upload everything the dry run lists.
