# image_video_effects — 2026-10-17 dispatch

**Status:** `main` @ `8fc34b8` is **red** (`wgsl-precommit-gate` + `test`, naga knownFailures ratchet); the two-line fix is commit `440d072` on this routine branch. Last week's #1393 shipped (PR #1438). Noah's 10-14 audit (#1449/#1450/#1451) is the live backlog and #1449 says "do this before any new feature work". Bundle at 324.61/325 KiB; 39 thumbnail deferrals expire 10-26.

## Mode declaration

**Fix First.** `main` has been red on three different ratchet gates in six days (8 of the last 14 runs failed), the bundle budget has 0.4 KiB left, a thumbnail cliff lands in nine days, and Noah's own #1449 already ranks "fix red main + the OOM-retry pool bug" above all feature work — so today is #1449 §1–§3, with the CI fix pre-committed here so the swarm starts from green.

## Context from prior sessions

- **10-10 tracks:** A (#1393 project files) **shipped** — PR #1438 merged 10-11: `src/services/project/` (types/validate/migrate/export/import + tests), `src/contracts/project_file.json`, `useProjectFile.ts`, `ProjectFilePanel.tsx`; swarm closeout 156 suites / 1282 tests. B (Copilot #1404) was expanded and **filed as #1434**, no PR since. C (`tools/deploy/deploy.py --dry-run`) **did not land — fourth week**; both deploy scripts still parse only `--force`/`--fresh`.
- **Noah's 10-10/10-11 merge train** cleared the 10-07 audit set: #1383 (thumbs rescue, deferral ratchet 234 → 41), #1419 (definition schema), #1415 (device-loss recovery), #1418 + #1441 (Graph Lab + sim-ring graphs), #1421–#1425 (#1395 slices), #1435 (WASM ready gate + `wasm:compdb`), #1442 (Display P3), #1440 (compile fix). 10-17: #1459 sidebar groups/filter (#1407). Only #1434, #1401 (`future`), #1408 (verification pass) and the 10-10 pair #1430/#1431 survive from that set.
- **Noah's 2026-10-14 audit** opened #1449 (Foundation first: red main, OOM-retry pool bug, unbounded pipeline cache, lazy WASM, facade split, tree moves), #1450 (CI dedupe → Vite/Vitest/ESLint 9, multi-day) and #1451 (Graph Lab v2, multi-day, GPU-visual). Open PRs: **#1465** (Noah, #1431 canvas capabilities, `unstable` — WASM artifacts need an emsdk 6.0.12 rebuild) and #1466 (opus/batch-02 shader ideas).
- **`main` red timeline:** 10-13→10-16 pasted prelude header (#1448); 10-17 07:09 prelude-migration ratchet (#1461 merge, fixed by #1463's migration commit); 10-17 08:25→ naga ratchet: PR #1462 rewrote `volumetric-depth-zoom.wgsl`, it now validates, and `src/contracts/wgsl_validation.json` still lists it (ratchet 31). Reproduced locally; fixed in `440d072` (1411 valid / 30 known / 0 new; gate tests 17/17). Every one of the three was a shader-batch merge that never ran green — the gates are not required checks (unverifiable from here, but the merge timestamps say so).
- **Cliffs:** main bundle 324.61 / 325.00 KiB gzip (`verify:bundle-size`, run 2818). Thumbnails: 43 deferrals, 39 `gpu-capture-pending` expire 2026-10-26; `verify:thumbs-deferrals` warns from 10-19, exits 1 from 10-27 inside the hard `verify:toolchain-foundation` step.
- **Gaps (real signal):** no chat-history tools this run (`recent_chats` / `conversation_search` unavailable), no `memory/` files (gitignored), `node_modules` absent in the VM so Jest was not run here; the naga fix was verified with the gate's own install-free scripts. Branch-protection settings not readable. Nothing below names a file or line I did not open this session.

## weekly_plan.md changes

- **Today's focus:** new 2026-10-17 Fix First block (reconciliation, why-Fix-First with run numbers, tree-verified line refs for every #1449 claim, track boundaries); the 10-10 block archived in `<details>` with its outcome.
- **Ideas:** 2026-10-17 note; **#1449 marked `[in progress — 2026-10-17]`**; added #1450, #1451, #1430, #1431 (→ PR #1465), #1434, and the 10-26 thumbnail wave (today's issue B); #1393 → DONE (PR #1438); #1394/#1395/#1396/#1397/#1398/#1399 → DONE with their PR numbers; #1407 noted DONE inside the usability line; #1404 → "filed as #1434".
- **Backlog:** 9 NEW 2026-10-17 items (red main + fix commit; three reds in six days / required checks; bundle 0.4 KiB; thumbnail cliff #3 with exact counts; deploy dry-run fourth week; PR #1465 artifact rebuild + the files the swarm must avoid; #1434 no PR; board hygiene; tooling gaps). "19 open PRs" → RESOLVED; "40 after #1383" → superseded; deploy item annotated.
- **Done:** 2026-10-17 reconciliation entry (what shipped, what was filed, what was carried, Noah's merge train) + the CI fix commit.
- **Last run:** 10-10 outcome filled in; 2026-10-17 entry appended.
- **Also on this branch:** `src/contracts/wgsl_validation.json` (commit `440d072`) — the naga ratchet fix, as its own commit so it can be cherry-picked if the plan PR waits.

## Today's focus

**#1449 — "Foundation first: fix red main (pasted prelude), renderer OOM-retry pool bug, bounded pipeline cache, lazy-load WASM, split renderer facade"** (Noah, 2026-10-14; labels `bug`, `ci`, `renderer`, `infrastructure`). Scope today: **§1** CI green + the ratchet gates as required checks (documented, since the swarm cannot change branch protection), **§2** bugs 1–5, **§3** lazy-load `WASMRenderer`; **§4** facade split only if §1–§3 are green with time left; **§5** tree moves **out** (they collide with every open branch and with #1465).

Rationale beyond "it's red": the cause of each red was a ratchet gate doing its job on a merge that skipped it, so §1's real deliverable is the required-check list plus a doc line, not another ratchet. §2 bug 1 is a real resource bug on a path (#1415 device-loss recovery) that just merged. §3 is the only honest way out of the 0.4 KiB bundle headroom. All of it is headless-verifiable: Jest with mocked `GPUDevice`, `tsc`, `SKIP_WASM_BUILD=1 npm run build`, `verify:bundle-size`, `verify:toolchain-foundation`.

## Dispatch

### A. Swarm task — Claude Code, long-running

```
You are working in ford442/image_video_effects (Pixelocity): a React 19 + TypeScript WebGPU shader playground. The TypeScript renderer under src/renderer/ is the production path (it runs in a render worker by default; `?renderer=main` keeps it on the page); the C++/WASM renderer is R&D-frozen (`?renderer=wasm` only). This is a long-running session: work in small verified iterations, write state to .swarm-state.md at every boundary, and expect to be paused and resumed.

OBJECTIVE
Implement GitHub issue #1449 sections 1, 2 and 3 ("Foundation first"), with section 4 as a stretch goal. Read the issue first: `gh issue view 1449` or https://github.com/ford442/image_video_effects/issues/1449. The why: main has been red on three different ratchet gates in six days, the renderer reuses destroyed GPU buffers after an OOM retry, pipelines are cached forever keyed by their full WGSL source, and the frozen WASM renderer is statically imported into a main bundle that has 0.4 KiB of budget left.

BRANCH AND BASELINE
- Branch from origin/main: `git fetch origin main && git checkout -b fix/1449-foundation-first origin/main`.
- Step 0: `npm ci` (if `sharp` postinstall fails with ECONNRESET, rerun). Then run `node scripts/verify-naga-wasm.mjs --all`. If it fails on `volumetric-depth-zoom`, that fix is already on branch claude/exciting-faraday-abr9u2 as commit 440d072 (src/contracts/wgsl_validation.json: remove the id, ratchet 31 -> 30); cherry-pick it. Do not touch any other contract file.
- Record the baseline in .swarm-state.md before changing code: `npx tsc --noEmit`, `npm test -- --watchAll=false --ci` (suite/test counts), `SKIP_WASM_BUILD=1 npm run build`, and the main-bundle number from `npm run verify:bundle-size` (it prints "main: X KiB gzip / 325.00 KiB budget").

ALLOWED TO EDIT
- src/renderer/** EXCEPT src/renderer/webgpu/device.ts and src/renderer/webgpu/device.test.ts (Noah's open PR #1465 edits both; touching them creates a conflict he has to resolve).
- src/components/LiveStudioTab.tsx (only to remove its static WASMRenderer import).
- src/gpuChores/GpuChoresHost.ts only if you reach section 4.
- docs/APP_STRUCTURE.md, docs/RENDER_WORKER.md (doc lines only), .swarm-state.md.
- New test files next to the code you change.

DO NOT TOUCH (read if you need to, never edit)
public/shaders/**, shader_definitions/**, public/shader-lists/**, wasm_renderer/**, public/wasm/**, src/wasm/**, src/contracts/** (except the cherry-pick above), scripts/**, .github/**, package.json, package-lock.json, craco.config.js, storage_manager/**, public/thumbnails/**, reports/**, tools/**, weekly_plan.md, weekly_dispatch.md. If a fix seems to need one of these, write the proposed change into .swarm-state.md under "needs Noah" and move on.

WORK ITEMS, IN ORDER
1. CI green and kept green (#1449 section 1).
   a. Confirm `npm run verify:toolchain-foundation` passes locally after the cherry-pick (it needs public/shader-manifest-unified.json; run `npm run build:manifest` first if verify:catalog-counts complains).
   b. The source of the three reds is that shader-batch PRs merge without the gates passing. You cannot change branch protection. Instead add a short section to docs/APP_STRUCTURE.md (or the nearest CI doc you find under docs/) titled "Required status checks" listing the job names that must be required on main: `wgsl-precommit-gate`, `test`, `catalog-consistency-audit`, `lint`, and `wasm` only via wasm.yml path filter. Explain in two sentences what each ratchet gate (prelude migration, naga knownFailures, dead sliders, extraBuffer) does when a listed shader starts passing, so the next person who sees "lower ratchet to N" knows it is a two-line contract edit. Put "Noah: enable these in branch protection" in .swarm-state.md.
2. Renderer correctness (#1449 section 2), each with a Jest test that fails before and passes after:
   a. src/renderer/webgpu/resources.ts: destroyBuffers() (around line 373) destroys uniformBuf/extraBuf/plasmaBuf but leaves the fields set, and ensureSamplersAndBuffers() (around line 289) only creates when a field is empty. Add a resetForDevice()/clear path that nulls the three buffers AND the samplers, and make the init retry in src/renderer/WebGPURenderer.ts (the `resourcesResult === 'lost' && attempt === 0` branch around line 271) use it so a fresh device gets fresh buffers and samplers. Test: mock GPUDevice, force the first attempt to report 'lost', assert createBuffer/createSampler are called again on the second device and no destroyed buffer object is reused.
   b. WebGPURenderer.ts around line 448: when the 1024 working-size restore fails WITHOUT device loss, return 'oom', not 'lost'. Test both branches.
   c. Pipeline cache: today only warm-up pipelines go through the 24-entry LRU in src/renderer/webgpu/shaderWarmup.ts; pipelines compiled on user selection in src/renderer/ShaderCompilation.ts (the cacheKey = pipelineCacheKey(wgsl, colorFormat) block around line 246) are stored in Maps keyed by id and never evicted, and the key is the full WGSL source (src/renderer/wgslFormatRewrite.ts pipelineCacheKey). Make one bounded LRU for all non-bound pipelines, keyed by a hash of (wgsl, colorFormat) — a small FNV-1a in src/renderer/ is fine, no new dependency. The currently bound slot pipelines must never be evicted. Test: compile 50 distinct shaders through the public API, assert the cache holds <= N (pick N = 32 unless you find a reason in the code) and the active ones survive. Keep the warm-up path working.
   d. src/renderer/webgpu/formatPolicy.ts around line 156 reports hasFloat32Blendable from the adapter while the device never requests the feature. Report the device feature (do not start requesting new features). Test with a mock where adapter has it and device does not.
   e. WebGPURenderer.ts around line 286 hard-codes `thread: 'main'`. Report the real thread (see how docs/RENDER_WORKER.md and the worker entry decide it). If the thread is only knowable from the host, plumb it as a constructor/init option with 'main' as default and set it from the worker entry.
3. Lazy-load the WASM renderer (#1449 section 3). WASMRenderer is statically imported by src/renderer/RendererManager.ts, backendLifecycle.ts, rendererDiagnostics.ts, rendererTypes.ts, performanceStatus.ts and src/components/LiveStudioTab.tsx. Move WASMDiagnostics and shared types to rendererTypes.ts as type-only exports, replace instanceof checks with a type guard on a `backend` discriminant, and `await import('./WASMRenderer')` only inside the `?renderer=wasm` branch. Then: `SKIP_WASM_BUILD=1 npm run build && npm run verify:bundle-size` and record the before/after main-bundle KiB in .swarm-state.md. The frozen path must still work: `npm run test:engine2:smoke` if Playwright + SwiftShader are available in your environment (see docs/RENDER_WORKER.md for the flags), otherwise say so explicitly. `npm run verify:dependency-boundaries` must stay green.
4. STRETCH ONLY: split WebGPURenderer.ts (1,339 lines) into webgpu/initSequence.ts (probe -> pool -> working-size ladder; where 2a/2b live), webgpu/canvasColor.ts and webgpu/capture.ts, as the issue describes. Pure moves, no behaviour change, facade < 700 lines. Stop before this if any of 1-3 is not green.

ITERATION LOOP (every item)
- `npx tsc --noEmit`
- `npm test -- --watchAll=false --ci` (never `npx react-scripts test` directly — it skips the craco moduleNameMapper and 11 WASM-bridge suites fail on bridge/api.js)
- `npx eslint src --ext .ts,.tsx` (non-gating in CI, but no NEW errors in files you touched)
- `SKIP_WASM_BUILD=1 npm run build` then `npm run verify:bundle-size` and `npm run verify:dependency-boundaries`
- After section 3: `npm run verify:toolchain-foundation`
- Fix any WebGPU/TypeScript error you introduced before moving to the next item. If a pre-existing failure appears, record it in .swarm-state.md with the exact output and keep going.
- Commit after each green item with a message that names the issue section, e.g. "fix(renderer): reset pool buffers/samplers on OOM retry (#1449 2a)".

SAVE STATE
At every iteration boundary overwrite .swarm-state.md with: iteration number; baseline numbers; done (item ids + commit shas); in_progress; blocked / needs Noah; verification_last_run (exact counts from the commands above, pasted, never copied from a previous note); bundle before/after; files_touched. If you are interrupted, the next session resumes from this file and must not redo green items.

FINISH
Push the branch and open a PR titled "Foundation first: green main, OOM-retry pool reset, bounded pipeline cache, lazy WASM renderer (#1449 §1–§3)" with the before/after numbers, the required-checks list for Noah, and "Closes nothing — #1449 §4/§5 remain" in the body. Mention that commit 440d072 (naga ratchet) is shared with the routine branch so the merge is a no-op if that lands first.
```

### B. GitHub issue — draft now (Claude implementation prep)

```
Title: Thumbnails: dispose the 2026-10-26 deferral wave and move expiry enforcement off the push gate

Context / motivation
The thumbnail pipeline (part of the "maintaining the rendering engine" focus — healthy thumbnails are how 1,391 shaders stay discoverable) has a wall-clock time bomb that has now gone off, or nearly, three times. `scripts/verify-thumbs-deferrals.js` runs inside `npm run verify:toolchain-foundation`, which is a hard step of the `test` job in `.github/workflows/ci.yml`. It exits 1 when any entry in `reports/thumbnail_deferrals.json` is past its `expires` date. On 2026-09-26 the 09-30 cliff was defused by hand (renewed 234, removed 835). PR #1383 (merged 2026-10-10) brought the file down to 43 entries, but **39 of them are `gpu-capture-pending` with `expires: 2026-10-26`**. The script warns from 2026-10-19 and fails every `main` and PR run from 2026-10-27 — on commits that did not touch a thumbnail. Ratchet is 41 against a target of 200, so the ratchet is not the problem; the calendar is. (Measured 2026-10-17: `node scripts/verify-thumbs-deferrals.js` → "43 (gpu-capture-pending 41, ratchet 41, target 200)"; 39 × 2026-10-26, 1 × 2026-11-10, 1 × 2026-11-15, 2 × reason `other`.)

Proposed approach (first pass — Noah will expand)
1. Dispose the 39 honestly, the same way as 09-26. Per the #1383 PR body they are real SwiftShader capture failures (black / flat / timeout). For each: either re-run the SwiftShader capture once with the current renderer (`scripts/generate-shader-thumbnails.js` / `scripts/run-thumbnail-waves.sh` — the 10-10 rescue changed four sims, so some may pass now) and commit the PNG + manifest entry, or remove the entry with `scripts/defer-thumbnail.js` so the shader shows as Missing in the report-only coverage job instead of being hidden behind a deferral. No blanket renewal: a renewal needs a `failure_note` and a shorter window.
2. Move the wall-clock check out of the push gate. Keep `verify-thumbs-deferrals.js` schema/ratchet checks in `verify:toolchain-foundation` (they are deterministic per commit) but make the expiry check a separate mode (`--expiry`) that runs only from the scheduled `.github/workflows/thumbnail-coverage-status.yml` job. When entries are within 7 days of expiry or expired, that job opens or updates a single sticky issue listing the ids and the disposition command, instead of failing unrelated PRs. The push-gate mode must still fail on an entry whose `expires` is already in the past at the time it is ADDED (diff against the base ref), so nobody can commit a pre-expired deferral.
3. Lower the ratchet to the post-disposition count and update `docs/THUMBNAIL_PIPELINE.md` so it describes the two modes and the sticky issue.

Acceptance criteria (rough)
- [ ] `reports/thumbnail_deferrals.json` has no entry expiring before 2026-11-10; every surviving `gpu-capture-pending` entry carries a `failure_note` and `renewals` count.
- [ ] `THUMBS_DEFERRALS_NOW=2026-10-27 node scripts/verify-thumbs-deferrals.js` exits 0 (push-gate mode) on the resulting tree; the same with `--expiry` reports the next upcoming expiry and exits 0 unless something is already expired.
- [ ] A new entry with `expires` in the past fails push-gate mode when it is introduced (test in `scripts/verify-thumbs-deferrals.test.js`).
- [ ] `thumbnail-coverage-status.yml` runs `--expiry` on its schedule and opens/updates one sticky issue (marker comment, like the existing `thumbnail-coverage-sticky` pattern in ci.yml) listing expiring ids.
- [ ] `ratchet` in the deferrals ratchet file equals the new `gpu-capture-pending` count; `docs/THUMBNAIL_PIPELINE.md` matches; `npm run verify:toolchain-foundation` green.
- [ ] Coverage report (`reports/thumbnail_coverage.md`) shows the removed ids as Missing, not deferred; healthy count does not go down.

Open questions for Noah
- Re-capture or remove? Re-capturing 39 on SwiftShader is ~2 fps × 39; is there a GPU box free this week, or is "Missing" the honest state until the capture farm exists?
- Should the sticky issue be opened by the scheduled job (needs `issues: write`), or is a workflow summary + Discord/notification enough?
- Is `--expiry` as a flag the right split, or should the expiry check live in `scripts/thumbnail-coverage-status.js` instead of `verify-thumbs-deferrals.js`?
- The two `other`-reason entries (11-11, 11-14): what are they, and should `other` be allowed at all now that the reason enum exists?
```

### C. Three chat-model prompts for the issue

**Gemini Pro** (attach or paste the repo; it reads code):

```
You have the ford442/image_video_effects repository (React 19 + TypeScript, WebGPU compute shaders, Node scripts under scripts/, GitHub Actions under .github/workflows/). Below is a draft GitHub issue. Produce a complete implementation plan from the actual code, not from the issue's assumptions.

Specifically:
1. Read scripts/verify-thumbs-deferrals.js, scripts/defer-thumbnail.js, scripts/check-thumbnail-coverage.js, scripts/thumbnail-coverage-status.js, their *.test.js files, reports/thumbnail_deferrals.json, the ratchet file they load, package.json's verify:toolchain-foundation script, .github/workflows/ci.yml (the test job and the thumbnail-coverage job with its sticky-comment pattern) and .github/workflows/thumbnail-coverage-status.yml and generate-thumbnails.yml. List every file and function the issue touches, with line references.
2. Identify what the issue missed: other callers of the deferral file, any CI job that would still fail on an expired entry after the change, what the ratchet file is actually called and who updates it, and whether defer-thumbnail.js already has a remove/renew mode or needs one.
3. Design the split between push-gate checks (deterministic per commit) and scheduled checks (wall clock). Show the exact CLI surface and exit codes, and how the "newly added, already expired" rule is computed against a base ref in CI.
4. Specify the sticky issue mechanism reusing the existing pattern in ci.yml, including required workflow permissions.
5. Write the test list for scripts/verify-thumbs-deferrals.test.js with the fixture shapes.
6. Give the disposition procedure for the 39 entries expiring 2026-10-26 as a sequence of commands, and say what the coverage report will show afterwards.
Flag anything in the issue that contradicts the code. Do not invent file paths; quote the ones you opened.

--- ISSUE ---
<paste section B here>
```

**gpt-oss-120b** (no web, no repo — everything it needs is in the prompt):

```
Context (self-contained, no external access needed): a web app's CI has a script that reads a JSON file of "thumbnail deferrals". Each entry is {id, reason, deferred_at, expires, renewals, failure_note?}. The script runs on every push and PR as part of a hard CI step and exits 1 if any entry's `expires` date is in the past, if the JSON is invalid, or if the count of reason="gpu-capture-pending" entries exceeds a "ratchet" number stored in a separate file (the ratchet may only go down). It also warns when an entry expires within 7 days. Today there are 43 entries; 39 are gpu-capture-pending expiring 2026-10-26, so from 2026-10-27 every CI run on every branch fails, including commits that never touched thumbnails. This already happened once (2026-09-30) and was fixed by hand-editing the file. A separate scheduled GitHub Actions workflow (cron) already exists that computes thumbnail coverage and posts a sticky comment/summary; it can be given permission to open issues.

The proposed approach: (1) dispose of the 39 entries now — either re-capture the thumbnail (slow software GPU, ~2 fps) or delete the entry so the shader is listed as Missing in a report; no blanket renewal. (2) Split the script into a push-gate mode (schema + ratchet + "a newly added entry may not already be expired", computed by diffing against the base branch) and a scheduled mode (--expiry) that runs from the cron workflow and opens/updates one sticky issue listing expiring ids instead of failing pushes. (3) Lower the ratchet to the new count and document it.

Tasks:
1. Stress-test this approach. Where does it fail or regress? Consider: a PR that is open across the expiry date, a fork PR without issue permissions, the base-ref diff on a rebased branch, clock skew, the ratchet interacting with removals, and what "honest" means if a shader simply never gets a thumbnail.
2. Propose two alternatives: (A) keep the push gate but make expiry a soft warning that becomes hard only N days after expiry, and (B) drop expiry entirely and rely only on the ratchet plus a coverage-percentage floor. Give one more of your own if you have a better one.
3. Argue for the best option with a short decision matrix: false-red risk on unrelated PRs, honesty of the coverage number, implementation size (lines/files), and how it fails when nobody looks at the scheduled job for a month.
4. Write the exact exit-code and CLI contract for the recommended option, plus the 6–8 unit tests that would pin it.
Keep it concrete; no general CI advice.
```

**Grok** (ecosystem awareness):

```
I maintain a React 19 + TypeScript + WebGPU (WGSL compute) web app with ~1,400 shaders, CI on GitHub Actions, thumbnails captured headlessly with Playwright's Chromium on SwiftShader (--enable-unsafe-webgpu --use-webgpu-adapter=swiftshader). We track shaders whose thumbnail capture failed in a JSON "deferral" file with expiry dates, and a CI script fails the build when an entry expires. I am about to (1) move that wall-clock expiry check from the per-push gate to a scheduled workflow that opens a sticky GitHub issue, and (2) dispose of 39 entries that failed on SwiftShader (black/flat/timeout).

What is current as of now that would change this plan?
- GitHub Actions: any changes to scheduled-workflow reliability, `issues: write` from scheduled runs, sticky-issue/sticky-comment actions people actually use, and whether GPU-enabled hosted runners (or cheap GPU runner providers) are now practical for a solo maintainer — that would make "re-capture on a GPU" the honest fix instead of "mark Missing".
- Headless WebGPU: has Chromium's SwiftShader WebGPU path or Dawn's null/software backends improved for compute-shader screenshots, or is there a better headless capture route (e.g. wgpu-native / Deno / Node WebGPU with a software adapter) that could capture those 39 reliably?
- Any well-known patterns for "ratchet + expiry" technical-debt files in CI that avoid the time-bomb problem (I want prior art, not a tutorial).
Cite sources with dates. Flag anything in my plan that is already outdated.
```

### D. Claude implementation handoff

```
You are implementing a well-specified GitHub issue in ford442/image_video_effects (React 19 + TypeScript, Node scripts under scripts/, GitHub Actions under .github/workflows/). The issue, expanded and verified, is below. Implement exactly that scope on its own branch; a separate long-running session is working in src/renderer/** today, so do not touch src/ at all.

Branch: `git fetch origin main && git checkout -b fix/thumbs-expiry-off-push-gate origin/main`. Before you start, run `node scripts/verify-naga-wasm.mjs --all`; if it fails on `volumetric-depth-zoom`, cherry-pick commit 440d072 from branch claude/exciting-faraday-abr9u2 (it is a two-line contract fix that unbreaks main) and nothing else.

Files you may edit: scripts/verify-thumbs-deferrals.js and its test, scripts/defer-thumbnail.js and its test, scripts/thumbnail-coverage-status.js, reports/thumbnail_deferrals.json, the deferral ratchet file those scripts load, .github/workflows/thumbnail-coverage-status.yml, .github/workflows/ci.yml only on the lines that invoke the thumbnail scripts, docs/THUMBNAIL_PIPELINE.md, package.json only to add/adjust the verify:thumbs-* script lines. Nothing under src/, public/shaders/, shader_definitions/, wasm_renderer/, storage_manager/, tools/.

Verify, in this order, and paste the outputs in the PR body:
1. `npm ci` (rerun once if the sharp postinstall resets)
2. `node --test scripts/verify-thumbs-deferrals.test.js scripts/defer-thumbnail.test.js` (or the repo's documented way to run those tests — check package.json)
3. `node scripts/verify-thumbs-deferrals.js` and `THUMBS_DEFERRALS_NOW=2026-10-27 node scripts/verify-thumbs-deferrals.js` — both exit 0 in push-gate mode
4. the new scheduled mode with the same two dates, showing the expiry report
5. `npm run build:manifest && npm run verify:toolchain-foundation`
6. `npm test -- --watchAll=false --ci` (never `npx react-scripts test` directly)
7. `npm run build` with SKIP_WASM_BUILD=1 set
8. `npx playwright test` only if the issue's acceptance list asks for a browser check; this task should not need it.

Commit in small steps (disposition data, script split, workflow, docs). Push with `git push -u origin fix/thumbs-expiry-off-push-gate` and open a non-draft PR titled "Thumbnails: dispose the 10-26 deferral wave, move expiry enforcement to the scheduled job" that lists each acceptance criterion with how it was verified, the new ratchet value, and the open questions you had to decide yourself.

{{EXPANDED_ISSUE}}
```

### E. Claude Code whole-stack task (mid-day)

```
Whole-stack hygiene pass for ford442/image_video_effects. The stack: a Create React App + React 19 + TypeScript WebGPU client, built with `npm run build` and deployed to DreamHost over SFTP by tools/deploy/deploy.py (full) and tools/deploy/deploy_app_only.py (app-only), talking to a Python FastAPI "storage manager" (storage_manager/) that serves shader/media manifests. CI is GitHub Actions (.github/workflows/ci.yml + wasm.yml). Two other sessions are working today in src/renderer/** and in scripts/*thumb*; do not touch either.

Deliverable 1 (the point of this task — it has been planned four weeks running and never landed): add a real `--dry-run` flag to BOTH tools/deploy/deploy.py and tools/deploy/deploy_app_only.py. Today each parses only `--force` and `--fresh` from sys.argv (deploy.py around lines 305-306, deploy_app_only.py around 137-138). Requirements:
- Use argparse (keep `--force` / `--fresh` behaviour identical).
- `--dry-run` must open NO network connection (no SFTP, no credential prompt; read tools/deploy/deploy_credentials.py to see how credentials are resolved and make sure the dry run never calls it, or calls it in a mode that does not prompt).
- It computes the same upload plan the real run would (walk build/ against the committed .deploy_manifest.json, honour ALWAYS_UPLOAD) and prints: files to upload (path, size, reason: new / hash-changed / always), files to delete if `--fresh`, totals, and the destination root — without changing anything on disk or remote and without rewriting .deploy_manifest.json.
- Exit 0 on a computable plan, non-zero with a clear message if build/ is missing.
- Add a unit test under tools/deploy/ (pytest, no network) that builds a tiny fake build/ + manifest in a temp dir and asserts the plan.
- Document the flag in the deploy section of README.md or docs/ wherever deploy is described (search for "deploy.py").

Deliverable 2: run the pipeline end to end and record real output (not summaries) in a file pipeline_report_2026-10-17.md at the repo root, one section per stage:
1. INSTALL: `npm ci` (rerun once on ECONNRESET from sharp). Node and npm versions.
2. TYPECHECK + TEST: `npx tsc --noEmit`; `npm test -- --watchAll=false --ci` (never npx react-scripts test directly). Paste the suite/test totals line.
3. BUILD: `SKIP_WASM_BUILD=1 npm run build`; then `npm run verify:bundle-size` (paste the "main: X KiB gzip / 325.00 KiB budget" line — it was 324.61 on 2026-10-17; say whether it moved) and `npm run verify:dependency-boundaries`.
4. SHADER LISTS: `node scripts/generate_shader_lists.js` and `npm run build:manifest`; `git status --short` must be empty afterwards (generated files are committed). Then `npm run verify:toolchain-foundation`; if `verify:naga-wasm:all` fails on volumetric-depth-zoom, note that commit 440d072 on claude/exciting-faraday-abr9u2 fixes it and do not edit the contract yourself.
5. DEPLOY DRY-RUN: `python3 tools/deploy/deploy.py --dry-run` and `python3 tools/deploy/deploy_app_only.py --dry-run` against the build you just made. Paste the plan summaries. Confirm from the code that no socket was opened.
6. BACKEND: from the repo root, `python -m pytest storage_manager/tests/ -q`. Then `curl -sS -m 10 https://ford442-storage-manager.hf.space/api/health` (and the `/api/songs?type=image` status code only) and record the HTTP status; if the host is unreachable from your network, say so — do not retry in a loop.
7. DEPENDENCY AUDIT: `npm audit --omit=dev` summary line only, and `pip list --outdated` for storage_manager/requirements if present.
8. VERDICT: one paragraph: pipeline healthy / issues found, each issue with the exact command and output that shows it. No fixes outside Deliverable 1 — file findings in the report.

Branch `chore/deploy-dry-run-and-pipeline-2026-10-17` from origin/main, commit Deliverable 1 separately from the report, push with `git push -u origin <branch>`, open a non-draft PR with the report's VERDICT paragraph as the description.
```

## Suggested timeline

- **T+0 (kickoff, ~15 min):** merge or cherry-pick `440d072` so `main` is green (it is on PR for this routine branch); start the swarm (A) in its own branch; paste the issue (B) into GitHub.
- **T+20 min → T+2 h (expansion):** run C.1 (Gemini) and C.2 (gpt-oss) in parallel; C.3 (Grok) only if Gemini's plan hinges on GPU runners or capture tooling. Fold the answers into the issue; resolve the four open questions (re-capture vs Missing is the one that changes the work).
- **T+2 h:** hand off D with the expanded issue; it works in `scripts/` + `reports/` + the scheduled workflow, nowhere near A.
- **T+3 h (mid-day):** start E; it is `tools/deploy/` + a report, independent of A and D. Its SHADER LISTS stage doubles as a second check that `main` is green after A's first push.
- **Check-ins on A:** read `.swarm-state.md` at ~T+1.5 h (expect 1 + 2a/2b green), ~T+4 h (2c/2d/2e), ~T+6 h (3 with bundle numbers). Decide §4 at T+6 h.
- **Before 10-19:** D's disposition must be merged, or at least the push-gate split, or CI starts warning on every run; before 10-27 it fails.

## Open questions

- **Branch protection:** are `wgsl-precommit-gate` and `test` required checks on `main`? The merge timestamps (shader PRs merged 2–3 min after opening, runs failing after merge) say no. The swarm documents the list; only Noah can flip it.
- **#1393 close-out:** PR #1438 merged but I could not confirm the issue was closed by it (the API did not return the link). Same for #1407 (PR #1459).
- **#1408 (old-build regressions):** nothing in the tree proves or disproves the four items; it still needs the verification pass it asks for, on a real GPU browser.
- **PR #1465:** needs an emsdk 6.0.12 WASM artifact rebuild before merge — Noah's box only. Until it merges, nothing should touch `src/renderer/webgpu/device.ts`, `canvas_configure.json` or `wasm_renderer/`.
- **#1450 vs the 08-07 "stay CRA/CRACO" decision:** #1450 reverses it. Not scheduled; Noah should say which stands before anyone picks it up.
- **Jest baseline:** not run in this VM (no `node_modules`, node v22). Last measured: 156 suites / 1282 tests (10-10 swarm closeout); CI run 2818 "Run unit tests" passed.
