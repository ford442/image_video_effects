# image_video_effects — 2026-10-03 dispatch (re-cut 19:30 UTC)

**Status:** The morning pick (#1311 WP-A) was overtaken the same day. Noah landed **all four #1311 work packages** (#1356 WP-A, #1355 WP-B, #1354 WP-C, #1353 WP-D) and **#1310** (#1339), merged the morning plan PR #1351, and CI is green on `main` @ `cb0f173`. #1311 and #1310 are closed. Today's focus is now **#1329**: hide the WASM toggle from the default UI, trim per-PR WASM CI, and state Tier B frozen in the policy docs. Copilot gets **#1357**, the verified bench-harness spec. Next cliff: **2026-10-26**, when the 234 renewed thumbnail deferrals expire.

## Mode declaration

**User Idea, re-cut.** Nothing is broken: CI is green after the biggest merge day in weeks, and the morning's clean install ran Jest at 107 suites / 764 passed / 0 failed. #1329 is Noah's own 09-27 follow-up to the #1080 Stay-B decision. It was waiting on WP-A (which deleted the dead `RendererToggle.tsx`), and WP-A merged at 18:04 UTC, so it is the first unblocked, headless, Noah-authored item left.

## Context from prior sessions

- **Morning audit stands:** #1312-A shipped 09-26 (verifier exit 0 at 234/234; all expire 10-26). #1307, #1300, #1308 landed; #1080 decided Stay B.
- **Afternoon, 17:30–19:10 UTC:** #1353 (repo-root cleanup: `agents/`, `memory/`, `MEMORY.md`, `.swarm-state.md` untracked; deploy scripts → `tools/deploy/`; `CMakeLists.txt` gone), #1354 (real ESLint gate — `npm run lint` fails CI now), #1356 (leak-free lifecycle; `destroy()` returns a promise; dead demo/`useWASM`/adapter-ladder helper deleted), #1339 (canvas COPY_SRC, GPU still ingest, WebCodecs recording, 6-slot artifact), #1355 (C++ correctness, `-flto`, rebuilt artifacts). PR #1351 merged at `cb0f173`.
- **Open issues (10):** #1357, #1330, #1331, #1329, #1325, #1324, #1314, #1313, #1312, #1182. #1324/#1325 were fixed by `621479d` on 09-26.
- **Issue reconciliation this run:** Noah filed #1357 from the section-B draft; this routine then wrote the tree-verified spec onto #1357 and restored #1330 to his original ten findings plus a pointer. Verified corrections in #1357: the harness is `window.__pixelocity__` (not `testHarness`) and already exposes `renderer.getDiagnostics()`; the TS leg already has `timestamp-query` timings while WASM is wall-clock, so the current comparison mixes sources (new T11); CRA Jest only runs under `src/`, so the pure helpers go in `src/utils/`.
- **Gaps:** `recent_chats` / `conversation_search` unavailable in this headless run. No evidence last week's Claude Code track ran. The routine's PROJECT CONTEXT is stale on TS version, the transformers package, and now the deploy path (`tools/deploy/deploy.py`, not `deploy.py`).
- **Watch:** `weekly_plan.md` and `weekly_dispatch.md` are tracked on `main` but listed in `.gitignore` after WP-D. `git add -f` is needed from now on; Noah should pick one (see Backlog).

## weekly_plan.md changes (written)

- **Today's focus:** replaced the morning block with the re-cut (#1329) and the reasons #1311 and #1312-C are not it.
- **Ideas:** #1311 → done (all four WPs); #1310 → landed; #1329 → `[in progress — 2026-10-03]`; Copilot line now points at #1357.
- **Backlog:** deploy dry-run item re-pointed at `tools/deploy/deploy.py`; two new items — the tracked-but-gitignored plan files, and #1312-C's numpy harnesses having left the repo with WP-D.
- **Done / Last run:** afternoon appended; the 10-03 Last run entry rewritten.

## Today's focus

From Ideas: **"WASM: hide the UI toggle + trim per-PR WASM CI (#1329, post-#1080 Stay B)."**

Verified on `main` @ `cb0f173`:
- **The live toggle** is `src/components/controls/panels/RendererBackendPanel.tsx`, rendered from `AdvancedDebugPanel.tsx:90` when `onSwitchRenderer` is passed (`ControlsContainer.tsx:91/241/403`). `?renderer=` parsing is in `src/renderer/backendLifecycle.ts:42`.
- **CI:** `wasm` job runs on every push to `main`/`develop` and every PR; `test` has `needs: wasm` and downloads `wasm-artifacts` (`ci.yml:104`); `test-wasm-e2e` needs both. The committed `public/wasm/pixelocity_wasm.wasm` is already sha-compared to the fresh build (`ci.yml:53-57`), so `test` can run against the committed artifacts without the build job.
- **Docs:** `docs/WASM_BACKEND_POLICY.md` and `docs/WASM_PROMOTION_TRACKING.md` have no "Tier B, frozen R&D" status line. `.github/PULL_REQUEST_TEMPLATE.md` still asks for WASM status on every PR.
- **Only one scheduled workflow exists** (`thumbnail-coverage-status.yml`), so the weekly WASM schedule is new.

---

## Dispatch

### A. kimi-cli swarm task (the main event)

```text
ROLE: You are a long-running engineering swarm in the repo ford442/image_video_effects ("Pixelocity":
React 19 + TypeScript ~5.4 + CRA/CRACO + WGSL WebGPU compute shaders, plus a C++/Emscripten WASM renderer
that is FROZEN at Tier B as R&D as of 2026-09-27). Work on a new branch: feat/1329-wasm-tier-b-surface.

OBJECTIVE
Land GitHub issue #1329 in full: remove the WASM backend from the DEFAULT user surface and from the
per-PR CI path, without deleting it. Read `gh issue view 1329` first. Why: #1080 decided WASM stays
Tier B / frozen R&D. Today every PR still builds the WASM toolchain (emsdk) and runs the WASM e2e job,
and every user sees a backend toggle for a renderer the project has frozen. `?renderer=wasm` must keep
working for R&D runs.

THE WORK (one commit per item)
1. UI. `src/components/controls/panels/RendererBackendPanel.tsx` is rendered from
   `AdvancedDebugPanel.tsx` when `onSwitchRenderer` is passed. Hide the panel unless a `?renderer=`
   query param is present (reuse the parsing in `src/renderer/backendLifecycle.ts` — READ-ONLY, do not
   change its semantics). When WASM is URL-forced, show an "Experimental (R&D)" badge next to the active
   backend; no badge otherwise. Keep the existing diagnostics summary in AdvancedDebugPanel. Jest:
   (a) no `?renderer=` → panel absent, no badge; (b) `?renderer=wasm` → panel present + badge;
   (c) `?renderer=webgpu` → panel present, no badge. Mock `window.location.search`.
2. CI. In `.github/workflows/ci.yml`:
   - `wasm` and `test-wasm-e2e` run only when the PR/push touches `wasm_renderer/**`, `public/wasm/**`,
     `tests/wasm-*`, `src/wasm/**`, or the workflow itself. Implement with a `paths` filter on a
     dedicated workflow OR a `dorny/paths-filter`-style job output — pick the simplest that keeps a
     single `ci.yml`. Add `schedule:` weekly on `main` (pick an off-hour, not :00/:30 — e.g. Sunday
     04:17 UTC) that runs both.
   - `test` must no longer `needs: wasm`. It runs against the committed `public/wasm/*` (the `wasm` job
     already sha-checks the committed artifact at ci.yml:53-57 — keep that check inside the `wasm` job).
     Remove the `download-artifact` step from `test` and verify nothing else in `test` depended on the
     fresh build (grep for `wasm-artifacts`). The WASM Jest gate (`--testPathPattern=WASM`) STAYS in
     `test` — it runs against committed artifacts and must keep passing.
   - `test-wasm-e2e`'s `if:` must not reference `needs.wasm.result` when `wasm` is skipped; use
     `always() && needs.test.result == 'success' && (needs.wasm.result == 'success' || needs.wasm.result == 'skipped')`
     or restructure so the e2e job only exists in the path-filtered branch.
   - Validate with `actionlint` if available (`npx -y actionlint` or the docker image), else with
     `node -e "require('js-yaml').load(require('fs').readFileSync('.github/workflows/ci.yml','utf8'))"`.
   Note for the PR body: Noah removes `wasm` / `test-wasm-e2e` from required checks in repo settings;
   you cannot.
3. PR template. `.github/PULL_REQUEST_TEMPLATE.md`: keep the checklist item for "if C++ or
   wasm_renderer/bridge changed", drop the standing "WASM / build notes" section into one line that
   links `docs/WASM_BACKEND_POLICY.md`. Check `CONTRIBUTING*`/`README.md` for the same ask and trim.
4. Policy docs. `docs/WASM_BACKEND_POLICY.md`: add at the top the status line
   "Tier B, frozen R&D as of 2026-09-27 (#1080). Parity bugs only; GraphRunner TS-only."
   `docs/WASM_PROMOTION_TRACKING.md`: link `reports/wasm-promotion-evidence-2026-09-27.md` and mark
   gates 1–4 "closed — not promoted"; note that trimming CI resets the Gate 4 clock (acceptable per
   the issue).

ALLOWED TO TOUCH
- src/components/controls/panels/RendererBackendPanel.tsx, AdvancedDebugPanel.tsx, and the minimum prop
  plumbing in src/components/controls/ControlsContainer.tsx; colocated *.test.tsx
- .github/workflows/ci.yml (+ a new workflow file only if the paths-filter approach needs it)
- .github/PULL_REQUEST_TEMPLATE.md, README.md / CONTRIBUTING*.md (WASM-status ask only)
- docs/WASM_BACKEND_POLICY.md, docs/WASM_PROMOTION_TRACKING.md
- .swarm-state.md (gitignored; local save-state)

DO NOT TOUCH
- wasm_renderer/**, public/wasm/** (frozen; emcc boundary) — deleting them is an explicit anti-goal
- src/renderer/** (WP-A/#1356 just landed today; read-only), src/wasm/**, src/gpuChores/**
- playwright.config.ts, tests/**, src/hooks/useTestHarness.ts, src/utils/benchmarkStats*,
  src/utils/gpuLaunchArgs* (a parallel Copilot task, #1357, owns these)
- tools/deploy/**, storage_manager/** (a parallel Claude Code task owns these)
- public/shaders/**, shader_definitions/**, shader_plans/**, shader_queue/**
- weekly_plan.md, weekly_dispatch.md

ITERATION LOOP
0. `npm ci` (re-run once on sharp ECONNRESET). Baseline: `npx tsc --noEmit`, `npm run lint` (REAL gate
   since #1354 — must be clean), `CI=true npx craco test --watchAll=false` (≈107 suites / 764 passed on
   2026-10-03 — record what you measure), `npm run test:wasm:unit`.
1. Per item: failing test first where a test applies (item 1), then fix, then tsc + lint + full Jest.
2. After item 2: YAML/actionlint validation; confirm `test` has no `needs: wasm` and no artifact
   download; dry-read the workflow for the three trigger cases (PR touching src only → wasm skipped,
   test runs; PR touching wasm_renderer/** → both run; schedule → both run).
3. Final: `SKIP_WASM_BUILD=1 npm run build` green; `npm run verify:dependency-boundaries` green.
4. No GPU exists in your environment; never add a fallback renderer or "fix" rendering you cannot see.

SAVE-STATE (mandatory)
Append to .swarm-state.md at every iteration boundary:
  ## #1329 — iteration N — <ISO timestamp>
  - done: <items + SHAs>   - next: <item>   - blocked: <cmd + error>
  - tests: <measured suites/passed/failed>   - files changed: <paths>

DEFINITION OF DONE
- Items 1–4 committed; Jest for item 1; tsc + lint + Jest + build green; YAML valid.
- PR body (for the wrap-up agent to open, not you): the three trigger-case table, the "remove from
  required checks" note for Noah, and the Gate-4 clock note.
- Leave the branch pushed; do not open the PR yourself.
```

### B. GitHub issue — filed

Done this run: **#1357** carries the tree-verified spec (T1–T12, scope, Jest note, parked alternatives, four questions). **#1330** is back to Noah's original ten findings plus a pointer to #1357; the C++ error-message item stays there, deferred. Nothing to paste.

### C. Chat-model expansion — consumed

Gemini / K2 / Grok outputs were folded into #1357 this run. Where they disagreed with the tree, the tree won (see #1357's "What the tree actually does today"). No further expansion prompts needed today; if Noah wants a second opinion on one point, the open one is **T3** (about:blank + bringToFront vs. a browser per leg).

### D. Copilot Agent handoff

```text
Implement GitHub issue #1357 in ford442/image_video_effects exactly as written (tasks T1–T12, acceptance
criteria, Jest note). Do not re-derive the plan from #1330; #1357 is the verified spec.

Hard rules:
- Edit ONLY: playwright.config.ts, tests/wasm-benchmark.spec.ts, tests/helpers/**, src/hooks/useTestHarness.ts,
  new src/utils/benchmarkStats.ts + src/utils/gpuLaunchArgs.ts with colocated *.test.ts, docs/WASM_BENCH_REPORT.md,
  and reports/data/ output. Pure helpers live under src/ because CRA Jest only runs tests under src/ and
  tests/**/*.spec.ts is Playwright's match.
- Never edit wasm_renderer/**, public/wasm/**, src/renderer/**, src/components/**, .github/workflows/**,
  .github/PULL_REQUEST_TEMPLATE.md, docs/WASM_BACKEND_POLICY.md, or any shader. Another agent is working
  #1329 in parallel on the CI workflow, the Controls panels and the policy docs.
- Keep every existing field in runBenchmark's return (tests/format-tier-bench.spec.ts consumes it).
- No GPU is available: GPU-only paths stay behind WASM_GPU_TESTS=1 and must not change default CI.
- Before opening the PR run: npx tsc --noEmit; npm run lint; CI=true npx craco test --watchAll=false;
  SKIP_WASM_BUILD=1 npm run build; npx playwright test tests/wasm-benchmark.spec.ts --list.
- PR description: a checklist of T1–T12 with evidence, the four open questions with the defaults you
  took, "real-GPU validation pending (Noah, T4 / Windows NVIDIA)", and the deferred C++ item from #1330.
```

### E. Claude Code whole-stack task (mid-day)

```text
Repo ford442/image_video_effects, on main @ cb0f173 or later. Goal: exercise the real pipeline end to
end — React/WebGPU client build → SFTP deploy to DreamHost (tools/deploy/deploy.py, moved there today by
#1353) → FastAPI Storage Manager (storage_manager/) on a VPS — and close the one gap that makes it
impossible to rehearse safely: deploy.py has no dry-run (sync_shaders_to_storage.py already has one).

1. Read tools/deploy/deploy.py, deploy_app_only.py, deploy_credentials.py, test_deploy_credentials.py
   and the deploy*/sync:shaders* npm scripts (already python3 after #1353). Add `--dry-run` to deploy.py
   and deploy_app_only.py: resolve credentials lazily so dry-run needs none, never open an SFTP
   connection, print remote root, file count, total bytes, first/last 20 paths, exit 0. Add a test next
   to test_deploy_credentials.py that runs the walk against a temp dir and asserts zero network calls
   (monkeypatch the SFTP client). Real-deploy behaviour unchanged. Add `"deploy:dry"` and
   `"deploy:app:dry"` npm scripts mirroring `sync:shaders:dry`.
2. Rehearse and time each stage: `npm ci` → `npm run build:manifest` (verify:catalog-counts needs
   public/shader-manifest-unified.json) → `npm run lint` (real gate now) → `npm run verify:toolchain-foundation`
   (record each sub-stage) → `SKIP_WASM_BUILD=1 npm run build` → `python3 tools/deploy/deploy.py --dry-run`
   against build/. Check build/ shader-lists use RELATIVE paths unless SHADER_LIST_BASE_URL is set; flag
   any absolute storage.noahcohn.com URLs baked into a non-deploy build.
3. Backend: venv + `pip install -r storage_manager/requirements.txt`, `python3 -m pytest storage_manager/tests -q`,
   start with uvicorn, `curl GET /api/health`, record the JSON. External hosts are blocked from this VM;
   that is not a failure. Do not touch the real VPS or DreamHost.
4. Write reports/pipeline_rehearsal_2026-10-03.md (stage, command, result, duration). Open a PR with the
   dry-run, the npm scripts and the report. Do not touch src/**, tests/**, playwright.config.ts,
   .github/workflows/**, docs/WASM_*.md or any shader — other agents own those today.
```

### F. Jules wrap-up template (end of day)

```text
You are wrapping up a completed kimi-cli swarm run in ford442/image_video_effects (Pixelocity: React 19,
TypeScript ~5.4, CRA via CRACO, WGSL WebGPU compute shaders; the C++/WASM renderer is frozen Tier-B R&D).
The swarm worked GitHub issue #1329: hide the WASM renderer toggle from the default UI (badge only when
?renderer=wasm is forced), path-filter the `wasm` and `test-wasm-e2e` CI jobs plus a weekly schedule,
decouple `test` from the WASM build, trim the PR template's WASM ask, and add the Tier-B frozen status
lines to docs/WASM_BACKEND_POLICY.md and docs/WASM_PROMOTION_TRACKING.md.
Branch: feat/1329-wasm-tier-b-surface.

FILES THE SWARM CHANGED:
{{KIMI_CLI_FILES_CHANGED}}

WHAT IT DID:
{{KIMI_CLI_SUMMARY}}

KNOWN ISSUES NOAH SPOTTED:
{{KNOWN_ISSUES}}

Read .swarm-state.md (latest "#1329" sections, if present locally) and `gh issue view 1329` first.

WRAP-UP CHECKLIST (all, in order; small logical commits on the same branch)
1. `npm ci` (re-run once on sharp ECONNRESET).
2. Format + lint: `npm run format:check` on changed files (fix with `npm run format` for those files
   only); `npm run lint` must be clean — it is a real CI gate since #1354.
3. `npx tsc --noEmit` clean.
4. `CI=true npx craco test --watchAll=false`: 0 failed, count >= 2026-10-03 baseline (107 suites / 764
   passed / 1 skipped) + the swarm's new tests. Also `npm run test:wasm:unit` (it must still pass
   against the committed public/wasm/* now that `test` no longer builds WASM). Never skip/.only/delete
   a test to go green.
5. Workflow validation: `npx -y actionlint .github/workflows/ci.yml` (or js-yaml parse if actionlint is
   unavailable). Re-read the three trigger cases — PR touching src only; PR touching wasm_renderer/**;
   schedule — and write them as a table in the PR body. Confirm `test` has no `needs: wasm` and no
   `download-artifact` of wasm-artifacts; confirm `test-wasm-e2e`'s `if:` tolerates a skipped `wasm`.
6. Finish any TODO/FIXME/stub in changed files; leave `// TODO(#1329):` + a PR note only if genuinely
   blocked.
7. Coverage: the panel-visibility + badge logic has Jest for no-param / ?renderer=wasm / ?renderer=webgpu.
   If the swarm added a helper (e.g. a `shouldShowBackendPanel(search)` pure function), it has its own test.
8. Boundaries: `git diff origin/main --stat` touches nothing under wasm_renderer/**, public/wasm/**,
   src/renderer/**, tests/**, playwright.config.ts, tools/deploy/**, storage_manager/**, or shaders.
   Revert anything outside the #1329 allowlist.
9. Docs: both status lines present; README/CONTRIBUTING no longer ask for WASM status per PR;
   `?renderer=wasm` documented as the only way to reach the backend.
10. `SKIP_WASM_BUILD=1 npm run build` green; `npm run verify:dependency-boundaries` green.
11. Open a PR to main titled "feat(wasm): #1329 — Tier-B surface: hide toggle, trim per-PR WASM CI"
    with: per-item summary, the trigger-case table, measured test counts, command log for 2/3/4/5/10,
    and two notes for Noah: (a) remove `wasm` / `test-wasm-e2e` from required checks in repo settings,
    (b) trimming CI resets the Gate-4 clock. Reference #1329; do NOT write "closes".

ACCEPTANCE (tick in the PR body)
- [ ] lint clean, tsc clean
- [ ] Jest 0 failed, >= baseline + new; test:wasm:unit green on committed artifacts
- [ ] ci.yml valid; `test` independent of `wasm`; path filter + weekly schedule present; e2e `if:` tolerates skip
- [ ] Panel hidden by default, shown with ?renderer=, badge only for wasm — Jest-covered
- [ ] Policy docs + PR template updated
- [ ] No files outside the allowlist; nothing under wasm_renderer/** or public/wasm/** deleted
- [ ] Build + dependency boundaries green

Open the PR for Noah to review. DO NOT MERGE.
```

### G. Review prompts (Gemini Pro)

**1. Raw kimi-cli diff (before Jules)**

```text
Attached: the diff of branch feat/1329-wasm-tier-b-surface vs main in ford442/image_video_effects, plus
.github/workflows/ci.yml at HEAD, src/components/controls/panels/{RendererBackendPanel,AdvancedDebugPanel}.tsx,
src/components/controls/ControlsContainer.tsx and src/renderer/backendLifecycle.ts. Context: WebGPU-required
React app; a C++/WASM renderer frozen as Tier-B R&D; the diff should implement issue #1329 (text below)
and nothing else. Review for:
1. CI correctness: enumerate every trigger (push main/develop, PR touching src only, PR touching
   wasm_renderer/**, schedule) and state which jobs run and whether `test` can ever be skipped or blocked
   by a skipped `wasm`. Flag any `needs:`/`if:` combination that silently skips `test`.
2. Safety: does `test` still exercise the committed public/wasm/* (WASM Jest gate)? Is the committed
   artifact still sha-checked somewhere on every change to wasm_renderer/**?
3. UI: can a user still reach WASM via ?renderer=wasm? Is the badge shown only then? Any change to
   backendLifecycle semantics (should be none)?
4. Drift: anything outside the issue's scope, anything touching src/renderer/**, tests/**, or the frozen
   C++; any deletion under public/wasm/.
Output a ranked list (blocker / should-fix / nit) with file:line and a concrete fix.

Issue #1329:
<paste gh issue view 1329>
```

**2. Jules PR vs objective + checklist**

```text
Attached: the Jules PR (diff + description) for "feat(wasm): #1329 — Tier-B surface" in
ford442/image_video_effects, the swarm objective, and the wrap-up checklist below.
1. For each of the four #1329 items: done? tested? evidence in the PR body? Mark ✅/⚠️/❌.
2. For each checklist item: done with command output, or just claimed?
3. Did Jules change behaviour beyond tidy-up (new logic, edits outside the allowlist, weakened tests,
   anything under wasm_renderer/** or public/wasm/**)? List each.
4. Is the trigger-case table in the PR body consistent with the actual ci.yml in the diff?
5. Merge recommendation: merge / merge after fixes (list) / reject (why).

Objective:
<paste section A>

Checklist:
<paste section F checklist + acceptance>
```

---

## Suggested timeline (from 19:30 UTC re-cut)

| Offset | Step |
|---|---|
| 0:00 | Start A (kimi, #1329). Hand D to Copilot against #1357 — the issue is already expanded. |
| 0:15 | E (Claude Code pipeline rehearsal + `deploy.py --dry-run`), ~1–1.5 h. |
| When kimi finishes | G1 on the raw diff, then fill in and launch F (Jules). |
| End of day | G2 on the Jules PR. Close #1324/#1325. In repo settings, drop `wasm` / `test-wasm-e2e` from required checks once the #1329 PR merges. |

## Open questions

- **Plan files:** `weekly_plan.md` / `weekly_dispatch.md` are tracked on `main` but listed in `.gitignore` after WP-D. Untrack them and move the routine's state to a gitignored path, or drop the two ignore lines? The routine needs to know where to write next week.
- **10-26 thumbnail expiry:** will a `gpu` self-hosted runner register before then? If not, 10-10 or 10-17 has to be the second honest removal pass.
- **#1312-C:** the `multi-turing` numpy harness left the repo with WP-D. Commit it under `tools/` or drop the pointer in the issue?
- **#1324 / #1325:** fixed by `621479d`. OK to close?
- **#1357 defaults taken:** developer-features flag off, `reports/data/` left tracked, 10 warm-up frames, no `--ozone-platform`. Answer the four questions at the bottom of #1357 before Copilot starts if any default is wrong.
- **PROJECT CONTEXT** in the routine prompt: TS ~5.4, `@huggingface/transformers` v4, deploy via `tools/deploy/deploy.py`, lint is now gating (`npm run lint`).
