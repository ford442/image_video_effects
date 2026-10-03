# image_video_effects — 2026-10-03 dispatch

**Status:** Last week's Fix First (the #1312-A thumbnail-deferral cliff) shipped on `main` on 09-26. The Copilot track (#1307) shipped too. CI is green at `e42ac52`, and a clean install runs Jest at **107 suites / 764 passed / 0 failed**. Today's focus is **#1311 WP-A, the TypeScript renderer lifecycle bugs**. Next cliff: **2026-10-26**, when the 234 renewed deferrals expire.

## Mode declaration

**User Idea.** The foundation is intact: CI is green and every gate passes, so Fix First does not apply. Noah's 2026-09-23 audit is still the live Ideas source. Its #1311 says to land WP-A "before the next large engine addition", and WP-A is the only open foundation package that needs no GPU, no emcc and no decision from Noah.

## Context from prior sessions

- **#1312-A shipped as six commits on 09-26** (`a44947c` → `f8ba344`): a `defer-thumbnail.js` writer, a 7-day warning, boundary tests, and the disposition (renew 234, remove 835, ratchet 1069→234). I re-ran the verifier today: exit 0. All 234 renewals carry `expires: 2026-10-26`.
- **The rest of the week also landed:** #1307 history-ring fix (`621479d`), #1300 audit close-out (`ee855e9`), #1308 `@group(1)` sim ring + DLA (`5e245f4`), the slot-1+ slider fix (`edd0f25`), and **#1080 decided Stay B / frozen R&D** (`8ae3847`), which spawned #1329, #1330 and #1331. Noah also stamped model/effort tags on issue titles (`memory/2026-09-26.md`).
- **11 issues are open:** #1311, #1312 (B/C), #1310, #1313, #1314, #1182, #1329, #1330, #1331, #1324, #1325. #1324 and #1325 describe what `621479d` already fixed.
- **The content stream is still running:** Jules/Grok generative plans and shaders landed 09-27 → 10-02, the catalog is at 1,374, and naga/extraBuffer/dead-slider gates pass. It stays decoupled from today's work.
- **Jest:** the "741 pass / 6 fail WASM bridge" line in `memory/2026-09-27.md` did not reproduce. A fresh run gives 764/0. That is the third week this boilerplate has been wrong.
- **Context gaps:** `recent_chats` and `conversation_search` are unavailable in this headless run, so there is no same-day-last-week or cross-project chat signal. I found no evidence that last week's track C (Claude Code whole-stack) ran. The routine's PROJECT CONTEXT is still stale: it says TS 4.9 and `@xenova/transformers`, but the repo is on TS ~5.4 and `@huggingface/transformers` v4.

## weekly_plan.md changes (written)

- **Today's focus:** added a 2026-10-03 block. The 09-26 block is archived in `<details>` with its outcome.
- **Ideas:** marked #1312-A, #1307, #1300 and #1308 done and #1309 closed. Set #1311 to `[WP-A in progress — 2026-10-03]`. Added #1330 (today's Copilot track), #1329 (next, sequenced after WP-A), the **10-26 expiry** as a must-pick for 10-10 or 10-17, and a close-out note for #1324/#1325. Removed a stale duplicate of the 09-26 Ideas block, which was a merge artifact.
- **Backlog:** added four items: the 10-26 cliff #2, the Jest boilerplate drift, `verify:catalog-counts` failing cold without `build:manifest`, and `deploy.py` having no dry-run.
- **Done:** added the 2026-10-03 reconciliation entry.
- **Last run:** marked the 09-26 outcome SHIPPED and appended the 10-03 entry.

## Today's focus

Quoted from Ideas: **"Foundation sweep: renderer lifecycle leaks, WASM bridge/C++ correctness, real lint gate, repo-root cleanup (#1311) — strongest next kimi candidate once the thumbs cliff is defused; mostly headless."** The cliff is defused, so today takes **WP-A only**.

I re-verified these on `main` today:
- **Metrics loop:** the rAF loop at `RendererManager.ts:210-215` is restarted on every switch (`:178`) and never cancelled.
- **`releasingDevice`:** set at `WebGPURenderer.ts:793`, checked at `:173`, never reset.
- **WASM render loop:** stops at `WASMRenderer.ts:655` with only a `console.error`.
- **Dead files:** `RendererContext`, `RendererToggle`, `ShaderDemo` and `useWASM` are all still present.
- **Hardcoded values:** `init.ts:25` hardcodes `'px_history_oom_cap'`, and `WASMRenderer.ts:517` hardcodes `index > 2`.

---

## Dispatch

### A. kimi-cli swarm task (the main event)

```text
ROLE: You are a long-running engineering swarm working in the repo ford442/image_video_effects
("Pixelocity": React 19 + TypeScript ~5.4 + CRA/CRACO + WGSL WebGPU compute shaders, optional C++/WASM
renderer that is FROZEN at Tier B as R&D). Work on a new branch: fix/1311-wpa-renderer-lifecycle.

OBJECTIVE
Land GitHub issue #1311 work package A ("TypeScript renderer lifecycle bugs") — and ONLY WP-A. Read the
issue first (gh issue view 1311 or the GitHub UI). Why: the TS WebGPU renderer leaks rAF loops on every
backend switch / StrictMode remount, can silently ignore a real device loss after an OOM retry, races a
re-probe against an in-flight device destroy, and lets the WASM backend die silently while still being
advertised as active. The next big engine change (#1314: worker renderer / frame graph) rewrites exactly
this code, so it must be correct and test-pinned first. Nothing here is a feature.

THE EIGHT ITEMS (line numbers in the issue have drifted ~30 lines in WebGPURenderer.ts — locate by symbol)
1. RendererManager.startMetricsCollection(): store the rAF id; cancel it before restart in switchRenderer
   and in destroy(). Test: 10 backend toggles => exactly one live loop (mock requestAnimationFrame /
   cancelAnimationFrame and count).
2. WebGPURenderer.releasingDevice: set in teardownGpuHandles, checked by the device.lost handler, never
   reset. Reset it once teardown completes / at the top of init(). Test: OOM-retry path then simulated
   device loss => recovery path runs.
3. WebGPURenderer.destroy() fires an un-awaited teardown; WebGPUCanvas.tsx calls destroy() synchronously
   and can re-run the boot probe mid-destroy. Make destroy() return the teardown Promise and await it in
   WebGPUCanvas before any re-probe. Reuse the existing release path in src/renderer/backendLifecycle.ts
   (do not invent a second one). Test: remount ordering (probe called only after teardown resolves).
4. WASMRenderer: after maxRenderErrorsBeforeStopping consecutive errors it flips initialized=false with
   only console.error. Route through the renderer's reportError channel so RendererManager stops
   advertising it / shows the existing failure overlay. Do NOT add a WebGL or Canvas2D fallback — the app
   policy is "WebGPU required" (docs/WEBGPU_BOOT_PROBE.md).
5. Two uncapturederror listeners (webgpuBootProbe.ts logs only; WebGPURenderer swallows GPUValidationError).
   Route both into reportError with a rate limit (e.g. first + every Nth per message). Keep the boot
   probe's breadcrumb JSON (window.webgpuProbe) unchanged in shape.
6. WebGPUCanvas.tsx restarts the render loop on every mousePosition change, and RendererManager.render()
   receives 9 ignored args. Move mouse into a ref read inside the loop; delete the dead arg plumbing.
   Test: N pointermoves => 0 extra loop restarts.
7. Delete dead code: src/components/shaders/RendererContext.tsx, RendererToggle.tsx, ShaderDemo.tsx (they
   load a nonexistent /wasm/wasm_renderer_test.js) and their exports from src/components/shaders/index.ts;
   src/hooks/useWASM.ts (+ its tests and hooks/index.ts export); webgpuDevicePolicy.requestAdapterWithFallback
   (+ its test — the boot probe ladder is the only ladder); the empty WebGPURenderer.render(){}; the
   log-only "buffering" effect in WebGPUCanvas.tsx. grep for every importer before deleting.
8. src/wasm/bridge/init.ts hardcodes the 'px_history_oom_cap' sessionStorage key — import it (and the cap
   derivation) from src/config/vramBudget.ts. WASMRenderer.getSlotState hardcodes `index > 2` — use
   PHYSICAL_SLOT_LIMIT. After touching src/wasm/bridge/*, run `node scripts/emit-wasm-bridge.mjs` so the
   generated public/wasm/bridge/*.js and wasm_renderer/bridge/*.js copies stay in sync (these generated
   JS copies are the one exception to the wasm_renderer/** boundary below — regenerate, never hand-edit),
   then `npm run verify:wasm-bridge-sync`.

ALLOWED TO TOUCH
- src/renderer/RendererManager.ts, src/renderer/WebGPURenderer.ts, src/renderer/WASMRenderer.ts,
  src/renderer/backendLifecycle.ts (reuse only), src/renderer/webgpuBootProbe.ts (the uncapturederror
  listener only), src/renderer/webgpuDevicePolicy.ts (delete the one dead export only)
- src/components/WebGPUCanvas.tsx, src/components/shaders/{RendererContext,RendererToggle,ShaderDemo}.tsx,
  src/components/shaders/index.ts, src/hooks/useWASM.ts, src/hooks/index.ts
- src/wasm/bridge/init.ts, src/config/vramBudget.ts (export only), and the emitted bridge copies the
  emit script regenerates (never hand-edit those)
- colocated *.test.ts(x) for all of the above; docs/WEBGPU_BOOT_PROBE.md if behaviour text changes
- .swarm-state.md

DO NOT TOUCH (hard boundaries)
- wasm_renderer/** C++ and public/wasm/pixelocity_wasm.* (emcc boundary + Tier-B freeze — WP-B is not yours)
- public/shaders/**, shader_definitions/**, shader_plans/**, shader_queue/** (live content stream)
- src/renderer/webgpu/** engine internals except where an item above strictly requires a call-site change
- src/gpuChores/**, src/contracts/** (read only), src/utils/adoptedGpuDevice.ts
- the adapter ladder / requiredLimits / dual canvas configure (Noah: "healthy — do not rewrite them")
- .github/workflows/**, playwright.config.ts, tests/** (Playwright — a parallel Copilot task owns these),
  src/hooks/useTestHarness.ts, scripts/deploy*.py, storage_manager/**
- the Controls renderer toggle UI (issue #1329 owns that; RendererToggle.tsx above is a different, dead file)
- weekly_plan.md, MEMORY.md, memory/** (WP-D is not yours)

ITERATION LOOP (repeat per item; one commit per item)
0. Iteration 0: `npm ci` (if sharp's postinstall fails with ECONNRESET, re-run), then record the baseline:
   `npx tsc --noEmit`, `CI=true npx craco test --watchAll=false` (expected ≈107 suites / 764 passed /
   0 failed as of 2026-10-03 — record what you actually measure), `npm run verify:dependency-boundaries`.
1. Write the failing Jest test for the item FIRST and prove it fails on the current code.
2. Fix. Re-run that test, then `npx tsc --noEmit`, then the full Jest suite.
3. Every 2 items: `SKIP_WASM_BUILD=1 npm run build` must compile with no new warnings-as-errors;
   `npm run verify:dependency-boundaries` and `npm run verify:wasm-bridge-sync` must pass.
4. If a test cannot be made to fail before the fix, say so in .swarm-state.md — do not fake it.
5. No GPU exists in your environment (navigator.gpu is absent headless). Do not try to "see" rendering.
   All verification is via mocks/spies in Jest + typecheck + build. Never add a fallback renderer to
   make something "work" headless.
6. Keep RendererManager.ts a thin facade (≤ ~430 LOC; it is 423 today) — extract into a small seam with
   its own test rather than growing it.

SAVE-STATE (mandatory)
At every iteration boundary append to .swarm-state.md a section:
  ## #1311 WP-A — iteration N — <ISO timestamp>
  - done: <item numbers + commit SHAs>
  - next: <item>
  - blocked: <anything, with the exact command + error>
  - tests: <suites/passed/failed/skipped, measured>
  - files changed: <paths>
Noah may stop you at any boundary and resume from this file; a resumed run reads it first.

DEFINITION OF DONE
- All 8 items committed, each with a test that pinned the bug.
- tsc clean; full Jest green with test count >= baseline + new tests; SKIP_WASM_BUILD=1 npm run build green;
  verify:dependency-boundaries + verify:wasm-bridge-sync green.
- Final .swarm-state.md entry lists every file changed and every item's before/after evidence.
- Do not open the PR yourself; leave the branch pushed for the wrap-up agent.
```

### B. GitHub issue draft (Copilot prep)

This expands the existing **#1330**. Paste it as a replacement body or as an expansion comment. It shares no files with A.

```markdown
# WASM bench harness: make the #1080 evidence numbers trustworthy (expands #1330)

## Context
#1080 closed with a **Stay B / frozen R&D** decision (`reports/wasm-promotion-evidence-2026-09-27.md`),
based on the first real-GPU run (Tesla T4). That run exposed harness bugs that flattered broken runs and
skewed real ones against the TS backend. Measurement tooling is explicitly in scope under the Tier-B
freeze. Active focus areas this serves: the WebGPU rendering engine's evidence base, and any future
reconsideration of WASM (which restarts the Gate-4 clock and will re-run this harness).

## Files in scope
- `playwright.config.ts`
- `tests/wasm-benchmark.spec.ts`
- `tests/helpers/**` (new helpers allowed)
- `src/hooks/useTestHarness.ts` (in-page `runBenchmark`)
- `reports/data/` (new timestamped output only)

## Out of scope (do not edit)
`wasm_renderer/**` (C++, frozen; includes the misleading "commonly happens on Windows" printf at
`wasm_renderer/device.cpp:220` — leave it and note it in the PR), `public/wasm/**`, `src/renderer/**`,
`src/components/WebGPUCanvas.tsx`, `.github/workflows/**`, any shader.

## Proposed approach (first pass)
1. **Launch flags:** `gpuArgs` in `playwright.config.ts`, applied only when `WASM_GPU_TESTS=1`.
   Everywhere: `--enable-unsafe-webgpu --ignore-gpu-blocklist`. Linux only:
   `--enable-features=Vulkan --use-vulkan=native --use-angle=vulkan --disable-vulkan-surface`.
2. **Page lifecycle:** collect `collectAdapterSummary(tsPage)` before closing the page, and close it in `finally` so the `continue` path cannot leak pages.
3. **Cross-leg contention:** navigate the WASM page to `about:blank` before the TS leg starts.
4. **Statistics:** `runBenchmark` computes p50/p95/max in-page over all samples and returns them. The spec stops deriving p95 from `samples.slice(-5)`. Keep `samples` in the payload only if it is needed, and say so.
5. **Partial results:** write the report in `finally`.
6. **Fail fast:** when `WASM_GPU_TESTS=1` and `requestAdapter()` returns null, fail with "no GPU adapter".
7. **Renderer health:** `assertExpectedBackend` / `benchBackend` also check `getDiagnostics()` (read-only use of the existing API), so a dead renderer cannot pass.
8. **Real platform:** record `process.platform`, `browser.version()` and both adapter summaries, not the spoofed UA.
9. **Artifact persistence:** write a timestamped copy to `reports/data/wasm-bench-<ISO>.json`, with the path configurable via an env var.

## Acceptance criteria (rough)
- [ ] With `WASM_GPU_TESTS` unset, `npx playwright test tests/wasm-benchmark.spec.ts --list` works and nothing about default CI changes.
- [ ] Pure helpers are unit-tested under Jest: the stats function (a known sample array gives exact p50/p95/max, and p95 ≤ max always holds) and the flag builder (`linux` and `win32` produce different arg sets).
- [ ] `tsc --noEmit` is clean, the full Jest suite is green, and `SKIP_WASM_BUILD=1 npm run build` is green.
- [ ] The report JSON schema is documented in a comment or a small `.md` next to the spec, with p50/p95/max, platform, browserVersion and adapters.
- [ ] The PR notes that GPU-run validation is pending Noah's hardware run.

## Open questions for Noah
1. Should p50/p95 be computed over frame **total** ms only, or over GPU-timestamp ms as well where available? Should this pre-wire #1331?
2. Should the `reports/data/` outputs be committed or gitignored? #1311 WP-D wants `reports/*.json` out of git.
3. Should the `devices['Desktop Chrome']` UA spoof be dropped entirely for the bench project?
4. Is a warm-up discard of N frames before sampling wanted? If so, what N?
```

### C. Chat-model expansion prompts

**Gemini Pro (codebase + issue → complete plan)**

```text
I'm attaching the repository ford442/image_video_effects (React 19 + TS ~5.4 + CRA/CRACO, WebGPU compute
shaders, a frozen C++/WASM renderer, Playwright for GPU benchmarks). Below is a GitHub issue I want an AI
coding agent to implement. Your job:
1. Read playwright.config.ts, tests/wasm-benchmark.spec.ts, tests/helpers/**, src/hooks/useTestHarness.ts,
   and how App.tsx exposes the test harness on window. Name every function/file the change touches.
2. Find dependencies the issue missed (e.g. other specs that import the same helpers, the shape consumers
   expect from runBenchmark, anything reading test-results/ or reports/data/).
3. Produce a numbered implementation plan with exact function signatures for the new stats helper and the
   flag builder, the report JSON schema, and the Jest tests to add.
4. Flag anything in the plan that would require touching src/renderer/** or wasm_renderer/** (forbidden).

ISSUE:
<paste the full issue from section B here>
```

**Kimi.com K2 (stress-test + 2 alternatives)**

```text
You're reviewing a proposed fix to a Playwright-based WebGPU benchmark harness that compares a TypeScript
WebGPU renderer against a C++/Emscripten (emdawnwebgpu) WASM renderer in headless Chromium on real GPUs
(Tesla T4 on Linux, NVIDIA on Windows). The current harness produced misleading numbers. Below is the
issue. Please:
1. Stress-test the proposed approach: where can it still produce wrong or biased numbers? Consider vsync
   capping, rAF throttling of background pages, GPU contention across two pages in one browser, warm-up
   and shader-compile spikes, sample-count sufficiency for p95, and Linux Vulkan flag fragility.
2. Propose two materially different alternatives (e.g. one-browser-context-per-leg / separate browser
   processes; in-page GPU timestamp queries instead of frame timing; a fixed-frame offline render loop).
3. Argue for the best of the three and list the minimum acceptance tests that would prove it measures
   what it claims.

ISSUE:
<paste the full issue from section B here>
```

**Grok.com (ecosystem currency)**

```text
Ecosystem check, October 2026. A project benchmarks WebGPU in headless Chromium via Playwright, comparing
a TypeScript WebGPU renderer against an Emscripten + emdawnwebgpu WASM renderer, on Linux (Tesla T4,
Vulkan) and Windows (D3D12). Stack: Playwright Test, Chromium, React 19, TypeScript ~5.4, Emscripten 6.x.
The plan below relies on these launch flags: --enable-unsafe-webgpu, --ignore-gpu-blocklist,
--enable-features=Vulkan, --use-vulkan=native, --use-angle=vulkan, --disable-vulkan-surface.
Tell me:
1. Which of those flags are still needed, renamed, or harmful in current Chromium/Playwright releases,
   and what the current recommended recipe is for headless WebGPU on Linux NVIDIA and on Windows.
2. Whether `timestamp-query` is now usable without flags in headless Chromium, and the current best
   practice for GPU-time measurement in WebGPU (vs frame-time).
3. Any Playwright changes (new GPU options, channel names like chromium-headless-shell, trace/artifact
   behaviour) that affect this plan.
Cite release notes or bug tracker links where you can. Be explicit about what you are unsure of.

ISSUE:
<paste the full issue from section B here>
```

### D. Copilot Agent handoff

```text
Implement the GitHub issue below in ford442/image_video_effects.

{{EXPANDED_ISSUE}}

Hard rules:
- Edit ONLY: playwright.config.ts, tests/wasm-benchmark.spec.ts, tests/helpers/**, src/hooks/useTestHarness.ts,
  new files under reports/data/ (if the issue says to commit them), and new Jest tests for pure helpers.
- Never edit wasm_renderer/**, public/wasm/**, src/renderer/**, src/components/WebGPUCanvas.tsx,
  .github/workflows/**, or any shader. Another agent is changing src/renderer/** in parallel.
- No GPU is available in your environment: put logic in pure, Jest-testable helpers; GPU-only paths stay
  behind WASM_GPU_TESTS=1 and must not change default CI behaviour.
- Before opening the PR run: npx tsc --noEmit; CI=true npx craco test --watchAll=false;
  SKIP_WASM_BUILD=1 npm run build; npx playwright test tests/wasm-benchmark.spec.ts --list.
- PR description: checklist of every acceptance criterion with evidence, plus "GPU validation pending".
```

### E. Claude Code whole-stack task (mid-day)

```text
Repo ford442/image_video_effects. Goal: exercise the real pipeline end to end, which is
React/WebGPU client build → SFTP deploy to DreamHost (scripts/deploy.py) → FastAPI Storage Manager
(storage_manager/) on a VPS. Fix the one gap that makes this impossible to rehearse safely:
scripts/deploy.py has no dry-run mode.

1. Read scripts/deploy.py, scripts/deploy_app_only.py, scripts/deploy_credentials.py and the "deploy*"
   npm scripts. Add `--dry-run` to scripts/deploy.py (and deploy_app_only.py if it shares the walk):
   resolve credentials lazily so dry-run needs none, never open an SFTP connection, print the remote
   root, file count, total bytes, and the first/last 20 paths it WOULD upload, and exit 0. Add a pytest
   (or a plain python unittest under scripts/) that runs the walk against a temp dir and asserts zero
   network calls (monkeypatch paramiko/pysftp). Do not change real-deploy behaviour.
2. Normalise the deploy* / sync:shaders* npm scripts from bare `python` to `python3` (only those lines).
3. Rehearse: `npm ci` → `npm run build:manifest` (verify:catalog-counts needs
   public/shader-manifest-unified.json) → `npm run verify:toolchain-foundation` (record each stage) →
   `SKIP_WASM_BUILD=1 npm run build` → `python3 scripts/deploy.py --dry-run` against build/.
   Check: build/ contains shader-lists with RELATIVE paths unless SHADER_LIST_BASE_URL is set; flag any
   absolute storage.noahcohn.com URLs baked into a non-deploy build.
4. Backend: `pip install -r storage_manager/requirements.txt` in a venv, run
   `python3 -m pytest storage_manager/tests -q`, then start the app locally (uvicorn) and curl
   GET /api/health; record the JSON. External hosts (storage.noahcohn.com etc.) are blocked from this VM;
   do not treat that as a failure, and do not touch the real VPS.
5. Report: a short table (stage, command, result, duration) in reports/pipeline_rehearsal_2026-10-03.md.
   Open a PR with the dry-run + python3 normalisation + report. Do not touch src/renderer/**, tests/**,
   playwright.config.ts or any shader (other agents own those today).
```

### F. Jules wrap-up template (end of day)

```text
You are wrapping up a completed kimi-cli swarm run in ford442/image_video_effects (Pixelocity: React 19,
TypeScript ~5.4, CRA via CRACO, WGSL WebGPU compute shaders, frozen C++/WASM renderer). The swarm worked
on GitHub issue #1311 work package A: TypeScript renderer lifecycle bugs (metrics rAF leak on backend
switch, releasingDevice never reset after OOM retry, un-awaited destroy racing the boot re-probe, silent
WASM render-loop stop, validation errors not reaching reportError, render loop restarting on pointermove,
dead-code deletion, bridge constants behind contracts). Branch: fix/1311-wpa-renderer-lifecycle.

FILES THE SWARM CHANGED:
{{KIMI_CLI_FILES_CHANGED}}

WHAT IT DID:
{{KIMI_CLI_SUMMARY}}

KNOWN ISSUES NOAH SPOTTED:
{{KNOWN_ISSUES}}

Read .swarm-state.md (latest "#1311 WP-A" sections) and `gh issue view 1311` before starting.

WRAP-UP CHECKLIST (do all, in order; commit in small logical commits on the same branch)
1. Install: `npm ci` (re-run once if sharp's postinstall fails with ECONNRESET).
2. Format: there is no repo-wide Prettier config yet — match surrounding style; do not reformat untouched
   files. Run `npx eslint <changed files> --ext .ts,.tsx` and fix every error/warning in CHANGED lines
   (repo-wide lint is non-gating and has pre-existing noise; do not fix unrelated files).
3. Typecheck: `npx tsc --noEmit` — must be clean.
4. Tests: `CI=true npx craco test --watchAll=false` (same as `npm test` in CI mode). Baseline on
   2026-10-03 was 107 suites / 764 passed / 1 skipped / 0 failed; the result must be >= that plus the
   swarm's new tests, 0 failed. Fix failures at the root cause; never skip, .only, or delete a test to go green.
5. Complete any TODO / FIXME / stub the swarm left in the changed files (grep them). If one genuinely
   cannot be finished, leave it with a `// TODO(#1311-WPA):` and list it in the PR.
6. Coverage: every new or changed exported function/class method (e.g. the metrics loop seam, the
   awaited destroy, the rate-limited error router) has a Jest test; add any missing ones. Each of the 8
   WP-A items must have a test that would fail without the fix — verify by temporarily reverting the fix
   locally for at least items 1, 2 and 3 and confirming the test goes red (do not commit the revert).
7. Bridge sync: if anything under src/wasm/bridge/ changed, regenerate the emitted copies with
   `node scripts/emit-wasm-bridge.mjs` and run `npm run verify:wasm-bridge-sync` and `npm run wasm:validate`.
8. Boundaries: `npm run verify:dependency-boundaries`; confirm `git diff origin/main --stat` touches no
   wasm_renderer/**, public/wasm/pixelocity_wasm.*, public/shaders/**, shader_definitions/**,
   .github/workflows/**, tests/** (Playwright) or playwright.config.ts. Revert any such change.
9. Docs: if public behaviour changed (destroy() now returns a Promise, errors now reach reportError, dead
   components removed), update docs/WEBGPU_BOOT_PROBE.md and any README/doc references to the deleted
   files (grep for RendererToggle, ShaderDemo, RendererContext, useWASM, requestAdapterWithFallback).
10. Build: `SKIP_WASM_BUILD=1 npm run build` must pass.
11. Open a PR to main titled "fix(renderer): #1311 WP-A — TS renderer lifecycle bugs" with: summary per
    item (1–8) with test names, the before/after Jest counts, the command log for steps 3/4/7/8/10, any
    leftover TODOs, and "Real-GPU visual QA pending (Noah)". Reference #1311 but do NOT write "closes".

ACCEPTANCE (all must be ticked in the PR body)
- [ ] tsc clean
- [ ] Jest: 0 failed, count >= baseline + new tests
- [ ] Each of WP-A items 1–8 has a pinning test; items 1–3 proven red-without-fix
- [ ] SKIP_WASM_BUILD=1 npm run build green
- [ ] verify:dependency-boundaries green; verify:wasm-bridge-sync + wasm:validate green if bridge touched
- [ ] No files outside the WP-A allowlist changed
- [ ] Docs updated for changed public behaviour / deleted files
- [ ] No WebGL/Canvas2D fallback introduced

Open the PR for Noah to review. DO NOT MERGE.
```

### G. Review prompts (Gemini Pro)

**1. Raw kimi-cli diff (before Jules)**

```text
Attached: the diff of branch fix/1311-wpa-renderer-lifecycle vs main in ford442/image_video_effects, plus
src/renderer/RendererManager.ts, WebGPURenderer.ts, WASMRenderer.ts, backendLifecycle.ts,
webgpuBootProbe.ts and src/components/WebGPUCanvas.tsx at HEAD. Context: React 19 + TS WebGPU renderer;
the app hard-requires WebGPU (no fallback); a single GPUDevice comes from the boot probe; the C++/WASM
backend is frozen R&D. The diff should fix #1311 WP-A items 1–8 (pasted below) and nothing else.
Review for:
1. Performance: anything new on the per-frame path (allocations, closures, Promise chains, logging,
   ref reads) — the render loop runs at display rate with up to 6 slots.
2. Lifecycle correctness: can any rAF loop, listener, or device survive destroy/switch? Any await that
   can deadlock remount (StrictMode double-mount)? Any reportError storm?
3. Architectural drift: a second release path instead of reusing backendLifecycle; a new device request;
   a fallback renderer; RendererManager growing instead of a seam; changes outside the allowlist.
4. Test quality: does each test actually fail without its fix, or does it assert the mock?
Output: a ranked list (blocker / should-fix / nit) with file:line and a concrete fix.

#1311 WP-A text:
<paste WP-A section of issue #1311>
```

**2. Jules PR vs objective + checklist**

```text
Attached: the Jules PR (diff + description) for "fix(renderer): #1311 WP-A — TS renderer lifecycle bugs"
in ford442/image_video_effects, the original swarm objective, and the wrap-up checklist below.
1. For each WP-A item 1–8: is it fixed, is there a pinning test, and does the test plausibly fail without
   the fix? Mark ✅/⚠️/❌ with evidence.
2. For each checklist item: did the PR actually do it, with command output as evidence, or just claim it?
3. Did Jules change behaviour beyond tidy-up (new logic, broadened scope, edits outside the allowlist,
   deleted or weakened tests)? List each.
4. Merge recommendation: merge / merge after fixes (list) / reject (why).

Original objective:
<paste section A objective + eight items>

Wrap-up checklist:
<paste section F checklist + acceptance>
```

---

## Suggested timeline

| Offset | Step |
|---|---|
| 0:00–0:15 | Start A (kimi-cli). Paste B into #1330. |
| 0:15–1:15 | Run the three C prompts in parallel, merge them into #1330, then hand off D to Copilot. |
| ~2:30 | E (Claude Code pipeline rehearsal + `deploy.py --dry-run`), about 1–1.5 h. |
| When kimi finishes | G1 on the raw diff, then fill in and launch F (Jules). |
| End of day | G2 on the Jules PR. Close #1324/#1325. |

## Open questions

- **Next week's pick:** the 2026-10-26 thumbnail expiry needs a decision by 10-17 at the latest. Is a `gpu` self-hosted runner going to register, or does the routine plan a second honest removal?
- **WP-D (repo-root cleanup) wants this routine's own files moved:** `weekly_plan.md`, `MEMORY.md` and `memory/` would go to a gitignored `.agents/`. Where should the routine read and write afterwards?
- **#1324 / #1325:** fixed by `621479d`. Are you OK closing them?
- **PROJECT CONTEXT is stale:** it still says TS 4.9 and `@xenova/transformers`. The repo is on TS ~5.4 and `@huggingface/transformers` v4. The block lives in the routine prompt, which this run can't edit.
- **Unverified:** whether last week's Claude Code track C ran at all. There's no commit or report for it.
