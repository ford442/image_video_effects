# image_video_effects — 2026-08-08 dispatch

**Status:** #1038 (Uniforms SoT) shipped + merged last week; today = **#1079 god-module strangler** (RendererManager 986 LOC + StoragePanel 737 LOC). Plan updated, PR #1090 open.

## Mode declaration

**User Idea mode.** Noah's fresh **2026-08-07 progress audit** (epic #1076 + children #1077–#1084) is the strongest in-context signal and the live Ideas source; it supersedes the 08-01 #1038–#1044 set. Picked **#1079** — the highest-leverage, non-GPU-blocked, headless-self-verifiable item. Foundation is healthy (#1038 landed clean) → **not Fix First**.

## Context from prior sessions

- **Last week's focus #1038 (Uniforms SoT) SHIPPED + MERGED.** Verified in tree: `src/contracts/uniforms_layout.json` present; `docs/BINDING_CONTRACT.md:61/73/91` + `agents/WGSL_BUILTINS_GENERATIVE.md:31` now say `config.y = rippleCount`; `npm run verify:uniforms` + `audit:config-y` scripts landed. Commits `639cd31` (#1055) + `67a8eb7` (#1056).
- **New live backlog:** Noah ran a 2026-08-07 progress audit (`memory/2026-08-07.md`) → epic **#1076** + **#1077–#1084**. Strategic call: *interleave foundation residual with content; prefer multipass excellence + discoverability over volume; stay CRA/CRACO; no GraphRunner C++ port until the WASM decision.*
- **Two residual god modules confirmed by `wc -l`:** `RendererManager.ts` = **986 LOC**, `StoragePanel.tsx` = **737 LOC** — exactly the #1079 targets.
- **Content stream runs autonomously in parallel** (Jules + generative swarm): `.swarm-state.md` = updatedParams campaign complete through tracker #355 / Batch 39 (2026-08-06); ~100 single-pass generatives still queued (#1084); merges #1085–#1088; open draft PR #1089. Decoupled from today's `src/` refactor.
- **Branch `claude/charming-lamport-k5052x`** even with `origin/main` `f65a351` (0/0 after fetch).

**Context gaps (flagged, not hidden):**
- `recent_chats` / `conversation_search` **UNAVAILABLE** in this headless scheduled run — context reconstructed from repo tree, `weekly_plan.md`, `.swarm-state.md`, `memory/2026-08-07.md`, and GitHub issues/PRs.
- **Jest count UNVERIFIED on-VM** — `node_modules` absent, `npm ci` blocked by the `sharp` postinstall (existing backlog item). kimi must establish the Jest baseline on iteration 0.
- **No GPU adapter on the Cloud VM** → thumbnails (#1078), WASM promotion (#1080), and multipass visual QA (#1081) are all GPU-blocked and deliberately not today's pick.

## weekly_plan.md changes (committed — PR #1090)

- **Today's focus** rewritten to #1079; the 08-01 #1038 focus archived in a `<details>` block marked DONE.
- **Ideas:** #1038 marked `[x] DONE 2026-08-08`; old #1042/#1043 marked renumbered/subsumed; 2026-08-07 audit seeded as the live Ideas source; **#1079 marked `[in progress — 2026-08-08]`**; #1081/#1082/#1083 non-picks appended.
- **Backlog:** #1038–#1044 set marked superseded (with forward-mapping); #1076–#1084 added as the live backlog; a note added that the content stream (Jules/swarm) is churning `public/shaders/**` and is out of the refactor's scope.
- **Done:** 2026-08-08 entry for #1038.
- **Last run:** overwritten with this run's summary; stale duplicate Focus/Outcome pair removed.

## Today's focus

**#1079 — Residual god-module strangler** (epic #1076). Modularize the two modules that survived Foundation Wave 2 and now tax every new renderer/backend feature:
- `src/renderer/RendererManager.ts` (**986 LOC**: backend switch, slots, quality, input, recording glue) → extract `backendLifecycle` / `slotOrchestration` / `inputSourceBridge` / `performanceStatus` seams with Jest tests; keep a thin facade ≤~350 LOC implementing `IRenderer` + the app API.
- `src/components/storage/StoragePanel.tsx` (**737 LOC**: UI + API + ratings) → split list/browser, detail, ratings, upload into `src/components/storage/panels/`; keep `StorageClient` as the sole network SoT.

**Why this pick:** highest-leverage item in the 08-07 audit that is **non-GPU-blocked and fully self-verifiable headless** (Jest + `npm run build` + `verify:dependency-boundaries` — no adapter needed). It's the same strangler pattern kimi executed for the WebGPU split (#967) and App/Controls Wave 3 (#938). Content generation is already flowing autonomously, so a foundation-residual pick complements rather than competes.

---

# Dispatch

## A. kimi-cli Swarm Task — the main event

```
OBJECTIVE
Strangler-refactor the two residual "god modules" in the Pixelocity (image_video_effects)
WebGPU app so they stop taxing every new renderer/backend feature. This is GitHub issue
#1079 under epic #1076. Two targets:

  1. src/renderer/RendererManager.ts   (~986 LOC: backend switch, slots, quality, input,
                                         recording glue)
  2. src/components/storage/StoragePanel.tsx (~737 LOC: UI + API + ratings)

WHY
Foundation Wave 2 already modularized WebGPURenderer (device/resources/pipeline/frame/
present/slotDispatch) and the App shell. These two modules were left behind and are now the
densest remaining files. Every backend-switch, slot, recording, or storage-UI change pays
interest on them. Mirror the proven WebGPU-split philosophy: extract PURE seams behind a thin
facade, each unit-tested, with zero behavior change.

SCOPE — ALLOWED TO TOUCH
- src/renderer/RendererManager.ts and NEW sibling seam modules:
    backendLifecycle.ts   (create/destroy TS vs WASM, ?renderer= query parsing)
    slotOrchestration.ts  (enable / mode / params forwarding across slots)
    inputSourceBridge.ts  (image / video / webcam / depth handoff)
    performanceStatus.ts  (format tier / FP32 pin / pass-budget surface)
  Keep RendererManager as a thin facade (target <=~350 LOC) implementing IRenderer + the app API.
- src/components/storage/StoragePanel.tsx and NEW src/components/storage/panels/*
  (split list/browser, detail, ratings, upload). Keep StorageClient as the SOLE network SoT.
- Colocated *.test.ts / *.test.tsx for every new module.
- docs/STORAGE_API.md ONLY if you clarify the StorageClient boundary (no API changes).

SCOPE — DO NOT TOUCH (hard boundaries)
- src/renderer/webgpu/** engine internals — READ-ONLY reference for the split shape; do NOT
  re-modularize what Wave 2 already split.
- src/renderer/UniformBuffer.ts — immutable uniform packing.
- wasm_renderer/** and src/wasm/wasm_bridge.js — #1063 owns that concat; keep decoupled.
- public/shaders/** and shader_definitions/** — content track is churning in parallel (Jules
  generative swarm); a refactor edit there WILL collide. Ignore entirely.
- scripts/, .github/workflows/**, prestart/prebuild shader-list generation — that is today's
  SEPARATE Copilot track (#1077 base-url drift). Ignore entirely.
- storage_manager/** Python backend.

CONTRACTS TO PRESERVE (regressions here are failures, not style nits)
- Feedback copy order stays: dataB -> dataC, THEN dataA -> dataC.
- WASM stays opt-in Tier B with NO auto-fallback to TS.
- Duck-typed / forwarded WASM methods must not regress (issue #887).
- Do NOT rename any public IRenderer or app-API method; the facade keeps the same surface.
- The new seam modules must not import "upward" into src/components or src/App.

ITERATION LOOP (repeat; small, verifiable steps)
0. BASELINE FIRST. Before touching anything:
   - `npx tsc --noEmit` clean; record any pre-existing errors.
   - `CI=true npx craco test --watchAll=false` — record the suite/test count (this is your
     regression baseline; node_modules may need `npm ci --ignore-scripts` first because the
     `sharp` postinstall is blocked behind the proxy).
   - `npm run build` — confirm "Compiled successfully".
1. Extract ONE seam at a time (start with the lowest-risk pure one, e.g. performanceStatus).
2. After each extraction:
   - `npx tsc --noEmit` clean.
   - `CI=true npx craco test --watchAll=false` — test count must not drop; add unit tests for
     the new module (backend-switch + slot-param forwarding are the must-cover paths).
   - `npm run build` compiles.
   - `npm run verify:dependency-boundaries` green (no upward imports).
3. Only after the seam is green and tested, move to the next.

ACCEPTANCE TARGETS
- RendererManager.ts facade <=~350 LOC.
- StoragePanel.tsx <=~400 LOC, or clearly panel-composed.
- New seam modules unit-tested (backend switch + slot param forwarding covered).
- Zero behavior change in Controls -> renderer-switcher and recording smoke paths.
- eslint noise is NON-gating — judge pass/fail on tsc + Jest + build only.

SAVE-STATE
At every iteration boundary, append progress to .swarm-state.md: which seam you extracted,
new LOC of the facade, test count before/after, contracts re-verified, and the next seam.
So Noah can pause/resume cleanly.
```

## B. GitHub issue — draft it now (Copilot prep, decoupled from A)

> Fully decoupled from kimi's `src/renderer/**` + `src/components/storage/**` refactor. This one lives in build scripts / prestart / shader-list generation. Builds on the audit's #1077.

```
TITLE
Fix catalog `--base-url` hardcode drift + prestart/prebuild hygiene (env-toggle local vs test CDN)

CONTEXT / MOTIVATION
Per the 2026-08-07 progress audit (epic #1076, item 1; success criterion:
"prestart/prebuild do not force absolute test CDN URLs into local lists without env toggle"),
the shader-list generation path bakes an absolute test-CDN `--base-url`
(e.g. https://test.1ink.us/image_video_effects) into the generated public/shader-lists/*.json.
That is correct for the deployed build but wrong for local dev and for anyone cloning fresh —
local runs then reach for a remote CDN for assets that exist on disk. This is a foundation-
hygiene multiplier: every shader added inherits the drift. Active focus areas this touches:
maintaining the shader catalog / list-generation pipeline and the deploy path.

PROPOSED APPROACH (first pass — Noah/Copilot will expand)
1. Locate the base-url injection: the prestart/prebuild npm scripts and the list generator
   (likely `scripts/generate_shader_lists.js` + the `prestart`/`prebuild` hooks in package.json).
2. Introduce a single env toggle (e.g. SHADER_BASE_URL) with a sane LOCAL default (relative /
   same-origin) and the deploy value supplied explicitly by deploy.py / CI.
3. Make the local default produce relative or same-origin URLs so `npm start` needs no network
   for on-disk shaders; deploy/CI keeps the absolute test/prod CDN.
4. Add a lightweight drift guard: a `verify:*` script (or a check folded into an existing
   verify) that fails if committed shader-lists contain a hardcoded absolute test-CDN host when
   they should be relative — closing the forward-only coverage gap.
5. Document the toggle in the relevant README / deploy notes.

ACCEPTANCE CRITERIA (rough — to be refined)
- [ ] `npm start` / `npm run build` locally produce shader-lists with relative/same-origin URLs
      by default (no absolute test-CDN host baked in).
- [ ] Deploy/CI path still emits the correct absolute base-url via explicit env, unchanged output.
- [ ] A drift check fails CI if a hardcoded test-CDN base-url leaks into committed lists.
- [ ] No change to shader content, renderer, or storage code.

OPEN QUESTIONS FOR NOAH
- Exact env var name + precedence (CLI flag > env > default?).
- Is the deployed value sourced from deploy.py, CI secret, or a committed config today?
- Should the drift check be a new `verify:base-url` or folded into `verify:dependency-boundaries`?
- Any consumers that currently RELY on the absolute URL in local builds (thumbnail tooling?)?

SCOPE GUARD
scripts/ + package.json prestart/prebuild hooks + public/shader-lists generation + docs only.
Do NOT touch src/renderer/**, src/components/storage/** (active refactor #1079), or
public/shaders/*.wgsl content.
```

## C. Three chat-model prompts targeting the issue from B

### Gemini Pro — affected files + dependency map + full plan

```
You are reviewing a React 19 + TypeScript (Create React App / CRACO) WebGPU shader-playground
repo (Pixelocity / image_video_effects). Frontend deploys via a Python SFTP script (deploy.py)
to DreamHost; a FastAPI backend serves shader/media storage. Below is a GitHub issue. Read the
codebase and produce a COMPLETE implementation plan.

Specifically:
1. Identify every file and function involved in generating public/shader-lists/*.json and where
   the absolute `--base-url` is injected (prestart/prebuild hooks, the list generator script,
   any config module).
2. Trace consumers of the base-url in the generated lists — who reads these URLs at runtime
   (shader browser, thumbnail tooling, ratings client) and whether relative/same-origin URLs
   would break any of them.
3. Spot missed dependencies: deploy.py's base-url arg, CI workflow steps, any committed config
   that pins the host, and any test that asserts the absolute URL.
4. Produce a step-by-step plan with the exact env-var design (name, precedence, defaults) and a
   concrete drift-check implementation, plus a rollback note.

--- ISSUE ---
[paste the full text of issue B here]
```

### Kimi.com (K2) — stress-test + alternatives

```
Here is a GitHub issue for a CRA/CRACO + TypeScript WebGPU app (Pixelocity). Stress-test the
proposed approach, then generate two ALTERNATIVE approaches and argue for the best.

Pressure points to attack:
- Is an env toggle (SHADER_BASE_URL) the right seam, or should base-url resolution move to
  runtime (resolve relative at load) instead of build-time injection?
- Failure modes: fresh clone with no env set; deploy that forgets to set it; a mixed cache of
  lists generated under different base-urls.
- The drift check: false positives/negatives, and whether "committed lists must be relative"
  is even the right invariant vs "lists must be reproducible from env".

Then give exactly two alternatives (e.g. (a) build-time env injection with a drift gate,
(b) runtime relative-URL resolution that removes base-url from committed lists entirely), with
a decision and the migration cost of each.

--- ISSUE ---
[paste the full text of issue B here]
```

### Grok.com — ecosystem currency check

```
Context: a 2026-era React 19 + TypeScript 4.9 app on Create React App with CRACO, WebGPU
(WGSL compute shaders), @xenova/transformers and @mlc-ai/web-llm lazy-loaded, deployed static
via SFTP to shared hosting, FastAPI backend. The team is deliberately staying on CRA/CRACO (no
Vite migration right now). Below is a GitHub issue about base-url handling in a build-time
asset-list generator.

Tell me what current ecosystem practice says so this approach isn't already outdated:
- In 2026, how do CRA/CRACO (and static-host) projects typically handle base-URL / public-path
  for generated asset manifests — PUBLIC_URL, import.meta-style, relative-by-default? Any known
  footguns with same-origin vs absolute CDN URLs under COOP/COEP (this app uses cross-origin
  isolation for WASM)?
- Is there a standard, low-dependency pattern for "env-driven base URL with a committed-drift
  guard" I should copy rather than invent?
- Anything about serving on-disk shader assets same-origin that interacts badly with WebGPU
  fetch / CORS in current Chrome?

--- ISSUE ---
[paste the full text of issue B here]
```

## D. Copilot Agent handoff

```
Implement the following GitHub issue for the Pixelocity (image_video_effects) repo. It is
scoped to build tooling only — do NOT touch src/renderer/** or src/components/storage/** (both
under an active refactor, #1079), and do NOT touch public/shaders/*.wgsl content.

Work strictly within the acceptance criteria. Keep the deploy/CI absolute base-url path
unchanged; only add the env toggle + local default + drift guard. Add or update tests. Run the
project's verify scripts and `npm run build` before opening the PR.

{{EXPANDED_ISSUE}}
```

## E. Claude Code whole-stack task (mid-day, independent of A)

> Whole-stack meaning for this project = "high-performance WebGPU client deployed via FTP to DreamHost, talking to a FastAPI storage backend." Pipeline-hygiene exercise, not integration with kimi's work.

```
Whole-stack pipeline-hygiene pass for image_video_effects. Exercise the full path client ->
build -> deploy artifact -> storage backend, report a green/red table, fix only what is safe
and in-scope. Do NOT touch the #1079 refactor files (src/renderer/**, src/components/storage/**)
or generative content.

Stages:
1. INSTALL: `npm ci --ignore-scripts` (the `sharp` postinstall is blocked behind the proxy;
   note if a plain `npm ci` still fails — that's a tracked backlog item). Confirm typescript
   resolves.
2. BUILD: `npm run build` — confirm "Compiled successfully"; capture the main.js gzip size and
   compare against the ~2.7 MB backlog warning (flag if it grew). Run `npm run verify:bundle-size`.
3. TEST BASELINE: `CI=true npx craco test --watchAll=false` — record suite/test count and any
   failures (this also establishes the number kimi's #1079 work must not regress). If
   CommunityGallery.test.tsx is red, diagnose (`useThumbnailManifest` fetch-mock) and fix if trivial.
4. SHADER PIPELINE: `npm run sync:shaders:dry` — report orphan/missing-WGSL drift count; do not
   upload. `npm run verify:uniforms` + `npm run audit:config-y` (the #1038 SoT gates) — confirm green.
5. DEPLOY DRY-CHECK: static-analyze deploy.py / deploy_app_only.py for correctness (env-based
   DEPLOY_PASS, base-url arg) WITHOUT running an actual SFTP push. Confirm no plaintext creds.
6. BACKEND: `cd storage_manager && python -m pytest tests/ -q` if runnable; else AST/lint-check
   app.py and confirm CORS allowlist + STORAGE_API base are intact.

Output: one status table (stage / green|red / evidence / action taken). Fix only trivial,
in-scope items; log anything larger to weekly_plan.md Backlog. Ignore the pre-existing
`wasm_renderer/build.sh --use-port=emdawnwebgpu` failure (#848).
```

## F. Jules wrap-up task — integrate kimi-cli's output (end-of-day template)

```
Wrap up and integrate the kimi-cli #1079 refactor into a reviewable PR for image_video_effects.
Do NOT merge — open the PR for Noah to review.

WHAT KIMI-CLI DID
Files changed: {{KIMI_CLI_FILES_CHANGED}}
Summary: {{KIMI_CLI_SUMMARY}}
Known issues from Noah's cursory review: {{KNOWN_ISSUES}}

This was a strangler refactor of src/renderer/RendererManager.ts (~986 LOC) into
backendLifecycle / slotOrchestration / inputSourceBridge / performanceStatus seams behind a thin
facade, plus splitting src/components/storage/StoragePanel.tsx (~737 LOC) into
src/components/storage/panels/*. Contracts that MUST still hold: feedback copy order
(dataB->dataC then dataA->dataC), WASM opt-in Tier B with no auto-fallback, no regressed
duck-typed WASM methods (#887), no renamed public IRenderer/app-API methods.

WRAP-UP CHECKLIST
- [ ] Formatter: run the repo formatter (prettier via `npx prettier -w` on changed files if
      configured; otherwise skip and note it).
- [ ] Linter: `npx eslint` on changed files — fix real errors; eslint noise is non-gating.
- [ ] Tests: `CI=true npx craco test --watchAll=false` (use `npm ci --ignore-scripts` if
      node_modules is cold). Fix any failures.
- [ ] Complete any TODO/stub kimi left behind in the new seam modules.
- [ ] Add unit tests for any new public function lacking coverage — especially backend-switch
      and slot-param forwarding.
- [ ] Update inline docs / docs/STORAGE_API.md / any renderer README if a public API surface
      changed (it should NOT have — flag if it did).
- [ ] Build: `npm run build` -> "Compiled successfully".
- [ ] `npm run verify:dependency-boundaries` green (no upward imports from the new modules).
- [ ] Confirm LOC targets: RendererManager.ts <=~350, StoragePanel.tsx <=~400 (or panel-composed).

ACCEPTANCE
- [ ] tsc clean, Jest green (count >= the pre-refactor baseline), build compiles.
- [ ] Preserved contracts verified (feedback order, WASM Tier-B, #887 methods, no renamed APIs).
- [ ] New modules unit-tested; facade + StoragePanel within LOC targets.
- [ ] Zero behavior change in Controls renderer-switcher / recording smoke paths.

Open a PR titled "refactor(renderer): strangler-split RendererManager + StoragePanel (#1079)".
DO NOT MERGE — leave it for Noah's review.
```

## G. Review prompts (Gemini Pro)

### G1 — analyze the raw kimi-cli diff (before Jules wraps)

```
Review this diff from a TypeScript WebGPU app (Pixelocity). It strangler-refactors
RendererManager.ts (~986 LOC) into backendLifecycle / slotOrchestration / inputSourceBridge /
performanceStatus seams behind a facade, and splits StoragePanel.tsx into panels/. Focus on:
- Performance bottlenecks introduced by the split: extra indirection on the hot per-frame path
  (slot dispatch, feedback copy), new allocations, or lost inlining in the render loop.
- Architectural drift: did the facade leak internals? Are the new seams truly pure, or do they
  reach back into RendererManager state? Any upward imports into src/components / src/App?
- Contract preservation: feedback copy order (dataB->dataC then dataA->dataC), WASM opt-in
  Tier B with no auto-fallback, duck-typed WASM methods (#887), no renamed public API.
Give a prioritized list of concrete concerns with file:line references.

--- DIFF ---
[paste the kimi-cli diff here]
```

### G2 — review the Jules PR vs objective + checklist

```
Review this PR for image_video_effects against BOTH (a) the original #1079 objective and (b) the
wrap-up checklist below. The objective: modularize RendererManager (facade <=~350 LOC) +
StoragePanel (<=~400 LOC) into tested seams with ZERO behavior change, preserving feedback copy
order, WASM Tier-B no-auto-fallback, and #887 duck-typed methods.

Check and report pass/fail with evidence:
- LOC targets actually met (facade, StoragePanel)?
- New seam modules unit-tested for backend-switch + slot-param forwarding?
- Jest count >= pre-refactor baseline; build green; dependency-boundaries green?
- Any renamed public API or changed Controls/recording behavior (should be none)?
- Contracts preserved (feedback order, WASM Tier-B, #887)?
- Docs updated only if a public surface changed?
Flag anything the checklist missed and give a merge / request-changes recommendation.

--- PR ---
[paste the PR diff / link contents here]
```

---

## Suggested timeline

- **T+0 (kickoff, 15 min):** launch **A** (kimi-cli #1079 swarm); file **B** (base-url drift issue) on GitHub.
- **T+0:15 → T+1:30 (expansion, while kimi runs):** run **C** (Gemini/Kimi/Grok) on issue B; assemble the expanded issue; hand off via **D** (Copilot).
- **Mid-day:** run **E** (Claude Code whole-stack hygiene) — independent; also establishes the Jest baseline that #1079 must not regress.
- **End-of-day (after kimi finishes):** fill placeholders and run **F** (Jules integration → PR, no merge).
- **Review loop:** **G1** on the raw kimi diff before Jules; **G2** on the Jules PR.

## Open questions

- **Jest baseline count** couldn't be captured on the Cloud VM (`node_modules` absent, `npm ci` blocked by `sharp`). kimi/Claude Code must establish it on iteration 0.
- **StoragePanel path** — `src/components/storage/StoragePanel.tsx` confirmed at 737 LOC, but the exact current panel/child structure (and whether `StorageClient` already exists as a discrete module) wasn't deep-read; kimi should confirm before splitting.
- **#1089 (draft, Jules generative)** is open on `public/shaders/**` — harmless to the #1079 src refactor, but if it merges mid-day it will move `main`; rebase the #1079 branch if needed (no file overlap expected).
- **#1077 base-url specifics** (env var name, where the deploy value is sourced) are genuinely open — that's why they're the issue-B open questions, to be resolved during Copilot expansion.
