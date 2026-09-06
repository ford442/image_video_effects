# image_video_effects — 2026-09-05 dispatch

**Status:** #1180 (TS/C++ workgroup fallback + empty-placeholder packing parity) shipped + merged + closed, all three parts; every headless gate green. Today = **lock the 2026-08-30/31 real-GPU WASM boot cascade (#1200–#1206) behind headless invariants**. Plan updated, PR #1221 open.

## Mode declaration

**User Idea mode.** The 2026-08-26 audit set is spent — #1179/#1180/#1181/#1183/#1184/#1185 are all **closed**, leaving only the `future`-tagged #1182. Noah's **2026-08-30/31 real-GPU session on Pascal/Chrome** (`test.1ink.us`) is now the freshest in-context signal and produced #1200–#1206; per standing precedent that set is the live Ideas source. Foundation is healthy on every gate → **not Fix First**.

The pick is shaped by one fact that changes what "work on these bugs" means: **all six already have fixes in the tree.** What none of them has is a *guard*. So today is proof, not repair.

## Context from prior sessions

- **Last week's focus #1180 SHIPPED + MERGED + CLOSED — all three parts**, verified on `main` @ `d5fffd4`. (A) `src/contracts/workgroup_dispatch.json` is the SoT and `src/renderer/ShaderCompilation.ts` returns `workgroupDispatchContract.unparsedFallback` (warning now reads "defaulting to 16x16"). (B) A fresh histogram of `public/shaders/*.wgsl` is **1408 × 16×16×1, 1 × 256×1×1, 1 × 16×16×4, and zero × 8×8** — all 26 leftovers migrated, and the catalog grew ~50 files in the same window without reintroducing one. (C) `wasm_renderer/resources.cpp` builds the 1×1 placeholder from an explicitly reset descriptor and uploads `bytesPerRow = sizeof(float)` (4 B, was 16). `npm run verify:device-policy` reports `workgroup_dispatch + emptyPlaceholder` in sync.
- **Noah ran a real-GPU session 2026-08-30/31** on Pascal/Chrome and filed seven issues: #1200 (gpu-chores-reduce `DispatchWorkgroups(65536)` > 65535 → black blink — the only one on the **default TS production path**), #1201 (remote-control gaps), #1202 (`wgpuSurfacePresent` unsupported in browser → abort), #1203 (`CreateSampler maxAnisotropy=0` → invalid bind groups), #1204 (`historyTex` `GPUOutOfMemoryError` on Pascal 2048²), #1205 (pipeline format mismatch, layout RGBA32Float vs shader RGBA16Float), #1206 (WASM boots clean then shows no image after JS→WASM switch). His own root-cause writeups are in `memory/2026-08-30.md` and `memory/2026-08-31.md` — read directly this run, and the authoritative account.
- **He also fixed all six the same night**, verified individually in tree: `GpuChoresHost.ts:307` now dispatches 2-D `(ceil(srcW/8), ceil(srcH/8))` with `shaders.ts` reduce at `@workgroup_size(8,8)` (`ac253e0`); `device.cpp:782-783` carries the "Do not call wgpuSurfacePresent…" contract comment and the call is gone; `resources.cpp` sets `samplerDesc.maxAnisotropy = 1` before all three `wgpuDeviceCreateSampler` calls; `historyTexProbe.ts` (+ colocated test) and `vramBudget.ts`'s `px_history_oom_cap` implement the 2048×8 → 1024×8 → 1024×4 → 1024×1 ladder, with `historyLayerCount_` threaded through `pipeline.cpp`/`frame.cpp`/`resources.cpp`; the `colorFormat_` storage-decl rewrite lives in `bridge/wgslFormat.js` + `pipeline.cpp`; `rebindMediaAfterBackendSwitch` is in `inputSourceBridge.ts` (+ test). Rebuilt `public/wasm/pixelocity_wasm.{js,wasm}` were committed the same day (`504a59c`) and `wasm:validate` passes on them.
- **But every issue is still open**, each annotated "Real-GPU confirm still needed", with the `go.1ink.us` promote on **HOLD**. And there is **no guard anywhere**: `maxAnisotropy` occurs in exactly one file repo-wide (`wasm_renderer/resources.cpp`) and in no test; nothing forbids re-adding `wgpuSurfacePresent`; nothing asserts the shipped `.wasm` is free of that import; and only **one** of the five `GpuChoresHost.ts` dispatch sites was converted — `:294`, `:468`, `:516`, `:552` remain unclamped against `maxComputeWorkgroupsPerDimension`.
- **#1184 landed visibly** even though it was last week's Copilot track: `public/shader-id-aliases.json`, `reports/catalog_drift.{md,json}`, and `verify:catalog-counts` are all in tree.
- **Gate status this run (all run live, not carried):** `verify:device-policy` ✅ · `verify:uniforms` ✅ · `wasm:validate` ✅ (artifacts + all four `bridge/*.js` in sync) · `audit:dead-sliders` PASS (1201 scanned, **0 new**, 26 known) · `audit:extrabuffer` PASS (0 new, 84 known, 32 dynamic-index for review, 0 out-of-range).

**Context gaps (flagged, not hidden):**

- `recent_chats` / `conversation_search` **unavailable** in this headless scheduled run. Context is reconstructed from the repo tree, `weekly_plan.md`, `.swarm-state.md`, `memory/2026-08-30.md` + `memory/2026-08-31.md`, live gate runs, and GitHub issue/PR state — not from conversation history.
- **Jest count carried, not measured.** `node_modules` is absent on this VM and plain `npm ci` is still blocked by the `sharp` postinstall behind the proxy (`npm ci --ignore-scripts` is the workaround). `.swarm-state.md` last recorded 84 suites / 550 passed / 1 skipped. kimi re-establishes the baseline on iteration 0.
- **`verify:wasm-bridge-sync` could not run** — `ERR_MODULE_NOT_FOUND` from the absent `node_modules`. Environmental, not a defect; `wasm:validate` covers the same artifacts and passes.
- **Real-GPU status of the six fixes is unknown to this run.** They are verified *present in source*; none is verified *working on hardware*. Nothing below claims otherwise.

## weekly_plan.md changes (written to the file, PR #1221)

- **Today's focus** — new 2026-09-05 block; the 08-29 (#1180) block archived into a `<details>`.
- **Ideas** — #1180 marked `[x]` with all three parts' verification evidence; the 08-26 set marked spent; the 08-30/31 cascade added as the live source with the picked item marked `[in progress — 2026-09-05]`; #1201, #1080, #1182 added as non-picks.
- **Backlog** — four new entries: the 08-30/31 set as live backlog; the "zero automated guards" finding; the **emcc 6.0.3 vs 3.1.56 read-only boundary**; and stale PR #1219.
- **Done** — 2026-09-05 entry for #1180 with per-part evidence and the full gate table.
- **Last run** — 08-29 outcome flipped from `pending` to SHIPPED+MERGED+CLOSED; new 2026-09-05 entry appended.

## Today's focus

**Lock the 2026-08-30/31 real-GPU WASM boot cascade behind headless invariants (#1200–#1206; unblocks #1080).**

Six bugs, six fixes already in tree, zero guards, six open issues, and a promote on HOLD. The gap is not code — it is that nothing in the repo can re-check any of this, and nothing tells Noah what is actually proven. Today closes both: every root cause becomes a machine-checked invariant (the pattern `uniforms_layout.json` and last week's `workgroup_dispatch.json` already established), and the run emits `reports/wasm_promotion_evidence.md` — the artifact #1080 has been blocked on since 08-07.

The sharpest single check available: the 08-31 memory note observes that the emscripten glue DCE-dropped `_wgpuSurfacePresent` and the wasm bytes no longer contain the import. That is a one-time observation today. Parsing the `.wasm` import table in CI turns it into a permanent proof.

**A hard new boundary applies to every track:** Noah rebuilt the artifacts with **emcc 6.0.3**; this VM has **3.1.56 with no emdawnwebgpu port** (#848). Editing `wasm_renderer/**` would desync the committed `.wasm` from its source and break `wasm:validate`. C++ is read-only until #848 is resolved.

---

# Dispatch

## A. kimi-cli swarm task — the main event

```
You are working in the Pixelocity repo (image_video_effects): a React 19 + TypeScript
web app that renders real-time image/video effects with WebGPU compute shaders, with an
experimental opt-in C++/WASM renderer backend alongside the production TypeScript one.

# Objective

On 2026-08-30/31 the maintainer ran the project's first real-GPU debugging session on a
Pascal-class NVIDIA GPU under Chrome/Windows and found six distinct runtime bugs. He
diagnosed every root cause and fixed every one of them in the tree the same night. He
then left all six issues OPEN, annotated each "Real-GPU confirm still needed", and put
the production promote on HOLD.

Your job is NOT to fix these bugs. They are already fixed. Your job is to make them
UN-REGRESSABLE and to make the current state LEGIBLE, because right now:

  - `maxAnisotropy` appears in exactly ONE file in the entire repository
    (`wasm_renderer/resources.cpp`) and in ZERO tests.
  - Nothing prevents a future agent from re-adding the `wgpuSurfacePresent` call that
    hard-aborts the renderer in a browser.
  - Nothing asserts that the shipped `public/wasm/pixelocity_wasm.wasm` is free of that
    import (it currently is, by dead-code elimination — but that is luck, not a gate).
  - Only ONE of the five `dispatchWorkgroups` call sites in `src/gpuChores/GpuChoresHost.ts`
    was hardened; the other four can still exceed the device limit.
  - No document states which of the six fixes is confirmed on hardware and which is not.

This repository already has the right pattern for this: `src/contracts/*.json` files that
are validated against both the TypeScript and the C++ sources by
`scripts/verify-device-policy-sync.js`. Read `src/contracts/workgroup_dispatch.json` and
`src/contracts/webgpu_limits.json` and mirror their shape exactly. Do not invent a new
mechanism.

# Read these first — they are the authoritative account

  - `memory/2026-08-30.md` and `memory/2026-08-31.md` — the maintainer's own root-cause
    notes for all six bugs. Everything you assert must be traceable to these or to code.
  - `src/contracts/workgroup_dispatch.json` — the contract shape to mirror.
  - `scripts/verify-device-policy-sync.js` — the validator you are extending.
  - `docs/GPU_CHORES.md`, `docs/BINDING_CONTRACT.md`.

# The six root causes you are locking down

  1. gpu-chores reduce dispatched `ceil(srcW*srcH/64)` as a 1-D grid, which at large
     canvas sizes produced `DispatchWorkgroups(65536,1,1)` and exceeded
     `maxComputeWorkgroupsPerDimension` (65535), throwing a GPUValidationError every
     frame (visible as a steady black blink). Fixed by moving the kernel to
     `@workgroup_size(8,8)` and dispatching 2-D.
  2. The C++ present path called `wgpuSurfacePresent`, whose emdawnwebgpu browser stub
     aborts the module ("use requestAnimationFrame via html5.h instead"). JS rAF already
     drives the render loop. Fixed by acquire + blit + submit, then return.
  3. `WGPUSamplerDescriptor samplerDesc = {}` left `maxAnisotropy` at 0; Dawn requires
     >= 1 for every sampler type including comparison samplers, so all bind groups using
     them were rejected. Fixed by setting it once before the three sampler creations.
  4. `historyTex` at 2048² × 8 rgba-float layers (~256-512 MiB) hit a committed-heap
     GPUOutOfMemoryError on Pascal under D3D12. Fixed with a probe ladder
     2048×8 -> 1024×8 -> 1024×4 -> 1024×1, a `px_history_oom_cap` sessionStorage latch
     that never retries the larger size in the same tab, and a C++ fail-soft path.
  5. The WASM pipeline layout declared RGBA32Float while a rewritten shader declared
     RGBA16Float, producing an invalid pipeline submitted every frame. Fixed by having
     WASM prefer rgba16float after a successful probe and rewrite storage declarations to
     the active colour format at LoadShader time; catalog WGSL stays rgba32float.
  6. After a JS->WASM backend switch the canvas showed no image: the exclusive switch
     destroys the JS device that owned the uploaded photo, and the new WASM device was
     never given the pixels. Fixed by re-uploading the current image/video frame after
     the switch, then resyncing the shader stack.

# Work items

1. Create `src/contracts/wasm_runtime_invariants.json` as the single source of truth,
   mirroring the existing contract files' shape. It must encode at minimum:
     - `forbiddenCppSymbols`: `wgpuSurfacePresent`, each with the reason and the correct
       alternative, and the source globs the ban applies to.
     - `requiredSamplerDefaults`: `maxAnisotropy` minimum 1, noting it applies to
       filtering, non-filtering AND comparison samplers.
     - `historyTexLadder`: [[2048,8],[1024,8],[1024,4],[1024,1]] plus the
       `px_history_oom_cap` sessionStorage key name.
     - `storageFormatRewrite`: catalog WGSL stays rgba32float; WASM rewrites storage
       declarations to the active colour format after a successful probe.
     - `maxComputeWorkgroupsPerDimension`: 65535, as the dispatch ceiling.
   Every entry carries the issue number that produced it and a one-line rationale.

2. Extend `scripts/verify-device-policy-sync.js` to enforce all of the above against the
   real sources. EXTEND ONLY — the existing limits / optional-features / wasm_exports /
   workgroup_dispatch / emptyPlaceholder checks are currently green and must stay green
   and unweakened. Specifically:
     - Scan `wasm_renderer/**/*.cpp` for the forbidden symbols and fail on any call.
     - Assert the `maxAnisotropy` assignment in `resources.cpp` precedes all three
       `wgpuDeviceCreateSampler` calls.
     - Assert the TS history ladder in `src/config/vramBudget.ts` and
       `src/renderer/webgpu/historyTexProbe.ts` matches the JSON.
     - **Parse the import table of `public/wasm/pixelocity_wasm.wasm`** and fail if any
       forbidden symbol appears as an import. This is a binary check on the actual
       shipped artifact — implement a minimal WASM import-section reader (the format is
       simple: magic + version, then sections; you want section id 2). Put it in
       `scripts/wasm_import_table.js` if that reads more cleanly than inlining it.
   Expose it as `npm run verify:wasm-invariants` and add it to `verify:toolchain-foundation`
   without reordering or dropping any existing script.

3. Add `src/gpuChores/dispatchLimits.ts` exporting a shared
   `assertDispatchWithinLimits(x, y, z, limits)` (or a clamping equivalent — pick one and
   be consistent), and route ALL FIVE `dispatchWorkgroups` call sites in
   `src/gpuChores/GpuChoresHost.ts` through it: the histogram, reduce, source-gain, LUT
   and downsample passes. Do not touch the kernel math or `src/gpuChores/shaders.ts` —
   the 8x8 reduce kernel IS the fix, do not revert or re-tune it. Extend
   `src/gpuChores/gpuChores.test.ts` (which already asserts the reduce dispatch stays
   <= 65535) to cover all five passes, with a 2048-square source and a deliberately
   oversized one.

4. Extend `tests/wasm-renderer.smoke.spec.ts` (or add a sibling spec) with a Playwright
   `?renderer=wasm` boot smoke that installs an `uncapturederror` / GPUValidationError
   listener and FAILS the spec on any captured error, plus a JS->WASM switch case
   asserting the input is non-empty afterwards (root cause 6). It must SKIP CLEANLY when
   no GPU adapter is present so headless CI stays green — a skip is correct here, a
   false pass is not.

5. Write `docs/WASM_RUNTIME_INVARIANTS.md` mapping each invariant -> the issue that
   produced it -> the guard that now enforces it. Then write
   `reports/wasm_promotion_evidence.md`: for each of the six bugs, state the root cause,
   the fix location, the automated guard you added, and an explicit
   **GPU-CONFIRMED** or **GPU-PENDING** flag. This document is the deliverable the
   maintainer takes to the promotion decision. Be honest: you cannot confirm anything on
   hardware from here, so almost everything is GPU-PENDING. Marking something
   GPU-CONFIRMED that you only checked headlessly makes the whole document worthless.

# Files you may touch

  - NEW `src/contracts/wasm_runtime_invariants.json`
  - `scripts/verify-device-policy-sync.js` (extend only)
  - NEW `scripts/wasm_import_table.js`
  - `src/gpuChores/GpuChoresHost.ts` (dispatch-clamp routing ONLY)
  - NEW `src/gpuChores/dispatchLimits.ts` (+ colocated test)
  - `src/gpuChores/gpuChores.test.ts`
  - `tests/wasm-renderer.smoke.spec.ts`, `tests/helpers/**`
  - `src/config/vramBudget.ts`, `src/renderer/webgpu/historyTexProbe.ts` — ONLY if the
    ladder must be read from the contract rather than a literal. They are already
    correct; prefer leaving them alone.
  - NEW `docs/WASM_RUNTIME_INVARIANTS.md`, NEW `reports/wasm_promotion_evidence.md`
  - `docs/GPU_CHORES.md` (dispatch-ceiling note)
  - `package.json` (add the new script, wire it into verify:toolchain-foundation)

READ-ONLY reference (read to write assertions; never edit):
  `wasm_renderer/**`, `public/wasm/*` (parse, never regenerate),
  `memory/2026-08-30.md`, `memory/2026-08-31.md`,
  `src/contracts/webgpu_limits.json`, `src/contracts/workgroup_dispatch.json`

# Files you must NOT touch

  - **`wasm_renderer/**` C++ sources and `public/wasm/*` artifacts.** The maintainer
    rebuilt these with emcc 6.0.3 on 08-31 and the source and artifacts were committed
    together. This machine has emcc 3.1.56 with no emdawnwebgpu port, so it CANNOT
    rebuild them. Any C++ edit silently desyncs the shipped .wasm from its source and
    breaks `npm run wasm:validate`. This is a hard boundary, not a preference.
  - `src/gpuChores/shaders.ts` — the 8x8 reduce kernel is the fix.
  - The adapter ladder, `webgpuDevicePolicy.ts`, `webgpuBootProbe.ts`,
    `WebGpuProbeFailureOverlay` — frozen.
  - `src/utils/adoptedGpuDevice.ts`, `RendererManager.getDevice()` — the device
    single-source-of-truth; do not re-plumb it.
  - `src/renderer/ShaderCompilation.ts`, `src/contracts/workgroup_dispatch.json` — just
    closed last week; do not reopen the dispatch contract.
  - `src/renderer/UniformBuffer.ts` — immutable uniform packing.
  - `src/RemoteApp.tsx`, `src/RemoteControlHeader.tsx`,
    `src/components/app/AppShell.tsx`, `src/hooks/useRemoteSync.ts`, `src/style.css` —
    a separate agent owns these today. Staying out of them is what keeps the two tracks
    from colliding.
  - `storage_manager/**`, `public/shaders/**`, `shader_definitions/**`, `shader_plans/**`.

Do not change the WASM default-backend policy (it stays experimental opt-in). Do not add
a WebGL fallback. Do not close any of the six issues — real-GPU confirmation belongs to
the maintainer, not to you.

# How to verify yourself, every iteration

Run these and do not proceed past a red one:

  npm ci --ignore-scripts        # plain `npm ci` is blocked by the sharp postinstall
  npx tsc --noEmit               # must be clean on src/
  CI=true npx craco test --watchAll=false
  SKIP_WASM_BUILD=1 npm run build            # must print "Compiled successfully"
  npm run verify:device-policy               # must stay green
  npm run verify:wasm-invariants             # your new gate
  npm run wasm:validate                      # proof you did not touch the artifacts
  npm run verify:uniforms
  npm run verify:dependency-boundaries
  npm run audit:extrabuffer                  # baseline: 0 new / 84 known
  npm run audit:dead-sliders                 # baseline: 0 new / 26 known

On iteration 0, RE-ESTABLISH the test baseline before changing anything and record it.
The last recorded count was 84 suites / 550 passed / 1 skipped, but it was carried from a
previous session rather than measured, so treat it as approximate.

**Prove each guard actually bites.** A gate that cannot fail is not a gate. For each
invariant, temporarily reintroduce the regression — add a `wgpuSurfacePresent` call, drop
the `maxAnisotropy` line, set a dispatch above the ceiling — confirm the check FAILS, then
revert. Record each of these proofs in your save-state. If a check passes both with and
without the regression, it is broken; fix it before moving on.

eslint noise is non-gating. Focus on tests, build, and the verify gates.

# Save-state

At every iteration boundary, append to `.swarm-state.md`:
  - Iteration number and date
  - What changed, file by file
  - Real command output for each gate above (not a summary — the actual result lines)
  - The bite-proof result for each new invariant
  - What is still GPU-PENDING and therefore cannot be closed from here
  - What you would do next if interrupted right now

Write this so the maintainer can stop you at any point and resume cleanly without
re-deriving anything.

# Definition of done

  - All six root causes represented in `wasm_runtime_invariants.json`, each with a
    passing enforcement check AND a recorded proof that the check fails on a
    reintroduced regression.
  - The .wasm import-table assertion runs in CI and passes on the committed artifact.
  - All five gpu-chores dispatch sites clamped and unit-tested.
  - The `?renderer=wasm` boot smoke exists and skips cleanly without an adapter.
  - `reports/wasm_promotion_evidence.md` written, with honest GPU-CONFIRMED /
    GPU-PENDING flags on every line.
  - Every gate above green, `wasm:validate` included.
  - Zero edits under `wasm_renderer/` and `public/wasm/`.
```

## B. GitHub issue — FILED as #1195

**[#1195 — Catalog count SoT: assert the derivable invariant, alias legacy IDs, split the extraBuffer baseline](https://github.com/ford442/image_video_effects/issues/1195)**

Expanded 2026-08-29 from the section-B draft using the Gemini / Kimi / Grok reviews **plus a verification pass against `a27a627`**. The verification overturned part of #1184's premise, so the filed issue differs materially from the draft. Full text also saved at `weekly_issue_catalog_sot.md`.

**What the verification changed:**

- **The "13 ID-vs-filename mismatches, mostly graph parents" premise is wrong.** There are **33** mismatches and **zero** are graph parents (all 7 `multipass.graph` definitions have `id == filename`). 31 are the cosmetic inverse case — underscore *filename*, hyphenated *ID*. The "whitelist graph parents" step all three reviews built a plan around is a **no-op** and was dropped.
- **The 13-count gap is real but differently caused:** it is exactly the 13 definitions with `multipass.pass > 1` (`vortex-pass2`, `quantum-foam-pass2/3`, `rd-on-video-pass2/3`, …) — secondary passes correctly excluded from the user-facing catalog.
- **The catalog is structurally healthy.** 0 duplicate IDs, 0 orphans. `generate_shader_lists.js` already computes and logs `skippedMultipassSecondaries` and `skippedDuplicates`; it just never asserts or exports them. The fix is far smaller than #1184 assumed.
- **Verified invariant:** `definitions − secondaries − duplicates == list entries == manifest total` → `1362 − 13 − 0 == 1349 == 1349`.
- **Gemini's file names were wrong:** the auditors are Python (`scripts/audit_extrabuffer.py`), not `audit-extrabuffer.mjs`.

**Design calls where the three reviews disagreed:**

- **README gate.** Kimi's churn objection wins on the *gate*; Gemini/Grok win on *generation*. Resolution: assert only the **derivable** invariant in CI — it needs no committed artifact, so it cannot red-build the daily generative PRs. `git diff --exit-code README.md` as a PR gate is explicitly rejected. The README drops to a rounded `1,300+`.
- **Alias map.** All three agree docs-only is useless. This issue ships the generated map (build-side); a named follow-up ships the runtime resolver, carrying Gemini's blast-radius list (share links, localStorage VJ stacks, FastAPI validation, WASM string identity).
- **Canonical count.** Definitions are the source of truth, manifest is derived — per Gemini and Grok, against Kimi.
- **Dynamic-index triage.** Machine-readable JSON the auditor consumes; unanimous.
- **Ajv schema validation** is included as an explicitly optional stretch, since it needs a devDependency the Copilot brief otherwise forbids.

## C. Three chat-model prompts targeting the issue from B

### C1 — Gemini Pro (codebase + issue → complete implementation plan)

```
I'm going to give you a GitHub issue from a React 19 + TypeScript codebase called
Pixelocity (a WebGPU shader playground for images and video). I want a complete
implementation plan, not a code dump.

Please:
1. Identify every file and function that must change, and every file that merely reads
   the affected state. I especially want dependencies I have missed — anything that
   reads the sidebar/chrome visibility state, anything that lays out the remote window,
   and anything in the host<->remote sync path that could be surprised by a new synced
   field.
2. Flag ordering hazards: which change must land before which, and what breaks if they
   land out of order.
3. Point out where the proposed approach duplicates something the codebase already does
   and should reuse instead. The issue notes the main app already solved the same
   problem — I want the remote to mirror that, not fork it.
4. Give me the failure modes a reviewer would catch: a user stranded in a chromeless
   window, state desync between host and remote, a CSS rule that leaks into the main app
   surface, a test that passes for the wrong reason.
5. Produce an ordered implementation plan with a verification step after each stage.

Relevant known context about the codebase:
  - `src/components/app/AppShell.tsx` already implements the main app's version:
    `chromeHidden = !showSidebar && activeTab === 'main'` suppresses the header, adds a
    `fullscreen` class to `.main-container`, and renders a `show-controls-overlay`
    button over the canvas.
  - `src/RemoteControlHeader.tsx` is a small presentational component with inline styles
    and no hide behaviour.
  - `src/hooks/useRemoteSync.ts` carries host<->remote state.
  - `src/style.css` holds the shared rules including `.show-controls-overlay`.
  - Tests are Jest via craco; the build is Create React App with CRACO.

Here is the issue:

[PASTE THE FULL ISSUE TEXT FROM SECTION B]
```

### C2 — Kimi.com (K2) (stress-test + alternatives)

```
Stress-test the approach in the GitHub issue below, then give me two genuine
alternatives and argue for the best one. Be adversarial about the proposed approach
before you offer replacements — I want the weaknesses named specifically, not
generically.

Context you need: this is a React 19 + TypeScript app with a main window and a separate
"remote control" window opened via `window.open('?mode=remote')`. The two share state
through a sync hook. The main window already implements exactly this hide-chrome
behaviour; the issue proposes mirroring it in the remote window.

Attack these points specifically:
  - The proposal says to mirror the main app's `chromeHidden` pattern. Is mirroring
    right, or does it duplicate logic that should be extracted into something shared?
    What is the actual cost of each choice at this codebase's size?
  - Where should the hidden state live — local component state, a URL parameter, or the
    host<->remote sync hook? Each has a different failure mode. Name them.
  - The proposal adds an overlay button so users can restore the chrome. Is an overlay
    button the right affordance for a small remote-control window, or is there something
    better (keyboard, edge hover, auto-hide on idle)?
  - Is moving inline styles to a global stylesheet an improvement here, or is it
    trading one problem for a specificity/collision problem across two window surfaces?

Then give me two alternative designs that are meaningfully different from the proposal
(not variations on it), evaluate all three against: implementation cost, risk of
breaking the main window, testability in Jest, and how it degrades if the sync channel
is unavailable. Recommend one and commit to the recommendation.

Here is the issue:

[PASTE THE FULL ISSUE TEXT FROM SECTION B]
```

### C3 — Grok.com (ecosystem currency check)

```
I want a current-ecosystem sanity check on an approach before I build it, so I don't
implement something that is already outdated.

The stack: React 19, TypeScript 4.9, Create React App with CRACO, Jest via craco test,
Playwright for browser automation, plain CSS in a shared stylesheet. The app renders
WebGPU compute shaders and has a secondary "remote control" browser window opened with
`window.open`, sharing state with the main window through a custom hook.

Questions:
1. React 19 specifically — is there anything in current React 19 practice that changes
   how I should manage a "chrome hidden" UI state shared across two browser windows?
   Anything that makes a custom sync hook the wrong call now?
2. Cross-window state sharing in 2026: what is the current default? BroadcastChannel,
   a shared worker, storage events, something else? Is a hand-rolled hook still
   reasonable, and what are its known sharp edges today?
3. TypeScript 4.9 is old. Is anything in this plan going to be materially easier or
   safer on TS 5.x, and is there a concrete reason this project should move? (Note: the
   project has explicitly decided to stay on CRA/CRACO and not migrate to Vite, so
   answer within that constraint.)
4. Fullscreen/chrome-hiding UI patterns for live-performance tools: has the accepted
   pattern moved on from an overlay "show controls" button? What do current
   VJ/performance tools do?
5. Anything about testing multi-window UI in current Jest/jsdom and Playwright that I
   should know before writing the tests?

Flag anything where my stated approach is already behind current practice, and say
plainly if the answer is "this is still fine, don't churn it."

Here is the issue describing what I plan to build:

[PASTE THE FULL ISSUE TEXT FROM SECTION B]
```

---

## D. Copilot Agent handoff

```
Implement GitHub issue #1195 in the Pixelocity repo (ford442/image_video_effects).

{{EXPANDED_ISSUE}}

Read the issue's "Corrections to the original premise" section first and take it literally. Two
plausible-sounding steps from the parent issue are no-ops and must NOT be implemented: whitelisting
multipass.graph parents (zero of the 33 ID/filename mismatches are graph parents), and renaming the
31 underscore filenames. The auditors are Python (scripts/audit_extrabuffer.py,
scripts/audit_dead_sliders.py) - there is no audit-extrabuffer.mjs.

Constraints — these are hard:

- Touch ONLY: scripts/, .github/workflows/, README.md, reports/, and package.json's scripts block.
- Do NOT touch: src/**, wasm_renderer/**, public/shaders/**, shader_definitions/**,
  shader_plans/**, storage_manager/**.
- Do NOT touch scripts/verify-device-policy-sync.js. Another change is actively extending it and
  you will collide.
- Do not rename any shader file or any shader ID. Aliases only.
- Do not add an npm dependency UNLESS Noah has approved the ajv devDependency for work package E.
  If he has not, skip E entirely rather than adding the dep.
- Do NOT add a CI step that fails on a stale committed artifact (no `git diff --exit-code README.md`
  gate). The count check must assert the derivable invariant only, so content PRs are never
  red-built by it. This is a hard design constraint, not a preference.

Verify before you open the PR:

  npm ci --ignore-scripts        # plain `npm ci` fails: the sharp postinstall is proxy-blocked
  SKIP_WASM_BUILD=1 npm run build
  npm run verify:shader-list-urls
  npm run verify:dependency-boundaries
  npm run audit:extrabuffer      # must still exit 0
  npm run audit:dead-sliders     # must still exit 0
  CI=true npx craco test --watchAll=false
  SKIP_WASM_BUILD=1 npm run build

Every acceptance criterion in the issue must be met, including the test coverage. If an
acceptance criterion turns out to be wrong or impossible, say so in the PR description
rather than silently dropping it.

{{EXPANDED_ISSUE}}
```

---

## E. Claude Code — whole-stack pipeline task

Independent of A and B. This exercises the pipeline described in the project's whole-stack definition: WebGPU client → FTP deploy to DreamHost → FastAPI backend on the VPS → CI.

```
Run a whole-stack pipeline hygiene pass on the Pixelocity repo (image_video_effects) and
report stage by stage with real command output. This is a verification pass — do not fix
anything unless it is trivially safe and clearly in scope, and say explicitly when you
decline to fix something and why.

Two findings from a prior pass are still open and are the priority of this run. Both were
deliberately left unfixed because they need a human decision; get them to the point where
that decision is a one-liner.

PRIORITY 1 — Storage Manager CORS (security-sensitive, unresolved since 2026-08-24).
  `storage_manager/config.py` `ALLOWED_ORIGINS` was found to (a) be missing the real
  production origin `noahcohn.com`, and (b) contain a `"*"` wildcard entry while
  `storage_manager/app.py` sets `allow_credentials=True`. Starlette's CORSMiddleware,
  when `"*"` is present alongside credentialed requests, reflects the caller's Origin
  header instead of emitting a literal `*` — which means any origin can make credentialed
  cross-site requests to this API.
  Verify whether this is still true in the current tree. If it is: do NOT silently change
  it. Instead produce (1) the exact diff you would apply, (2) the list of origins that
  actually need to be allowed, derived from evidence in the repo rather than guessed —
  check `storage_manager/app.py` for the `--base-url` value and any deploy scripts for
  the real frontend host, (3) a regression test asserting the allowlist is finite and
  contains no wildcard, and (4) a note on what breaks if an origin is missed.

PRIORITY 2 — the WASM artifact/source sync boundary.
  `public/wasm/pixelocity_wasm.{js,wasm}` were rebuilt with emcc 6.0.3 and committed
  alongside their C++ sources. Most agent VMs have emcc 3.1.56 with no emdawnwebgpu port
  and cannot rebuild them, so a C++ edit would desync the shipped artifact from its
  source. `npm run wasm:validate` currently passes.
  Determine whether that validation would actually CATCH a desync, or whether it only
  checks the bridge JS files and artifact well-formedness. If it would not catch a C++
  source change that was never rebuilt, that is a real gap — propose the cheapest gate
  that would (a recorded source hash, a build-stamp comparison, whatever fits the
  existing script), but do not implement it without saying what it costs.

Then run the standard stages and report each with actual output:

  1. INSTALL — `npm ci --ignore-scripts` (plain `npm ci` is blocked by the sharp
     postinstall behind the proxy; note if that is still true).
  2. TYPECHECK + TEST — `npx tsc --noEmit`; `CI=true npx craco test --watchAll=false`.
     Report the suite/test counts as numbers.
  3. BUILD — `SKIP_WASM_BUILD=1 npm run build`. Report the gzipped main.js size and the
     lazy chunk sizes.
  4. SHADER LISTS — `node scripts/generate_shader_lists.js`; confirm it is deterministic
     (zero git diff against committed output) and duplicate-id clean.
  5. DEPLOY DRY-RUN — compute the manifest diff LOCALLY with zero network calls. Confirm
     the deploy credential path still reads from env / .env.deploy / prompt with no
     hardcoded secrets. Make no connection to DreamHost.
  6. BACKEND — `python -m pytest storage_manager/tests/ -q` FROM THE REPO ROOT (the tests
     import `storage_manager.app`, which only resolves with the repo root on sys.path).
  7. DEPENDENCY AUDIT — `npm audit --production`. The known chain is @xenova/transformers
     for depth estimation; report whether the CVE set has shifted again and whether any
     fix has become available. Do not auto-fix.
  8. VERIFY GATES — `verify:device-policy`, `verify:uniforms`, `verify:dependency-boundaries`,
     `verify:catalog-counts`, `wasm:validate`, `audit:extrabuffer`, `audit:dead-sliders`.
     Current baselines to compare against: extrabuffer 0 new / 84 known / 32 dynamic-index;
     dead-sliders 1201 scanned / 0 new / 26 known.

For each stage give a PASS/FAIL verdict and the evidence. Where a check cannot run in this
environment, say so plainly and label it UNVERIFIED rather than assuming it passes. End
with a single verdict line: pipeline healthy, or N issues found with severity.
```

---

## F. Jules wrap-up — integrate kimi-cli's output (fill placeholders at end of day)

```
You are wrapping up and integrating work that another agent (kimi-cli) produced today in
the Pixelocity repo (image_video_effects): React 19 + TypeScript 4.9, Create React App
with CRACO, Jest, Playwright, and a C++/WASM renderer backend.

## What was being built

The objective was to make six real-GPU bugs found on 2026-08-30/31 un-regressable. The
bugs were already fixed in the tree; the work was to add machine-checked invariants that
prevent regression, clamp all gpu-chores compute dispatches against the device limit, add
a `?renderer=wasm` boot smoke test, and produce a promotion-evidence report.

Files changed by kimi-cli:
{{KIMI_CLI_FILES_CHANGED}}

What kimi-cli did:
{{KIMI_CLI_SUMMARY}}

Issues I noticed on a cursory review:
{{KNOWN_ISSUES}}

## Hard constraint — read this before touching anything

There must be ZERO changes under `wasm_renderer/` and `public/wasm/`. Those artifacts
were built with emcc 6.0.3 and cannot be rebuilt in this environment (emcc 3.1.56, no
emdawnwebgpu port). If the diff contains changes there, STOP and report it rather than
trying to rebuild — a desynced .wasm is worse than an unfinished PR.

Also do not weaken any existing check in `scripts/verify-device-policy-sync.js`. Its
limits / optional-features / wasm_exports / workgroup_dispatch / emptyPlaceholder
assertions were green before today and must be green after.

## Wrap-up checklist

1. Read the full diff before changing anything. Note anything that looks unfinished,
   stubbed, or inconsistent with the objective above.
2. Run the formatter across changed files.
3. Run the linter. Fix real problems; leave pre-existing unrelated noise alone.
4. Run the tests: `CI=true npx craco test --watchAll=false`. Fix every failure. Do not
   skip, disable, or quarantine a test to get green — if a test is wrong, fix the test
   and say why in the PR.
5. Complete any TODOs or stubs kimi-cli left behind. If a stub cannot be completed
   without a decision I need to make, leave it and list it in the PR description.
6. Add unit tests for any new exported function that lacks coverage — in particular the
   dispatch-limit helper and the .wasm import-table parser, both of which are pure and
   easy to test properly.
7. **Verify the new guards actually bite.** For each invariant added, temporarily
   reintroduce the regression it guards against, confirm the check FAILS, then revert. A
   check that passes both with and without the regression is broken. Report the result
   of each of these probes in the PR description — this is the single most important
   thing in this wrap-up, because the entire value of today's work is that these gates
   are real.
8. Check `reports/wasm_promotion_evidence.md` for honesty: nothing may be marked
   GPU-CONFIRMED that was only verified headlessly. Downgrade any overclaim to
   GPU-PENDING.
9. Update inline docs and `docs/WASM_RUNTIME_INVARIANTS.md` / `docs/GPU_CHORES.md` if the
   public surface changed. Update README only if a documented command changed.
10. Run the full gate set and confirm green.

## Commands for this stack

  npm ci --ignore-scripts                     # plain `npm ci` is blocked by sharp's postinstall
  npx tsc --noEmit
  CI=true npx craco test --watchAll=false
  SKIP_WASM_BUILD=1 npm run build
  npm run verify:device-policy
  npm run verify:wasm-invariants              # the new gate, if it landed
  npm run wasm:validate
  npm run verify:uniforms
  npm run verify:dependency-boundaries
  npm run audit:extrabuffer                   # baseline: 0 new / 84 known
  npm run audit:dead-sliders                  # baseline: 0 new / 26 known
  npx playwright test                         # GPU specs should SKIP, not fail, without an adapter

## Acceptance criteria

  - [ ] Formatter and linter clean on changed files
  - [ ] `npx tsc --noEmit` clean
  - [ ] Full Jest suite green; suite/test counts reported as numbers in the PR
  - [ ] `SKIP_WASM_BUILD=1 npm run build` prints "Compiled successfully"
  - [ ] Every verify and audit gate above green, at or better than the stated baselines
  - [ ] Playwright GPU specs skip cleanly without an adapter (skip, never false-pass)
  - [ ] Zero changes under `wasm_renderer/` and `public/wasm/`
  - [ ] No existing check in `verify-device-policy-sync.js` weakened
  - [ ] Every new exported function has unit test coverage
  - [ ] Each new guard proven to fail on a reintroduced regression, with results in the PR
  - [ ] No TODO or stub left unlisted
  - [ ] `reports/wasm_promotion_evidence.md` contains no unearned GPU-CONFIRMED flags

## Output

Open a pull request for me to review. Do NOT merge it. In the description: what changed
and why, the test/suite counts, the result of every gate, the guard bite-proofs from
step 7, and an explicit list of anything you could not finish or chose not to do.
```

---

## G. Review prompts

### G1 — Gemini Pro: review the kimi-cli diff before Jules wraps it

```
Review this diff for performance problems and architectural drift. It is from a React 19
+ TypeScript WebGPU application. Be specific and skip praise.

The diff's stated objective: take six runtime bugs that were already fixed in the tree
and make them un-regressable, by adding a JSON contract file validated against the
TypeScript and C++ sources by an existing verification script, clamping all compute
dispatches against the device's maxComputeWorkgroupsPerDimension limit, adding a browser
boot smoke test, and writing a promotion-evidence report.

Assess:

1. **Do the guards actually guard?** For each check added, could it pass while the
   regression it targets is present? Look hard at anything grep- or regex-based against
   source files — those are easy to write and easy to fool. The .wasm import-table parser
   in particular: is it parsing the binary format correctly, and does it fail closed if
   the file is malformed or the section is absent?

2. **Per-frame cost.** The dispatch clamp runs on paths executed every frame. Does the
   diff add per-frame allocation, per-frame limit lookups that should be hoisted, or
   anything that turns a hot loop into a slower one? The correct implementation caches
   limits once at attach time.

3. **Architectural drift.** This repo has an established contract pattern:
   `src/contracts/*.json` validated by `scripts/verify-device-policy-sync.js`. Does this
   diff follow it, or does it introduce a parallel mechanism that will need maintaining
   separately? Flag any near-duplicate of existing logic.

4. **Boundary violations.** There must be zero changes under `wasm_renderer/` or
   `public/wasm/`, and no existing assertion in the verification script may be weakened,
   loosened, or made conditional. Check for subtle versions of this — a check that still
   runs but now skips on a condition that is usually true is a weakened check.

5. **Test quality.** Do the new tests fail if the implementation is wrong, or do they
   assert on the mock? Does the Playwright spec skip when no adapter is available rather
   than silently passing?

For each finding: file and line, why it is wrong, what breaks in practice, and the
smallest correct fix. Rank by severity and be honest if the diff is basically sound.
```

### G2 — Gemini Pro: review the Jules PR against the original objective

```
Review this pull request against the objective it was supposed to fulfil and the wrap-up
checklist it was supposed to complete. I want gaps, not a summary.

ORIGINAL OBJECTIVE: six real-GPU bugs (a compute dispatch exceeding the device's
workgroups-per-dimension limit; a browser-unsupported present call that aborted the WASM
module; samplers created with maxAnisotropy=0 which Dawn rejects; a history-texture
out-of-memory failure needing a size-ladder fallback; a pipeline/shader storage-format
mismatch; and lost image input after a renderer backend switch) were ALREADY fixed in the
tree but had no automated protection. The work was to encode each root cause as a
machine-checked invariant, clamp every compute dispatch site, add a WASM-renderer boot
smoke test, and produce an honest promotion-evidence report.

WRAP-UP CHECKLIST that should have been completed: formatter, linter, full test suite
green with counts reported, all TODOs and stubs resolved or explicitly listed, unit tests
for every new exported function, docs updated, full build passing, every verify and audit
gate green, zero changes under the C++/WASM directories, and — most importantly — a
recorded proof for each new guard that it FAILS when its regression is reintroduced.

Check specifically:

1. Is any of the six root causes missing an invariant, or covered only by a weak check?
2. Are the guard bite-proofs actually present in the PR description, with results — or
   was that step quietly skipped? This is the highest-value item; treat its absence as a
   blocking finding, because a guard nobody proved can fail is indistinguishable from no
   guard.
3. Does the evidence report mark anything as hardware-confirmed that could only have been
   verified headlessly? Any such claim is a defect.
4. Were any tests skipped, disabled, weakened, or given loosened assertions to reach
   green? Compare assertion strength before and after, not just pass/fail.
5. Are the reported test counts consistent with the number of tests added?
6. Any changes under the C++/WASM directories at all?
7. Anything listed as "could not finish" that is actually load-bearing for the objective?

Give me a merge / do-not-merge recommendation with the specific blocking items, then the
non-blocking nits separately.
```

---

## Suggested timeline

| Offset | Action |
| --- | --- |
| **T+0:00** | Fire **B → Copilot** first. #1201's remote half is small, entirely decoupled, and gets a head start while you set up. Then launch **A (kimi-cli)** — it is the long-horizon job and should be running before anything else competes for your attention. |
| **T+0:15** | Kickoff done. kimi-cli is on iteration 0 re-establishing the test baseline. |
| **T+0:30 – T+2:00** | Expansion window. Run **C1/C2/C3** against the issue from B, fold the answers into the expanded issue, hand it to **D**. Check kimi's iteration-0 save-state: if it did not record real baseline numbers, correct that now — everything downstream compares against it. |
| **T+2:00 – T+4:00** | Mid-day. Run **E** (whole-stack hygiene). The CORS finding has been open since 08-24 and this run is meant to end with a one-line decision for you, so read that section properly rather than skimming the verdict. |
| **T+4:00 – T+6:00** | kimi-cli's tail. The bite-proofs (temporarily reintroducing each regression to confirm the gate fails) are the part most likely to be skipped under time pressure — check `.swarm-state.md` for them specifically. |
| **T+6:00** | Run **G1** on the final kimi-cli diff before wrapping. |
| **T+6:30** | Fill the three placeholders in **F** and hand it to Jules. |
| **T+7:30** | Run **G2** on the Jules PR. Review and merge if clean. |
| **End of day** | Update the `Outcome:` line in `weekly_plan.md`'s Last run section. Decide on PR #1219 (last week's routine branch, still open) and PR #1221 (this week's). |

## Open questions

1. **The six issues' real-GPU status is unknown to this run.** All six fixes are verified present in source; none is verified working on hardware. Only you can close that loop, and only on the Pascal/Chrome host. Today's evidence report is written to make that session short, not to replace it.
2. **Does the `go.1ink.us` promote hold lift after real-GPU confirmation, or is something else gating it?** #1200 says "HOLD go.1ink.us /pixelocity/ (100%)" and #1201 adds "no remote on public build" — it is not clear from the issues whether those are one hold or two.
3. **#848 (emscripten toolchain) is now load-bearing.** Until agent environments can build with emcc 6.0.3 + emdawnwebgpu, all C++ work is yours alone, and every routine track has to route around `wasm_renderer/`. That is a real constraint on how much of this project the weekly loop can reach.
4. **Jest baseline is carried, not measured** (84 suites / 550 passed / 1 skipped, from `.swarm-state.md`). `node_modules` is absent on the routine's VM. kimi re-establishes it on iteration 0; treat any comparison against the carried number as approximate until then.
5. **PR #1219** (`claude/nice-bardeen-50zdxv`, non-draft) is last week's routine branch and is still open. This week's branch was cut fresh from `main` rather than stacked on it, so #1219 needs a merge-or-close decision from you.
