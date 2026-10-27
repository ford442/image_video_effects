# image_video_effects — 2026-10-24 dispatch

**Status:** `main` @ `c88e6085` is **green** (runs 2916–2922 since 10-20). Last week's #1449 §1–§3 shipped as PR #1473 (bundle 324.61 → 313.15 KiB), the 10-26 thumbnail cliff was defused by PR #1493, and `deploy.py --dry-run` finally landed in PR #1494. Noah's 2026-10-21 review (#1511) found eleven user-facing bugs and a secret in the shipped bundle that green CI cannot see; #1512/#1513 wait on it. Board: 8 open.

## Mode declaration

**Fix First.** CI is green and last week's tracks all shipped, but #1511 — Noah's own 10-21 audit, labelled `bug` — says "fix these first", two of its items are ours (bug 7 is a regression of last week's #1449 §2c pipeline LRU; bug 2 is `REACT_APP_WEBHOOK_SECRET` inlined into the client by `vite.config.ts`), and both roadmap issues (#1512, #1513) declare `Depends on: #1511`. Nothing new gets built on a renderer whose upload button is a no-op and whose upload signing key is public.

## Context from prior sessions

- **10-17 tracks, all shipped.** A: PR #1473 merged 10-17 23:26 (nine commits `e52bc81e`..`e37a2210`: README count, required-checks doc, OOM-retry pool reset, `'oom'` vs `'lost'`, one 32-entry FNV-1a-keyed LRU, float32-blendable from the device, real device-thread report, lazy `WASMRenderer`); `.swarm-state.md` closeout 163 suites / 1376 passed; #1449 CLOSED, §4/§5 not started. B: PR #1493 (10-18) removed the 39 deferrals (ratchet 41 → 2) and moved expiry to a scheduled `--expiry` job; today's gate: 21 entries / 19 pending / ratchet 20, exit 0; follow-up #1492. E: PR #1494 (10-18) added `--dry-run` to both deploy scripts plus `pipeline_report_2026-10-17.md` — fifth attempt.
- **Noah's 10-17 → 10-23 merge train** closed the rest of the 10-14 set: #1450 toolchain via #1477/#1480/#1485 (**Vite 6 + Vitest 3 + ESLint 9 + TS 5.9, Node ≥ 24; `craco.config.js` is gone**), #1451 slice 1 (#1487), #1430 (#1476), #1431 (#1465), #1434 (`hydrateDurations` now only in `useB3hdMode.ts`), #1484 JSPI dual build, the #1403–#1408 usability set, ~14 shader batches, four Jules PRs.
- **10-18/10-19 red streak:** 11 of 17 `main` runs failed — the toolchain migration landing in pieces (run 2885: `jest` globals in `WASMBridge.call.test.ts` under the Vitest typecheck), the `f3798000` "push fix" direct push leaving 17 pending deferrals vs ratchet 2 (run 2893), an npm `ENETUNREACH` (run 2914). All cleared by run 2916. Direct pushes to `main` still bypass every gate.
- **Noah's 2026-10-21 audit:** #1508 (CI WASM — premise mostly stale, see Backlog), #1509 (sim-ring spatial hash + two flagships), #1510 (`future`: crossfade cue recall), **#1511 (Foundation sweep, `bug`)**, #1512 (tier 2 + compositor + GPU runner), #1513 (modulation matrix + Graph Lab slice 2 + Physics Lab set 2). Plus #1492 (GPU re-capture, parked) and #1401 (`future`).
- **Open PRs:** #1505 `opus/batch-10` (Noah, no check runs on its head; touches `scripts/generate-shader-thumbnails.js`, `scripts/lib/thumbnailHarness.mjs`, `src/contracts/prelude_migration.json` — today's tracks avoid those), #1497 `opus/batch-08` (red since 10-19), drafts #1517/#1518/#1519 (Jules).
- **Gaps (real signal):** no chat-history tools again (`recent_chats` / `conversation_search` unavailable), no `memory/` files, `node_modules` absent and Node 22 on this VM (repo wants ≥ 24), so nothing was built or tested here — every claim below is a tree read (`grep`/`sed`) or a GitHub API read. `AGENTS.md` and the routine's PROJECT CONTEXT both still describe CRA/Jest; the commands in this dispatch follow `package.json` on `main`.

## weekly_plan.md changes

- **Today's focus:** new 2026-10-24 Fix First block (reconciliation with PR numbers, why-Fix-First with run numbers, tree-verified line refs for bugs 1/2/3/5/6/7/8/9, track boundaries); the 10-17 block archived in `<details>` with its outcome.
- **Ideas:** 2026-10-24 note; **#1511 marked `[in progress — 2026-10-24]`**; added #1508 (with the stale-premise finding), #1509, #1510, #1512, #1513, #1492, and a "file #1511 bug 4 as its own issue" item; #1449 → DONE (PR #1473); #1450 → DONE (#1477/#1480/#1485); #1451 → slice 1 DONE (#1487); #1430 → CLOSED (#1476); #1431 → DONE (#1465); #1434 → CLOSED (tree-verified); the 10-26 thumbnail wave → DONE (#1493); #1403–#1408 → CLOSED.
- **Backlog:** eight 10-17 items resolved with evidence (red main, bundle, thumbnail cliff, deploy dry-run, PR #1465, #1434, board hygiene; the "three reds" item marked `[~]` with the second streak recorded); 9 NEW 2026-10-24 items (shipped webhook secret + rotation, bug 7 regression, bugs 4/11 homeless, #1508 stale premise, `AGENTS.md` wrong toolchain + Node 22 vs ≥ 24, open PRs to steer around, Actions Node 20 deprecation warnings, root files the routine depends on being on the clutter list, the `f3798000` direct push).
- **Done:** 2026-10-24 reconciliation entry (what shipped, with commits, plus Noah's merge train and the 10-21 audit).
- **Last run:** 10-17 outcome filled in (SHIPPED ×3); 2026-10-24 entry appended.

## Today's focus

**#1511 — "Foundation sweep 2026-10-21: dead file upload, client-side webhook secret, BGL float32-filterable + TS/C++ layout drift, input/MIDI/worker-cache bugs, renderer dedupe, build/repo hygiene"** (Noah, 2026-10-21; labels `bug`, `build`, `renderer`, `infrastructure`). Scope today: **Part 1, bugs 1, 2, 3, 5, 6, 7, 8, 9, 10**, each with a Vitest regression test. Bug 2's server half is a signing proxy in `storage_manager/` (the receiver `/webhook/image-effects` is not in this repo; `storage_manager/` has no HMAC code today). **Out:** bug 4 (bind-group-0 contract generated for TS + C++ — its own issue, added to Ideas), bug 11 (C++ `wgpuInstanceWaitAny` budgets — needs emcc), Part 2 (TS organization — after Part 1), Part 3 (today's issue B).

Verified in tree this run: bug 1 `src/components/app/AppShell.tsx:497-498` (`onChange={() => {}}`; `RemoteApp.tsx:226/284/291` has a working `handleFileUpload`); bug 2 `vite.config.ts:22`, `src/config/appConfig.ts:61`, `src/services/storage/client.ts:57`, `webhook.ts:26-32`; bug 3 `src/renderer/webgpu/pipeline.ts:220/228/235` (`sampleType: fST` from the device feature), `src/config/formatPolicy.ts:155`; bug 5 `src/components/WebGPUCanvas.tsx:716`; bug 6 `src/services/midiControl.ts:172/217`; bug 7 `src/renderer/worker/WorkerWebGPUBackend.ts:131/259/443`, consumer `src/graphLab/runDraft.ts:83,90`; bug 8 `src/AutoDJ.ts:341/538`; bug 9 `src/renderer/webgpuBootProbe.ts:596`.

## Dispatch

### A. Swarm task — Claude Code, long-running

```
You are working in ford442/image_video_effects (Pixelocity): a React 19 + TypeScript WebGPU shader playground built with Vite 6, tested with Vitest 3, linted with ESLint 9, TypeScript 5.9, Node >= 24. The TypeScript renderer under src/renderer/ is the production path and runs in a render worker by default (`?renderer=main` keeps it on the page; docs/RENDER_WORKER.md). The C++/WASM renderer is R&D-frozen (`?renderer=wasm` only) and is not touched today. The Python FastAPI backend in storage_manager/ is deployed to a VPS; it is in scope for exactly one change (below). This is a long-running session: work in small verified iterations, write state to .swarm-state.md at every boundary, and expect to be paused and resumed.

OBJECTIVE
Fix GitHub issue #1511 Part 1 bugs 1, 2, 3, 5, 6, 7, 8, 9 and 10, each with a Vitest regression test. Read the issue first: https://github.com/ford442/image_video_effects/issues/1511 (gh may be unavailable; fetch it in the browser or via the API). The why: CI is green but the app's upload button does nothing, every click fires twice, MIDI adapters overwrite each other, the worker reports evicted shaders as cached (a regression from the #1449 pipeline LRU that landed 2026-10-17), and the HMAC secret that authorizes uploads to the storage VPS is inlined into the public JS bundle. #1512 and #1513 are blocked on this.

BRANCH AND BASELINE
- `git fetch origin main && git checkout -b fix/1511-part1-bugs origin/main`.
- Node >= 24 is required (`nvm use 24` or equivalent). `npm ci` (if the `sharp` postinstall fails with ECONNRESET, rerun).
- Record the baseline in .swarm-state.md before changing code:
  `npx tsc --noEmit` (expect clean), `npm run test:ci` (Noah measured 169 files / 1435 tests on 10-21; record yours), `npm run lint` (0 errors; `--max-warnings 125` is a ratchet, do not exceed it), `SKIP_WASM_BUILD=1 npm run build`, `npm run verify:bundle-size` (expect about 313 KiB gzip / 325 budget), `npm run verify:toolchain-foundation` (needs the build; if `verify:catalog-counts` complains, run `npm run build:manifest` first), and `python3 -m pytest storage_manager/tests -q`.
- If the baseline is red on main, record it, do not fix it, and continue — you are not here to fix the toolchain.

ALLOWED TO EDIT
- src/components/app/AppShell.tsx, src/RemoteApp.tsx, a new src/hooks/useLocalMediaUpload.ts (bug 1)
- vite.config.ts (ONLY the KNOWN_APP_ENV list), src/config/appConfig.ts, src/services/storage/** , storage_manager/** (bug 2)
- src/renderer/webgpu/pipeline.ts, src/config/formatPolicy.ts (bug 3)
- src/components/WebGPUCanvas.tsx (bug 5)
- src/services/midiControl.ts, src/App.tsx (only the MIDI effect around lines 389-400), src/hooks/useLiveControl.ts (bug 6)
- src/renderer/worker/WorkerWebGPUBackend.ts (bug 7)
- src/AutoDJ.ts (bug 8)
- src/renderer/webgpuBootProbe.ts (bugs 9 and 10)
- New or existing test files next to the code you change; .swarm-state.md.
- docs/RENDER_WORKER.md, docs/STORAGE_API.md, docs/WEBGPU_BOOT_PROBE.md, docs/DEVICE_FEATURES.md — doc lines only, where behavior you changed is described.

DO NOT TOUCH (read if you need to, never edit)
public/shaders/**, shader_definitions/**, public/shader-lists/**, public/thumbnails/**, wasm_renderer/**, public/wasm/**, src/wasm/**, src/contracts/**, scripts/**, .github/**, package.json, package-lock.json, tsconfig*.json, eslint.config.mjs, README.md, AGENTS.md, weekly_plan.md, weekly_dispatch.md, reports/**, tools/**, and the three files Noah's open PR #1505 edits: scripts/generate-shader-thumbnails.js, scripts/lib/thumbnailHarness.mjs, src/contracts/prelude_migration.json. Bug 4 (bind-group-0 contract codegen) and bug 11 (C++ WaitAny budgets) are explicitly OUT. If a fix seems to need a forbidden file, write the proposed change into .swarm-state.md under "needs Noah" and move on.

WORK ITEMS, IN ORDER (one commit per bug, message `fix(<area>): <what> (#1511 bug N)`; never write "Closes #1511")
1. Bug 2, client half — stop shipping the secret. Remove 'REACT_APP_WEBHOOK_SECRET' from KNOWN_APP_ENV in vite.config.ts; delete STORAGE_WEBHOOK_SECRET from src/config/appConfig.ts and the `secret` field from the storage client config (src/services/storage/client.ts:57). Change src/services/storage/webhook.ts so the browser never computes an HMAC: `webhookSave` POSTs the unsigned payload to the storage manager proxy route from item 2 (`${STORAGE_API_URL}/api/webhook-proxy/image-effects`), and surfaces the proxy's error body on non-2xx. Add a source-scan contract test (pattern: the lazy-WASM source-scan test from #1449 §3) asserting that no file under src/ or vite.config.ts contains `WEBHOOK_SECRET` or `your-webhook-secret-here`, and that KNOWN_APP_ENV does not list it. Record in .swarm-state.md "needs Noah": rotate the webhook secret on the VPS receiver — the current value is in every deployed bundle.
2. Bug 2, server half — a signing proxy in storage_manager. New route module (follow the existing storage_manager/routes/* layout): `POST /api/webhook-proxy/image-effects` reads `WEBHOOK_SECRET` and `WEBHOOK_RECEIVER_URL` from the environment (via storage_manager/config.py, same style as the existing settings; refuse with 503 if unset), computes HMAC-SHA256 over the raw request body, forwards it to the receiver with `X-Hub-Signature-256: sha256=<hex>` (match what src/services/storage/webhook.ts sent before your change — read it first and keep the header shape byte-identical), and returns the receiver's status and JSON. Reuse the app's CORS allowlist; no new dependency (httpx is already used, check requirements.txt). pytest: happy path with a mocked receiver, missing env → 503, receiver 4xx passthrough. Document the two env vars in storage_manager/README.md and docs/STORAGE_API.md.
3. Bug 7 — worker proxy cache truth. In src/renderer/worker/WorkerWebGPUBackend.ts replace the `cachedIds` set from `event.snapshot.cachedShaderIds` on every snapshot instead of merging into it (line ~259); keep the optimistic add at ~443 only until the next snapshot. Test: snapshot with [a,b], then snapshot with [b] → `isShaderCached('a')` is false; graphLab/runDraft.ts then recompiles. Check runDraft.ts:83,90 still reads the right method.
4. Bug 9 — probe device leak. In src/renderer/webgpuBootProbe.ts move the `probeFormatCapabilities(adapter, ...)` call at ~596 inside the try whose finally/catch destroys the probe device. Test: make `probeFormatCapabilities` reject and assert `device.destroy()` was called exactly once.
5. Bug 5 — double down-handler. src/components/WebGPUCanvas.tsx:716 passes both onPointerDown and onMouseDown to handleMouseDown; keep only the pointer events (check that touch and pen still work through onPointerDown and that there is no matching onMouseUp/onMouseMove duplication). Test: one pointerdown dispatch → exactly one ripple/drag-start callback.
6. Bug 10 — honest tone-mapping report. In webgpuBootProbe.ts do not report `canvasToneMapping: 'extended'` as applied while the canvas is still `getPreferredCanvasFormat()` (8-bit); report 'standard' plus the existing narrowing reason. Do not touch src/contracts/canvas_configure.json. Test: probe with extended requested on an 8-bit format → 'standard' with a reason.
7. Bug 1 — file upload is a no-op. Extract RemoteApp.tsx's `handleFileUpload` (line ~226) into `src/hooks/useLocalMediaUpload.ts` returning `{ onImageChange, onVideoChange }` over the media loader it already uses; wire AppShell.tsx:497-498 inputs to it and switch RemoteApp to the same hook. Test (jsdom): a change event with a File on each input calls the loader with that file and resets the input value so the same file can be re-chosen.
8. Bug 3 — BGL sample type keyed on the format, not the feature. In src/renderer/webgpu/pipeline.ts derive the sampleType for bindings 1, 9 and the history array (lines ~220/228/235) from the texture format: rgba16float → 'float'; rgba32float → 'float' only if the device has 'float32-filterable', else 'unfilterable-float'. In src/config/formatPolicy.ts (around 198-220) demote 'ultra'/'auto' to rgba16float when `!hasFloat32Filterable` so the 957 shaders that pair readTexture with the filtering u_sampler stay valid. Test with a mock device whose features set is empty: the layout for rgba16float is 'float'; resolveColorFormat never returns rgba32float. Do not change binding 4 (depth, r32float, unfilterable-float). Run `npm run verify:device-policy` after — if it goes red because a contract expects the old behavior, stop, record it under "needs Noah", and revert this item (src/contracts is off-limits).
9. Bug 6 — MIDI listeners. In src/services/midiControl.ts replace `input.onmidimessage = ...` (lines ~172, 217) with `addEventListener('midimessage', handler)` and per-adapter `removeEventListener` in `disable()`; the `event.port.onmidimessage === null` check at ~208 must be rewritten to track subscription state yourself. In App.tsx's MIDI effect (~389-400) and useLiveControl.ts (~201) add an abort flag so a cleanup that runs before `requestAccess()` resolves does not leave a hook attached. Tests: two adapters on one input both receive a message; disabling one does not silence the other; cleanup-before-resolve attaches nothing.
10. Bug 8 — AutoDJ auto-transition races. In src/AutoDJ.ts give each `startAutoTransition` run a generation token and an AbortController; `await connectSource(...)` before starting the orchestrator; stop() aborts, cancels the 5 s setTimeout (~341) and any rAF, and disposes the audio graph exactly once. Tests with fake timers: start → stop before connectSource resolves leaves no orchestrator running and disposes the graph; overlapping start/start keeps exactly one loop; the timeout is cleared on stop.

ITERATION LOOP (after every work item)
`npx tsc --noEmit` → `npm run test:ci` → `npm run lint` (0 errors, warnings ≤ 125). After items 1, 7 and 8 also `SKIP_WASM_BUILD=1 npm run build && npm run verify:bundle-size` (the bundle must not grow by more than 0.5 KiB; the hook in item 7 should be neutral) and `npm run verify:toolchain-foundation`. After items 1-2 also `python3 -m pytest storage_manager/tests -q` and a build-output grep: `grep -rl "your-webhook-secret-here\|WEBHOOK_SECRET" build/ && echo LEAK || echo clean` — it must print clean. Fix whatever you broke before starting the next item. Never skip or delete a test; never raise the lint warning cap or the bundle limit.

SAVE STATE
At every item boundary write .swarm-state.md (overwrite; it is gitignored-but-tracked, commit it at the end only) with: branch + base sha; baseline numbers; `done` (item → commit sha → one line); `in_progress`; `blocked / needs Noah` (secret rotation, VPS deploy of the proxy with WEBHOOK_SECRET + WEBHOOK_RECEIVER_URL, anything forbidden you wanted to touch, any verify:device-policy conflict); `verification_last_run` (the five numbers); `files_touched`. A fresh session must be able to resume from that file alone.

FINISH
When items 1-10 are green (or the remaining ones are recorded as blocked with a reason), push `fix/1511-part1-bugs`, open a PR titled "Foundation sweep Part 1: upload fix, secret out of the bundle + signing proxy, BGL by format, input/MIDI/worker-cache/AutoDJ/probe fixes (#1511 bugs 1-3, 5-10)" referencing #1511 (do not auto-close it; bugs 4, 11 and Parts 2-3 remain). The PR body lists each bug → commit → test, the before/after bundle number, the `grep build/` result, and the two things Noah must do by hand (rotate the secret; deploy storage_manager with the two env vars). Then write the final .swarm-state.md and stop.
```

### B. GitHub issue — draft now (Claude implementation prep)

**Title:** Build/CI/repo hygiene after the Vite move: opt-in WASM prebuild, `wasm.yml` path filter + action pins, root clutter, Vite-era `AGENTS.md`/`README.md` (#1511 Part 3 + #1508 residue)

**Context / motivation**

`main` moved to Vite 6 + Vitest 3 + ESLint 9 + TypeScript 5.9 with Node ≥ 24 on 2026-10-18 (#1477, #1480, #1485; `craco.config.js` is gone). The build and repo plumbing around it did not move with it, and that is now costing real sessions: `AGENTS.md` still tells every agent to run `npm test -- --watchAll=false --ci` "Jest via craco", which errors under Vitest, and describes a CI `wasm` job that no longer exists; the weekly routine's own context block repeated the same stale facts. Meanwhile `npm run build` still runs `wasm:build` in `prebuild`, so every app build needs emcc or `SKIP_WASM_BUILD=1` for a backend that policy froze (#1329, `docs/WASM_BACKEND_POLICY.md`). #1511 Part 3 lists the cleanup; #1508 asked for the CI half but was written against a pre-Vite tree — on `main` today `ci.yml` has no `wasm`/`test-wasm-e2e` job (jobs: `test`, `wgsl-precommit-gate`, `catalog-consistency-audit`, `lint`, `thumbnail-coverage`) and `wasm.yml`'s artifact hash compare already fails the job. What is left of #1508 is small and belongs here. Every GitHub Actions job also prints `Node.js 20 is deprecated` for `actions/checkout@v4`, `setup-node@v4`, `setup-python@v5`, `upload-artifact@v4`.

This is pipeline plumbing for the active focus areas (shader authoring at 1,391+ shaders, the TS renderer) — a shader-only PR must not need emcc, and an agent reading the repo must get the right test command on the first try. It is fully decoupled from #1511 Part 1 (the renderer/UI/storage bug fixes run in a separate branch and never touch `package.json`, `.github/**`, docs or root files).

**Proposed approach (first pass — Noah will expand)**

1. **Opt-in WASM build.** `package.json` `prebuild` becomes `npm run gen`; add `build:wasm` / `BUILD_WASM=1` (or keep `wasm:build` as the explicit command) so `npm run build` uses the committed `public/wasm/*` by default. Keep `wasm:validate` in the `test` job so a PR that forgets to commit `public/wasm/` still fails. Update `wasm_renderer/build.sh`'s "missing emcc is a hard failure unless SKIP_WASM_BUILD=1" message to the new contract; drop `SKIP_WASM_BUILD` only if nothing else reads it (grep CI, docs, scripts).
2. **`wasm.yml` path filter** gains `src/contracts/wasm_compile_flags.json`, `src/contracts/wasm_exports.json`, `src/wasm/bridge/**`, `scripts/format-wasm-compile-flags.js`, `scripts/emcc-version-gate.sh`, `scripts/gen-*-header.js`, `scripts/emit-wasm-bridge.mjs`; one sentence in `docs/WASM_BUILD_CI_GUIDE.md` or the workflow header that `ci.yml` does not compile WASM. Delete `jspi.sFlags` from `wasm_compile_flags.json` only if `verify:device-policy` / `format-wasm-compile-flags.js` do not read it — otherwise record it and leave it.
3. **Action pins.** Bump `actions/checkout`, `setup-node`, `setup-python`, `upload-artifact`, `download-artifact` (and `mymindstorm/setup-emsdk` in `wasm.yml` if a Node-24 release exists) to the current majors across all six workflows; keep `node-version` at 24.
4. **Root clutter.** Delete `swarm_sync.sh` (loops `git add -A && git commit && git push origin main`). Delete or rewrite `test_shaders.sh` (embeds the old pasted binding header, which CI forbids). Move `build.sh` to `tools/deploy/` and fix every reference (`npm run deploy*`, docs, `.htaccess` comment in `vite.config.ts`). Move `pipeline_report_2026-10-17.md` to `docs/reports/`. Decide `shader_queue/` (move to `tools/` or delete — check `shader_plans/queue.json` is the live queue). **Leave `weekly_plan.md`, `weekly_dispatch.md`, `.swarm-state.md` where they are** (the weekly routine writes them at the root; moving them is a routine change, not a repo change — open question below). Do not gitignore `reports/` in this issue: `verify:*` baselines and `catalog_drift_baseline.json` live there; list which files would need to move first.
5. **Docs.** Rewrite `AGENTS.md` "Services / commands" for Vite/Vitest/Node ≥ 24 (`npm start` = Vite dev server, `npm run test:ci`, `npm test` is watch mode, `npm run lint` with the 125-warning ratchet, `npm run typecheck`, build without emcc), and the `README.md` lines that still say Jest/CRA (`README.md:102`, `:294`). Fix `docs/GRAPH_LAB.md:70` ("remain open on #1451" → #1512/#1513), `docs/PARALLEL_SLOTS.md` slot count if it still says 3, and add a one-line deprecation note to `docs/plans/*` or move them under `docs/plans/archive/`.

**Acceptance criteria (rough)**

- [ ] `npm run build` succeeds on a machine with no emcc and no `SKIP_WASM_BUILD`; `npm run wasm:validate` still runs in the `test` job and fails on a stale/missing `public/wasm/*`.
- [ ] A PR touching only `public/shaders/**` + `shader_definitions/**` does not trigger `wasm.yml`; a PR touching `src/contracts/wasm_compile_flags.json` or `src/wasm/bridge/**` does.
- [ ] No `Node.js 20 is deprecated` warning on a fresh CI run of `ci.yml`.
- [ ] `swarm_sync.sh` is gone; `test_shaders.sh` is gone or passes `scripts/wgsl_precommit_gate.py`; `build.sh` lives in `tools/deploy/` and `npm run deploy:full` still works (`--dry-run`).
- [ ] `AGENTS.md` and `README.md` contain no `craco`, `react-scripts`, `--watchAll` or "Jest" as the current test runner; a fresh agent following `AGENTS.md` runs the right commands.
- [ ] `docs/TOOLCHAIN_DECISION.md` is unchanged (it already describes Vite); `npm run verify:toolchain-foundation`, `verify:device-policy`, `verify:wasm-invariants` stay green; bundle size unchanged.
- [ ] #1508 is closed or re-cut by Noah with a pointer to this issue.

**Open questions for Noah**

1. `weekly_plan.md` / `weekly_dispatch.md` / `.swarm-state.md`: keep at the root (routine unchanged) or move to `docs/routine/` and re-point the weekly routine the same day? Default here: keep.
2. `reports/` (6.1 MB tracked): gitignore everything except the `*_baseline.json` files and move those to `src/contracts/`? Or leave tracked? Default here: leave for this issue, list the move.
3. Should `SKIP_WASM_BUILD=1` keep working as an alias for a transition period (CI `wasm.yml`, docs, other agents' muscle memory)?
4. `shader_queue/` — is `shader_plans/queue.json` the only live queue now?
5. Is `test_shaders.sh` used by any external process (Jules, the content swarm) before it is deleted?

### C. Expansion prompts for the issue in B

**C1 — Gemini Pro (has the codebase)**

```
You have the ford442/image_video_effects repository (Pixelocity: React 19 + TypeScript 5.9 WebGPU shader playground, Vite 6 build, Vitest 3 tests, ESLint 9, Node >= 24, a frozen C++/Emscripten WASM renderer under wasm_renderer/ with committed artifacts in public/wasm/, GitHub Actions CI in .github/workflows/, a Python FastAPI backend in storage_manager/, deploy scripts in tools/deploy/). Below is a draft GitHub issue. Produce a complete implementation plan for it.

Specifically:
1. For each of the five numbered approach items, list every file that must change, with the exact lines/keys (package.json scripts, workflow YAML steps, shell scripts, docs). Open and read the files; do not guess.
2. Find every reader of `SKIP_WASM_BUILD`, `wasm:build`, `prebuild`, `build.sh`, `test_shaders.sh`, `swarm_sync.sh`, `shader_queue/`, `pipeline_report_` across the repo (scripts, workflows, docs, Python, Markdown) so nothing is orphaned by a move or delete.
3. Check whether `scripts/format-wasm-compile-flags.js` or `scripts/verify-device-policy-sync.js` read `jspi.sFlags` from `src/contracts/wasm_compile_flags.json`; say whether it is dead.
4. List the current `uses:` action versions in all six workflows and which ones trigger the "Node.js 20 is deprecated" warning.
5. Identify what in `reports/` is read by a `verify:*` script (so it must stay tracked) versus what is generated output.
6. Flag anything in the draft that is already done on `main` or contradicts `docs/TOOLCHAIN_DECISION.md`, `docs/WASM_BACKEND_POLICY.md`, or `docs/WASM_BUILD_CI_GUIDE.md`.
7. Propose the PR split (which items can land independently, in what order) and the exact verification commands for each.

Output: a revised issue body (same headings) plus a "files to touch" table and a "do not touch" list.

--- ISSUE ---
<paste the full issue text from section B here>
```

**C2 — gpt-oss-120b (no codebase, no web; fully self-contained)**

```
You are reviewing a build/CI hygiene plan for a web project. Facts you can rely on (do not assume anything else about the code):

- Frontend: React 19, TypeScript 5.9, built with Vite 6 (`npm run build` = `vite build`), unit tests with Vitest 3 (`npm run test:ci` = `vitest run`), ESLint 9 with a `--max-warnings 125` ratchet, Node >= 24 required. The migration from Create React App + CRACO + Jest landed six days ago.
- A C++ renderer compiled with Emscripten (emsdk 6.0.12) lives in `wasm_renderer/`; its compiled artifacts (`public/wasm/pixelocity_wasm.wasm`, `pixelocity_wasm_jspi.wasm`, JS glue) are committed to git. Policy declares this renderer frozen R&D: parity fixes only, opt-in via `?renderer=wasm`.
- `package.json` has `"prebuild": "npm run wasm:build && npm run gen"`. `wasm:build` runs `bash wasm_renderer/build.sh`, which hard-fails if `emcc` is missing unless the env var `SKIP_WASM_BUILD=1` is set, in which case it skips and the committed artifacts are used. `gen` regenerates shader lists/manifests and must keep running before every build.
- GitHub Actions: `ci.yml` runs on every PR with jobs test, wgsl-precommit-gate, catalog-consistency-audit, lint, thumbnail-coverage; it does NOT compile WASM but runs `npm run wasm:validate` against the committed artifacts. A separate `wasm.yml` compiles WASM only on a path filter (`wasm_renderer/**`, `public/wasm/**`, `tests/wasm-*`), on a Monday cron, and on manual dispatch; it fails if the fresh build's sha256 differs from the committed artifact. The path filter does not include the JSON contracts and scripts that define the build flags (`src/contracts/wasm_compile_flags.json`, `src/wasm/bridge/**`, `scripts/format-wasm-compile-flags.js`, etc.).
- Every Actions job prints "Node.js 20 is deprecated" because `actions/checkout@v4`, `setup-node@v4`, `setup-python@v5`, `upload-artifact@v4` are pinned.
- Repo root has leftovers: `swarm_sync.sh` (a loop doing `git add -A && git commit && git push origin main`), `test_shaders.sh` (embeds an old shader header that CI now forbids), `build.sh` (actually a deploy wrapper), `pipeline_report_2026-10-17.md`, a `shader_queue/` directory of unclear liveness, and a 6.1 MB tracked `reports/` directory that mixes generated audits with `*_baseline.json` files that CI gates read.
- `AGENTS.md` (instructions agents read first) and `README.md` still describe the old CRA/Jest commands (`npm test -- --watchAll=false --ci`), which now error.

The plan under review is the issue below. Do three things:
1. Stress-test it: for each approach item, name the failure modes (e.g. making the WASM build opt-in — what breaks for someone who edits `wasm_renderer/` and forgets to rebuild? how does CI catch a committed artifact that is stale relative to the C++ source if `wasm.yml` only runs on a path filter and a cron? what does `SKIP_WASM_BUILD` removal do to existing scripts/docs/muscle memory?).
2. Generate two alternative designs for the WASM-build question specifically: (a) keep `prebuild` as is but make `build.sh` skip silently when emcc is absent and the committed artifact's recorded source hash matches; (b) a `postinstall`/`pretest` check that compares a hash of `wasm_renderer/**` + the compile-flags contract against a hash recorded next to the artifact, failing CI when they diverge — compare both with the issue's "opt-in via env var" proposal on: false-green risk, developer friction, CI minutes, and how much new code each needs.
3. Argue for one option and write it as a replacement for approach item 1, plus the precise acceptance criterion that proves a stale artifact cannot reach main unnoticed.

Also: give the current recommended major versions of actions/checkout, actions/setup-node, actions/setup-python, actions/upload-artifact as of your knowledge, with the caveat that they must be verified, and say whether pinning by SHA is worth it for a solo-maintainer repo.

--- ISSUE ---
<paste the full issue text from section B here>
```

**C3 — Grok (current ecosystem awareness)**

```
I maintain a public WebGPU shader playground (React 19, TypeScript 5.9, Vite 6, Vitest 3, ESLint 9, Node 24, an Emscripten 6.0.12 C++ WebGPU renderer that is frozen as R&D with committed .wasm artifacts, GitHub Actions CI, a Python 3.13 FastAPI backend). I am about to do a build/CI hygiene pass (issue text below). Before I do, check whether any of it is already outdated as of today. Please search for and report, with dates and sources:

1. GitHub Actions: the current major versions of actions/checkout, actions/setup-node, actions/setup-python, actions/upload-artifact, actions/download-artifact, and mymindstorm/setup-emsdk, and the status of the "Node.js 20 is deprecated / forced to Node 24" runner change (timeline, whether v4 of checkout/setup-node already run on Node 24, what breaks). Is there any reason to wait rather than bump now?
2. Vite: is Vite 7 (or newer) stable, and does it change anything relevant for a project that just moved to Vite 6 — Node version floor, `define`-based env inlining, Rolldown as the bundler, chunk naming plugins? Should the hygiene pass include a Vite major bump, or is that a separate decision?
3. Vitest: current major and whether Vitest 3 → next has breaking changes for jsdom tests, `globals: true`, `mockReset`, or coverage-v8.
4. Node: is 24 the active LTS right now, and when does 22 go maintenance-only? Any npm 11 behavior changes relevant to `npm ci` in CI (lockfile v3, peer deps)?
5. Emscripten: latest emsdk release, whether 6.0.12 is still reasonable to pin, and any change in how `-sJSPI` / ASYNCIFY builds or the emdawnwebgpu port are shipped that would make a committed-artifact hash compare brittle across emsdk patch versions.
6. WebGPU in Chrome: anything shipped in the last 60 days that affects a WebGPU app's CI (e.g. headless/SwiftShader flag changes, `featureLevel: 'compatibility'` status, `shader-f16` availability) — only what would change a CI workflow, not features.
7. Any well-known tooling for keeping a committed WebAssembly artifact in sync with its source (hash manifests, GitHub Actions patterns) that I should copy instead of inventing.

End with a short list: "safe to do now", "do differently than the issue says", "defer". Flag anything you could not verify.

--- ISSUE ---
<paste the full issue text from section B here>
```

### D. Claude implementation handoff

```
You are implementing a GitHub issue in ford442/image_video_effects (Pixelocity: React 19 + TypeScript 5.9 WebGPU shader playground; Vite 6 build, Vitest 3 tests, ESLint 9, Node >= 24; frozen C++/Emscripten WASM renderer with committed artifacts in public/wasm/; GitHub Actions in .github/workflows/; deploy scripts in tools/deploy/). The issue has been expanded and reviewed; implement it as written and nothing more.

{{EXPANDED_ISSUE}}

CONSTRAINTS
- Branch from origin/main: `git fetch origin main && git checkout -b chore/1511-part3-hygiene origin/main`. Node >= 24 (`nvm use 24`), then `npm ci`.
- This is build/CI/docs/root-file plumbing. You may edit: package.json (scripts only — no dependency changes), .github/workflows/**, wasm_renderer/build.sh, AGENTS.md, README.md, docs/**, the root scripts named in the issue, tools/deploy/** (only for the build.sh move and its references). Do NOT edit anything under src/, public/shaders/, shader_definitions/, src/contracts/, scripts/ (other than paths you must update for a moved file), storage_manager/, or the files another branch is working on: src/components/app/AppShell.tsx, src/RemoteApp.tsx, src/services/storage/**, src/config/**, src/renderer/**, src/services/midiControl.ts, src/AutoDJ.ts, src/App.tsx, src/hooks/useLiveControl.ts, vite.config.ts.
- Do not gitignore reports/ or move weekly_plan.md / weekly_dispatch.md / .swarm-state.md unless the expanded issue's open questions were answered "yes" explicitly in the text above.
- One commit per approach item, conventional messages (`chore(build): ...`, `ci: ...`, `docs: ...`, `chore(repo): ...`).

VERIFY BEFORE PUSHING (all must pass; paste the outputs in the PR body)
1. `npm run build` with NO emcc on PATH and NO `SKIP_WASM_BUILD` set → succeeds using committed public/wasm/*.
2. `npm run wasm:validate` → passes; then temporarily corrupt public/wasm/pixelocity_wasm.wasm (append a byte), rerun → fails; `git checkout public/wasm/` to restore.
3. `npx tsc --noEmit`, `npm run typecheck:scripts`, `npm run test:ci`, `npm run lint` → clean / 0 errors / warnings <= 125.
4. `npm run verify:toolchain-foundation`, `npm run verify:device-policy`, `npm run verify:wasm-invariants`, `npm run verify:bundle-size` (unchanged main-bundle number) → green.
5. `python3 tools/deploy/deploy.py --dry-run` and `npm run sync:shaders:dry` still run after any build.sh move (they must print a plan, not a traceback).
6. For each edited workflow: `node -e "require('js-yaml')"` is not guaranteed — instead validate with `python3 -c "import yaml,sys;[yaml.safe_load(open(f)) for f in sys.argv[1:]]" .github/workflows/*.yml`. Then confirm by reading: the wasm.yml `paths:` list contains every file the issue names; ci.yml has no emsdk/wasm:build step; action versions match the issue.
7. `grep -nE "craco|react-scripts|watchAll|Jest via" AGENTS.md README.md` → no hits that describe the current toolchain.
8. `git status` shows none of the forbidden paths modified.

Then push with `git push -u origin chore/1511-part3-hygiene` and open a PR titled "chore: build/CI/repo hygiene after the Vite move (#1511 Part 3, #1508 residue)". Body: what changed per item, the verification outputs above, any open question you had to decide (and how), and a note that it does not close #1511 (Parts 1-2 remain) but does supersede #1508. Reference both issues. Do not merge.
```

### E. Claude Code whole-stack task (mid-day)

```
Pipeline hygiene pass for ford442/image_video_effects (Pixelocity). The stack: a Vite 6 / React 19 / TypeScript 5.9 WebGPU client built with `npm run build` into build/, deployed by SFTP to DreamHost with tools/deploy/deploy.py and deploy_app_only.py (both now have --dry-run), shader assets synced to the VPS by tools/deploy/sync_shaders_to_storage.py (--dry-run), a Python FastAPI storage manager in storage_manager/ running on the VPS, and GitHub Actions CI. This is the first end-to-end pass since the toolchain moved from CRA/Jest to Vite/Vitest on 2026-10-18, and since a review found that the storage webhook HMAC secret (REACT_APP_WEBHOOK_SECRET) is inlined into the client bundle. The goal is a truthful report of what works, what is exposed, and what drifted. You are NOT here to implement fixes: the bug fixes run in another session on branch fix/1511-part1-bugs and the CI/repo cleanup is a separate issue. Deliverable 1 is a report; deliverable 2 is at most one tiny fix if a stage is broken by something trivial (a wrong path, a missing flag) — anything bigger is a finding.

BRANCH: `git fetch origin main && git checkout -b chore/pipeline-2026-10-24 origin/main`. Node >= 24, `npm ci` (rerun on sharp ECONNRESET).

STAGES — run every one, paste the real output (trim long lists with "…", never summarise), record pass/fail and wall time:
1. Toolchain truth. `node --version`, `npm --version`, `npx vite --version`, `npx vitest --version`, `npx tsc --version`, `npx eslint --version`. Compare with AGENTS.md "Services / commands" and README.md; list every command in those two files that no longer exists or errors (e.g. `npm test -- --watchAll=false --ci`). Do not fix the docs (that is the hygiene issue); report.
2. Static gates. `npx tsc --noEmit`, `npm run typecheck:scripts`, `npm run typecheck:tests`, `npm run lint` (count errors and warnings vs the 125 ratchet), `npm run verify:device-policy`, `npm run verify:uniforms`, `npm run verify:shader-definitions`, `npm run verify:generated-sync`.
3. Unit tests. `npm run test:ci -- --coverage` — files/tests passed/failed/skipped, duration, and the five slowest files from the reporter output.
4. Build. `SKIP_WASM_BUILD=1 npm run build` (no emcc here) → then `npm run verify:bundle-size` (main gzip KiB vs 325 budget), `npm run verify:catalog-counts`, `npm run verify:toolchain-foundation` (which gates pass), `npm run wasm:validate`, `npm run thumbs:test`, `npm run verify:thumbs-deferrals`.
5. Secret exposure (read-only). `grep -rn "REACT_APP_WEBHOOK_SECRET\|your-webhook-secret-here" src vite.config.ts` and `grep -rlo "your-webhook-secret-here" build/ ; grep -rlo "X-Hub-Signature-256" build/`. If `.env*` files exist locally, do NOT print their values; print only which keys they define. Report: is a webhook secret (or its default placeholder) present in the built JS? Which chunk? This is the exposure the fix branch is removing; the report is the evidence for rotating the secret.
6. Browser smoke on software WebGPU. `npm run test:engine2:smoke` (Playwright `swiftshader-smoke` project in both render threads; needs the production build from stage 4). If `page.goto: Page crashed` appears on `?renderer=wasm`, rerun that spec once alone and report both results — it is a known SwiftShader/host-load flake, not a regression, unless the TS renderer path also fails. Report which specs passed per render thread.
7. Deploy rehearsal (no writes). `python3 tools/deploy/deploy.py --dry-run` and `python3 tools/deploy/deploy_app_only.py --dry-run`: how many files would upload, total bytes, and whether the plan references `build/` paths that exist. Then `npm run sync:shaders:dry`: count to upload / orphaned definitions (compare with the 37-39 orphan count recorded in weekly_plan.md Backlog). No credentials are needed for dry runs; if a script asks for a password in dry-run mode, that is a finding.
8. Backend. `cd storage_manager && python3 -m pytest -q` (count). Then read-only health against the live VPS: `curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n"` for the API base URL in src/config/appConfig.ts (`/api/songs?type=image`, `/api/shaders` or whatever the config names; read appConfig.ts to get the real routes and host). Note the CORS allowlist in storage_manager/config.py vs the origins in appConfig.ts. If the VPS is unreachable from this environment (network policy), say so explicitly rather than reporting it down.
9. CI mirror. From the GitHub API or `gh` (if available): conclusion of the last 10 `main` runs of ci.yml and the last wasm.yml and thumbnail-coverage-status.yml scheduled runs; for any failure, the failing job + first error line. Compare the CI job list against what you ran locally and note gates you could not reproduce (GPU, emcc).

REPORT: write docs/reports/pipeline_report_2026-10-24.md (create the directory; do not move the existing root pipeline_report_2026-10-17.md — the hygiene issue owns that). Structure: header (base sha, environment, date), one section per stage with the pasted output and PASS/FAIL, then VERDICT: pipeline healthy / degraded / broken, a numbered findings list (each: severity, evidence line, which open issue owns it — #1511 Part 1 for the secret and app bugs, the hygiene issue for docs/root/CI drift, #1492 for thumbnails, #1508 if anything WASM-CI — or "new, needs an issue"), and the three commands a human should run on a real-GPU machine that this environment could not. Keep it under 400 lines; precision over prose.

Commit the report (and the one tiny fix, if any, as its own commit), push `chore/pipeline-2026-10-24`, open a PR titled "docs: pipeline report 2026-10-24 (first pass on the Vite toolchain)". If stage 5 found the secret in build/, say so in the PR body's first line.
```

## Suggested timeline

- **T+0 (kickoff, 15 min):** start the swarm (A) on `fix/1511-part1-bugs`; file issue B as drafted.
- **T+20 min → T+2 h (expansion):** run C1 (Gemini Pro, with the repo), C2 (gpt-oss-120b), C3 (Grok) against the issue; merge their output into the issue body; answer the five open questions inline. Then hand the expanded issue to D on `chore/1511-part3-hygiene`. Check `.swarm-state.md` once: items 1-3 (secret out, proxy, bug 7) should be committed by now.
- **T+2 h → T+4 h (mid-day):** run E on `chore/pipeline-2026-10-24`; read its stage 5 (secret in `build/`) and stage 6 (SwiftShader smoke) first. Meanwhile the swarm should be through items 4-7 (probe leak, double click, tone-mapping report, upload hook).
- **T+4 h → end of day:** swarm items 8-10 (BGL by format, MIDI, AutoDJ) are the risky ones — expect one `needs Noah` entry if `verify:device-policy` objects to the BGL change. Review the three PRs in order: A (bugs), D (hygiene), E (report). After A merges: **rotate the webhook secret and deploy `storage_manager` with `WEBHOOK_SECRET` + `WEBHOOK_RECEIVER_URL`** — nothing else on the list matters until that is done.

## Open questions

- **Branch protection:** are `test`, `wgsl-precommit-gate`, `catalog-consistency-audit`, `lint` required checks on `main` now (#1449 §1b)? Unverifiable from here; the `f3798000` direct push on 10-19 suggests not.
- **Webhook receiver:** where does `${STORAGE_VPS_HOST}/webhook/image-effects` actually run, and does it live in a repo this routine can see? `storage_manager/` has no HMAC verification, so the swarm's proxy assumes the receiver is a separate service on the same host. If the receiver is in `storage_manager/legacy/` or elsewhere, the proxy should be replaced by a session/token check there instead.
- **#1434:** closed, and `hydrateDurations` has left `useContentManifest.ts` — but no PR references the issue. Was the fix part of a batch merge, or did the hook simply get rewritten? Not important for today, recorded for the Done ledger.
- **PR #1505** has no check runs on its head — did CI not trigger (base `401bccbd`), or were the runs deleted? It also edits `scripts/lib/thumbnailHarness.mjs`; today's tracks avoid that file, but it will conflict with any later thumbnail work.
- **Node on this VM is 22**, `engines.node` is `>=24`: no local build or test was possible this run. The dispatch commands follow `package.json`; if any of them differ on your machine, the AGENTS.md rewrite in issue B is where the truth should land.
- **This routine's PROJECT CONTEXT** still says CRA, TypeScript 4.9 and `npm test (Jest)`; please update it to Vite 6 / Vitest 3 (`npm run test:ci`) / TS 5.9 / Node ≥ 24 so next week's prompts stop inheriting the drift.
