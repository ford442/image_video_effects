# image_video_effects — 2026-10-10 dispatch

**Status:** CI green on `main` @ `d74e665` (run 2709). Both 10-03 tracks shipped (#1329 → PR #1380, #1357 → PR #1385). Noah's 2026-10-07 audit (#1393–#1408) is the live backlog and he has 10 PRs in flight against it. Today: **#1393 versioned project files** (kimi), **#1404 video preload dedupe** (Copilot), **`deploy.py --dry-run` finally built** (Claude Code).

## Mode declaration

**User Idea.** Nothing is red and last week's work landed, so Fix First does not apply. The Ideas section (seeded by Noah's PR #1420, merged into this branch) has unfinished items; everything already under one of his open PRs is excluded so today's agents don't collide with branches he is driving. #1393 is the only Noah-authored, product-facing, fully headless item with no PR and a code surface none of the 19 open PRs touch.

## Context from prior sessions

- **10-03 tracks:** A (#1329) shipped via PR #1380 on 10-05 — no UI toggle, `?renderer=wasm` still works, `wasm`/`test-wasm-e2e` moved to path-filtered `wasm.yml`, policy docs carry "Tier B, frozen R&D". B (#1357) shipped via PR #1385 on 10-09; `d74e665` adds `benchmarkSpeedup.ts`, uncapped mode, COOP/COEP serving, report schema v3. C (deploy dry-run) **did not run** — third week.
- **Noah's 2026-10-07 audit** opened #1393–#1408 (two Opus/Sonnet audit passes: renderer/device/WASM/build foundation + a no-WebGPU-machine usability sweep). Of these, #1394 → PR #1419, #1395 → PRs #1421–#1425, #1396 → PR #1415, #1399 → PR #1418, #1402 merged. Uncovered: #1393, #1397, #1398, #1400, #1401, #1403–#1408.
- **Thumbnails:** PR #1383 (open since 10-05, `clean`, 1,040 files) captures on SwiftShader: healthy 20.1% → 91.7%, `gpu-capture-pending` 234 → 40, coverage check becomes blocking, and it rescues the four #1312-C sims with numpy gates under `scripts/sim_models/`. After it merges, 40 deferrals still expire 10-26.
- **PR pile-up risk:** 19 open PRs — #1383, #1419 (rewrites shader definitions), eight shader-upgrade batches, five #1395 slices + #1415 + #1418 in `src/renderer/**`. Merge order matters; suggestion recorded in Backlog.
- **Gaps:** `recent_chats` / `conversation_search` unavailable in this headless run. No `memory/`, `MEMORY.md`, `SOUL.md`, `USER.md` in the clone (gitignored since WP-D) — `weekly_plan.md` is the only state that persists. Jest not re-run here (`node_modules` absent); CI on `d74e665` and PR #1383's 993-pass run are the evidence.

## weekly_plan.md changes (written to this branch)

- **Today's focus:** new 2026-10-10 entry; 10-03 entry archived with outcome.
- **Ideas:** merged Noah's seed block (PR #1420); #1393 marked `[in progress — 2026-10-10]`; #1329 and #1357 marked DONE with PR numbers; thumbnails-10-26 item annotated "covered by PR #1383, 40 remain"; #1404 added as today's Copilot track with verified file pointers; prioritisation note on the seed comment.
- **Backlog:** five NEW items (PR pile-up + merge order; deploy dry-run still missing; 40 post-#1383 deferrals; #1408's 503 verification; absent workspace memory files). 10-03 dry-run item marked still open; #1312-C harness item marked resolved-by-#1383.
- **Done:** 2026-10-10 reconciliation entry.
- **Last run:** 10-03 outcome filled; 10-10 entry appended.

## Today's focus

**#1393 — "Product: versioned project files for saving and restoring a complete VJ session"** (Noah, 2026-10-07, labels `product` / `roadmap`). Issue text, verbatim scope: *"Introduce a versioned project document and user-facing export/import flow for the recoverable parts of a session: ordered shader slots and params, active slot, input-source choice and safe source references, and relevant render/audio-control settings. Provide local file download and import first; this should not require a server account. Treat browser permissions, live device handles, and local media bytes as runtime-only. Reuse chain/preset data where possible rather than creating a competing shader-stack model. Keep migrations explicit as the schema evolves."*

Why now: the two existing half-formats — `SharedChain` (`src/services/layerChainShare.ts`, `v`-versioned, slots + params only) and `VjSetExportPayload` (`src/services/vjSetExport.ts`, `VJ_SET_EXPORT_VERSION = 1`, timeline only) — are exactly the pieces the issue says to reuse, and nothing in the 19 open PRs touches them.

---

## Dispatch

### A. kimi-cli swarm task — #1393 versioned project files

```text
OBJECTIVE
Implement GitHub issue #1393 in ford442/image_video_effects: a versioned, user-owned project file that saves and restores a complete VJ session, with local export/import (no server, no account). Branch from current `main`; branch name `feat/1393-project-files`.

WHY
The app has two partial formats that each capture a slice of a session: `SharedChain` in src/services/layerChainShare.ts (schema field `v`; ordered slots with shaderId/params/enabled/mode, compacted against per-shader defaults, with a migrate step in decodeChain) and `VjSetExportPayload` in src/services/vjSetExport.ts (`VJ_SET_EXPORT_VERSION = 1`; a recorded timeline, parsed by parseVjSetExport/sanitizeTimeline). Neither captures the active slot, input-source choice, or render/audio settings, and neither is a file a user owns. The issue forbids building a third competing stack model: the project file must be a versioned envelope that embeds those two, plus the missing session fields.

READ FIRST (in this order, before writing code)
1. The issue body for #1393 (acceptance criteria are the spec).
2. src/services/layerChainShare.ts, src/hooks/useShareChain.ts (what is captured today: modes, activeSlot, slotParams, inputSource, currentImageUrl, activeGenerativeShader), src/services/vjToSharedChain.ts, src/services/vjSetExport.ts, src/services/vjSetRecorder.ts, src/hooks/useSetRecorder.ts.
3. src/components/controls/panels/VjStudioPanel.tsx (where "Save to My Sets" lives) and src/components/controls/types.ts.
4. src/contracts/ (how JSON contracts are laid out; e.g. slot_limits.json, canvas_configure.json) and scripts/verify-uniforms-layout.js for the pattern of a contract-vs-code verifier.
5. docs/VJ_STUDIO.md and docs/APP_STRUCTURE.md.

DELIVERABLE
1. src/contracts/project_file.json — the schema (JSON Schema draft 2020-12) for ProjectFile v1:
   { schemaVersion: 1, app: { name: "pixelocity", version: string }, createdAt: ISO, chain: SharedChain (embed as-is, keep its own `v`), activeSlot: number, source: { kind: 'image'|'video'|'webcam'|'generative'|'stream'|'none', ref?: string (URL or catalog id — never bytes, never a MediaStream/track id), generativeShaderId?: string }, render: { renderScale?: number, quality?: string } (only fields that already exist in app state — do not invent settings), audio: { mappings as already serialised by the app, or omit }, timeline?: VjSetExportPayload (optional embed) }.
   Secrets/permissions/device handles are forbidden by schema (additionalProperties: false at the top level).
2. src/services/project/ — new directory:
   - types.ts (ProjectFile, ProjectFileV1, discriminated by schemaVersion)
   - validate.ts (validateProjectFile(raw: unknown): { ok: true, project } | { ok: false, errors: string[] }) with safe defaults for optional fields. Prefer a hand-written validator consistent with how decodeChain/parseVjSetExport already validate; do not add a runtime JSON-schema dependency unless one is already in package.json.
   - migrate.ts (migrateProjectFile(raw): explicit v→v+1 chain; v1 is identity; unrecognised version returns null with a reason). Add a "v0" migration that accepts a bare SharedChain or a bare VjSetExportPayload and lifts it into v1, so existing exported files import.
   - exportProject.ts / importProject.ts (buildProjectFile(sessionState), serializeProjectFile → string, parseProjectFile(string) → validated+migrated ProjectFile). Import is two-phase: validate the whole file first; only then produce an "apply plan" { chain, activeSlot, source, warnings[] } — unknown shader ids become empty slots with a warning, an unavailable media ref becomes source.kind 'none' with a "relink" warning. Nothing touches live session state until the plan exists.
   - index.ts barrel.
3. A hook src/hooks/useProjectFile.ts that adapts live app state → buildProjectFile and apply plan → the existing setters (reuse what useShareChain already does to apply a decoded chain; do not duplicate its expansion logic — call it).
4. One panel src/components/controls/panels/ProjectFilePanel.tsx: "Export project (.pixelocity.json)" (Blob download) and "Import project…" (file input), showing the warnings list after import. Wire it where VjStudioPanel's "Save to My Sets" lives, as a sibling, minimal CSS in the existing stylesheet split (run `npm run verify:css`).
5. Tests (Jest, colocated *.test.ts): schema validation (valid, missing fields, extra top-level key rejected), migration (v0 SharedChain → v1, v0 VjSetExport → v1, unknown version → null), round-trip (buildProjectFile → serialize → parse → deep-equal on supported fields), unknown shader id → empty slot + warning, unavailable media → 'none' + warning, and a guard test that the serialised file never contains the strings "MediaStream", "permission", or a data: URI.
6. Docs: a short "Project files" section in docs/VJ_STUDIO.md (format, what is and is not saved, migration policy). README one-liner only if README lists VJ features.
7. Backward compatibility: existing share links (useShareChain URL path) and PresetPackGallery must be untouched — run their tests.

BOUNDARIES
ALLOWED: src/services/project/** (new), src/contracts/project_file.json (new), src/hooks/useProjectFile.ts (new), src/components/controls/panels/ProjectFilePanel.tsx (new), src/components/controls/panels/VjStudioPanel.tsx (mount point only), src/components/controls/types.ts (prop plumbing only if required), src/hooks/useShareChain.ts and src/services/vjSetExport.ts (export small adapters only — no behaviour changes), docs/VJ_STUDIO.md, the CSS file that already styles VjStudioPanel.
READ-ONLY: src/renderer/**, src/wasm/**, src/gpuChores/**, src/components/PresetPackGallery.tsx, src/services/layerChainShare.ts (import it; do not change the wire format), storage_manager/**, public/shaders/**, shader_definitions/**, .github/**, package.json dependencies (scripts block may gain nothing — no new deps).
IGNORE COMPLETELY: anything in src/renderer or webgpu device code — five open PRs (#1421–#1425, #1415) are rewriting it; wasm_renderer/** (frozen Tier B); thumbnails/scripts.

ITERATION LOOP (repeat until acceptance is met)
0. Baseline: `npm ci` (retry once on sharp ECONNRESET), `npx tsc --noEmit`, `npm test -- --watchAll=false --ci` — record suite/test counts as MEASURED (do not copy a previous number).
1. Implement one deliverable item.
2. Verify: `npx tsc --noEmit` → `npm run lint` (real CI gate, must be clean) → `npm test -- --watchAll=false --ci` → `npm run verify:css` → `npm run verify:dependency-boundaries`. Fix before moving on.
3. Every third iteration: `SKIP_WASM_BUILD=1 npm run build`, then `npx serve -s build` and load `?renderer=main` in Chromium; open the panel, export, re-import, confirm no console errors. (If no GPU adapter is available, the WebGPU-required overlay is expected; the panel must still export/import the current state.)
4. Write .swarm-state.md (see below) and commit with a scoped message (`feat(project): …`).

SAVE STATE — write .swarm-state.md at EVERY iteration boundary:
# .swarm-state.md
iteration: N
baseline: suites X / tests Y (measured at iteration 0)
done: [list]
in_progress: [item + exact next step]
blocked: [anything needing Noah: e.g. which audio fields exist in state]
verification_last_run: tsc OK/FAIL, lint OK/FAIL, jest suites/pass/fail, build OK/FAIL/skipped
files_touched: [paths]
Noah may stop you at any boundary and resume from this file; make it sufficient on its own.

ACCEPTANCE (all required)
- validateProjectFile rejects malformed input with messages; accepts a minimal valid v1.
- Migration: v0 SharedChain and v0 VjSetExport import; unknown version → null with reason.
- Round-trip export→import restores slots, params, activeSlot, source ref, render settings; a file with an unknown shaderId imports with that slot empty and a warning, live session untouched until apply.
- Serialized file never contains permission state, device handles, or media bytes (guard test).
- Share links and preset packs unchanged (their existing tests pass).
- tsc clean, lint clean, Jest green, build green.
- Open a PR against main titled "feat(project): versioned project files — export/import a VJ session (#1393)" with: what is saved / not saved, migration policy, screenshots or a short description of the panel, and "Closes #1393".
```

### B. GitHub issue draft — #1404 expansion (Copilot prep)

```markdown
Title: Video preloads: dedupe duration probes, defer until selection, skip when the renderer is blocked (#1404)

## Context / motivation
On a machine with no WebGPU adapter, the new build (test.1ink.us) logs ~34 `net::ERR_ABORTED` for videos under storage.googleapis.com/my-sd35-space-images-2025/video/*.mp4. Each URL is requested twice, then aborted (#1404). This happens while the "WebGPU required" overlay is up, so the work is wasted twice over. Active focus: the renderer is production-default TS WebGPU with a hard-fail boot probe (`window.webgpuProbe`); media handling should respect that probe.

## Verified surface (main @ d74e665)
- `src/services/videoSegmentManager.ts` — `probeVideoDuration(url)` creates a hidden `<video preload="metadata" muted crossOrigin="anonymous">` per URL, caches the duration in a module-level `DURATION_CACHE` **only after** `loadedmetadata`, and its `cleanup()` sets `src=''` then calls `load()` (that is one abort per probe). There is no in-flight map, so two callers for the same URL before metadata arrives produce two requests.
- Callers: `src/hooks/useContentManifest.ts`, `src/hooks/useB3hdMode.ts`, `src/App.tsx`, `src/components/app/AppShell.tsx`.
- Manifest fetch: `src/services/contentLoader.ts:64` (`VIDEO_MANIFEST_URL = ${STORAGE_API_URL}/api/songs?type=video`, `src/config/appConfig.ts:35`), with a fallback in `src/app/constants/fallbackContent.ts`.
- `src/components/WebGPUCanvas.tsx:685` — the one real playback `<video preload="auto">`; not the source of the burst.

## Proposed approach (first pass — Noah expands)
1. In `probeVideoDuration`: add an in-flight `Map<string, Promise<number|undefined>>` next to `DURATION_CACHE`, return the same promise for concurrent callers, and clear it on settle. Make `cleanup()` idempotent and only call `load()` if `src` was actually set.
2. Add a gate: `probeVideoDuration` (or its callers) no-ops when `window.webgpuProbe?.ok !== true` (renderer blocked) — resolve `undefined`, record "skipped: renderer blocked" once in the console, not per URL.
3. Make probing lazy: callers probe on selection/hover (or when a segment is actually needed by useB3hdMode), not for the whole manifest at boot. Keep a small bounded prefetch (e.g. first N=3 in the active list) if the UX needs instant durations.
4. Confirm the "twice" part: check whether `useContentManifest` and `useB3hdMode` each probe the full list, or whether React StrictMode double-invokes an effect in dev only. Fix the real cause, not the symptom.

## Acceptance criteria (rough)
- Loading the app with the WebGPU-required overlay up produces **zero** `.mp4` requests.
- With a working renderer, each video URL is probed at most once per session (Network panel shows one metadata range request per URL, no `ERR_ABORTED`).
- Unit tests (Jest, `src/services/videoSegmentManager.test.ts`): concurrent calls share one promise; cache hit skips element creation; blocked probe resolves `undefined` without touching `document.createElement`.
- `npx tsc --noEmit`, `npm run lint`, `npm test -- --watchAll=false --ci`, `SKIP_WASM_BUILD=1 npm run build` all green.
- No change to `WebGPUCanvas.tsx`, `src/renderer/**`, `contentLoader.ts`'s manifest shape, or the storage-manager API.

## Open questions for Noah
1. Is duration needed at boot for anything user-visible (e.g. B3HD segment planning), or only when a video is chosen?
2. Should the "renderer blocked" gate also skip the manifest fetch itself (`contentLoader.ts`), or only the per-video probes? (#1408 wants the 503 fallback path verified — keep manifest fetch as is unless you say otherwise.)
3. Dev-only StrictMode double-probe: acceptable, or guard with a ref?
```

### C. Three chat-model prompts for the #1404 issue

**C1 — Gemini Pro (codebase + issue → complete plan)**

```text
You are reviewing the React 19 / TypeScript 5.4 / WebGPU repo ford442/image_video_effects (Create React App + CRACO, Jest, ESLint as a CI gate). I'm attaching the repo. Here is a draft GitHub issue:

[PASTE THE FULL ISSUE TEXT FROM SECTION B]

Tasks:
1. Open src/services/videoSegmentManager.ts, src/hooks/useContentManifest.ts, src/hooks/useB3hdMode.ts, src/App.tsx, src/components/app/AppShell.tsx and src/services/contentLoader.ts. List every call path that ends in probeVideoDuration, with file:line, and say which ones run at boot versus on user action.
2. Determine why each URL is requested twice. Candidates: two independent callers, React StrictMode double effects, or the cleanup() src=''+load() pattern. Say which, with evidence from the code.
3. Produce a complete implementation plan: exact functions to change, the in-flight promise map design, where the `window.webgpuProbe.ok` gate belongs (service vs. hook), and how to make probing lazy without breaking useB3hdMode's segment planning.
4. List the Jest tests to add (file, test names, how to mock document.createElement and window.webgpuProbe under jsdom).
5. Name anything the issue missed: other media preloading (images, HLS in HLSVideoSource.tsx), the fallbackContent path, or anything that would also fire with the renderer blocked.
Only name files you actually opened. If a path in the issue is wrong, say so.
```

**C2 — Kimi K2 (stress-test + alternatives)**

```text
Stress-test this GitHub issue for a React 19 + WebGPU web app. The app shows a hard-fail "WebGPU required" overlay when navigator.gpu.requestAdapter() returns null, exposes window.webgpuProbe { ok: boolean, ... }, and loads a video manifest from a FastAPI storage backend, then probes each video's duration with a hidden <video preload="metadata"> element.

[PASTE THE FULL ISSUE TEXT FROM SECTION B]

1. Attack the proposed approach: where does an in-flight promise map leak or deadlock (component unmount mid-probe, URL changes, manifest refetch)? What breaks if probing becomes lazy (segment planning that needs all durations up front)?
2. Propose two alternatives: (a) server-side durations in the manifest (the backend is ours: FastAPI, GCS-backed), (b) a single shared <video> element worker queue with bounded concurrency. Give cost, risk and what each does to the "zero requests while blocked" criterion.
3. Argue for the best option for a solo maintainer who ships weekly, and write the acceptance criteria you would hold it to.
Be concrete; no generic advice about performance.
```

**C3 — Grok (ecosystem currency check)**

```text
Current-ecosystem check for a web app built with React 19, TypeScript 5.4, Create React App + CRACO, WebGPU compute shaders (WGSL), hls.js, Playwright 1.58+, Jest/jsdom. Issue under consideration:

[PASTE THE FULL ISSUE TEXT FROM SECTION B]

Questions, with sources and dates:
1. As of October 2026, what do Chromium, Firefox and Safari do with <video preload="metadata"> for cross-origin MP4s — one range request or several? Does setting src='' then load() still trigger a visible net::ERR_ABORTED in Chromium DevTools, and is there a cleaner teardown?
2. Is there a 2026-current way to read MP4 duration without a media element (fetch a byte range + parse moov; WebCodecs; mp4box.js) that is small enough for a CRA bundle with a size gate?
3. React 19 StrictMode: does it still double-invoke effects in development, and what is the idiomatic guard today?
4. Anything in WebGPU/Chromium 2026 about media and "no adapter" states that should change how a blocked renderer handles media preloading?
Flag anything in the issue that is already outdated.
```

### D. Copilot Agent handoff

```text
Implement the following GitHub issue in ford442/image_video_effects on a new branch from main. Work only in the files the issue names plus new colocated test files; do not touch src/renderer/**, src/components/WebGPUCanvas.tsx, the storage-manager API, or package.json dependencies.

{{EXPANDED_ISSUE}}

Before opening the PR: `npm ci`, `npx tsc --noEmit`, `npm run lint` (must be clean — it is a CI gate), `npm test -- --watchAll=false --ci`, `SKIP_WASM_BUILD=1 npm run build`. Paste the measured Jest suite/test counts into the PR body. Open the PR as ready for review, titled "fix(media): dedupe video duration probes and skip them when the renderer is blocked (#1404)", body: cause found, what changed, how verified, "Closes #1404". Do not merge.
```

### E. Claude Code whole-stack task — build the deploy dry-run, then exercise the pipeline

```text
Repo: ford442/image_video_effects (fresh clone of main). Goal: the frontend deploy script has never had a dry-run mode — three weekly plans have scheduled a "deploy dry-run" that cannot run. Build it, then exercise the pipeline end to end and report what you measured. Work on branch `chore/deploy-dry-run`. Do not touch src/**, shaders, or CI workflows.

1. Add `--dry-run` to tools/deploy/deploy.py and tools/deploy/deploy_app_only.py.
   - Read both scripts fully first. Today they parse only `--force`/`--fresh` from sys.argv (deploy.py:305-306, deploy_app_only.py:137-138) and walk build/ against .deploy_manifest.json, uploading on hash mismatch with ALWAYS_UPLOAD = ['index.html', '.htaccess', 'asset-manifest.json'].
   - Dry run must: compute the exact upload plan (new / changed / always-upload / unchanged counts, and the file list with sizes) WITHOUT opening an SFTP connection, without touching the manifest, and without prompting. Exit 0. Print a one-screen summary plus `--dry-run --verbose` for the full list.
   - Keep argument handling minimal and consistent with the existing style (no new deps; argparse is fine if you convert both flags too). Credentials must not be required for a dry run — guard the import/use of deploy_credentials so a missing credentials file does not block the plan.
   - Add tests next to tools/deploy/test_deploy_credentials.py: plan computation over a temp build dir with a synthetic manifest (new, changed, unchanged, always-upload cases). Run with `python3 -m pytest tools/deploy -q`.
2. Pipeline rehearsal (record real output for each step; if a step fails for an environmental reason, say so explicitly rather than skipping silently):
   a. `npm ci` (retry once if sharp's postinstall hits ECONNRESET).
   b. `SKIP_WASM_BUILD=1 npm run build` (no emsdk here; committed public/wasm/* is used and sha-checked in CI).
   c. `npm run build:manifest` then `npm run verify:toolchain-foundation` — note: verify:catalog-counts needs public/shader-manifest-unified.json, which build:manifest produces; a cold clone fails there otherwise. If it still fails cold, make the verifier print that hint (scripts/verify-catalog-counts.mjs only) and note it.
   d. `python3 tools/deploy/deploy.py --dry-run` against the fresh build/ — paste the summary.
   e. Backend: `cd storage_manager && python3 -m pip install -r requirements.txt && python3 -m pytest -q`; then `curl -sS -m 10 https://ford442-storage-manager.hf.space/api/health` and `.../api/songs?type=video` — record HTTP status and body head. Issue #1408 reported a 503 on 10-07; do not fix the backend, just record what you see and whether the frontend's fallback (src/services/contentLoader.ts:64, src/app/constants/fallbackContent.ts) would engage.
   f. `npm run verify:css`, `npm run lint`.
3. Report: a table of step → command → result → duration, the dry-run summary, the backend health result, and any finding that belongs in an issue (do not file issues; list them). Commit the dry-run work with tests, push, open a PR "chore(deploy): --dry-run for deploy.py and deploy_app_only.py" with the rehearsal table in the body. Do not merge.
```

### F. Jules wrap-up — integrate kimi-cli's #1393 output (fill placeholders at end of day)

```text
You are wrapping up a day of agent work on ford442/image_video_effects (React 19 + TypeScript 5.4, CRA + CRACO, Jest, ESLint gate, WGSL compute shaders, optional C++/WASM renderer that is FROZEN and must not be touched). Another agent (kimi-cli) implemented GitHub issue #1393 — versioned project files for saving/restoring a VJ session — on branch `feat/1393-project-files`. Your job is to turn that branch into a clean, reviewable PR. You do NOT merge.

CONTEXT FROM TODAY
Files kimi-cli changed:
{{KIMI_CLI_FILES_CHANGED}}

What kimi-cli did (summary):
{{KIMI_CLI_SUMMARY}}

Known issues Noah noticed on cursory review:
{{KNOWN_ISSUES}}

The original objective (hold the work to this): a versioned ProjectFile v1 envelope (src/contracts/project_file.json + src/services/project/**) that embeds the existing SharedChain (src/services/layerChainShare.ts) and optional VjSetExportPayload (src/services/vjSetExport.ts), adds activeSlot / source reference / render settings, validates with safe defaults, migrates explicitly (v0 bare SharedChain or VjSetExport → v1), exports/imports as a local file with two-phase import (validate whole file → apply plan with warnings; unknown shader ids → empty slot; missing media → 'none' + relink warning; live session untouched until apply), never serialises permissions/device handles/media bytes, and keeps share links + preset packs backward-compatible.

WRAP-UP CHECKLIST (do all; record the command and result for each)
1. `git fetch origin && git checkout feat/1393-project-files && git merge origin/main` — resolve conflicts preserving kimi's intent; never rebase or force-push.
2. `npm ci` (retry once on sharp ECONNRESET).
3. Format: run Prettier only on the files in {{KIMI_CLI_FILES_CHANGED}} using the repo config (`npx prettier --write <files>`); do not reformat unrelated files.
4. Lint: `npm run lint` — must be clean (it is a CI gate). Fix in place.
5. Types: `npx tsc --noEmit`.
6. Tests: `npm test -- --watchAll=false --ci`. Fix failures caused by the branch; do not skip, disable, or `.only` any test. Paste the measured suite/test counts into the PR body (never copy a number from a previous note).
7. TODO/stub sweep: `grep -rn "TODO\|FIXME\|stub\|not implemented" <changed files>` — complete or remove each; if something genuinely needs Noah, leave the TODO with "NOAH:" prefix and list it in the PR body.
8. Coverage for new public functions: every exported function in src/services/project/** and src/hooks/useProjectFile.ts needs at least one Jest test (valid path + one failure path). Add colocated *.test.ts files where missing. Required tests, add if absent: extra top-level key rejected; v0 SharedChain → v1 migration; unknown schemaVersion → null; round-trip deep-equal; unknown shaderId → empty slot + warning; serialised output never contains "MediaStream", "permission", or "data:" (guard).
9. Docs: if any public API or user-facing flow changed, update docs/VJ_STUDIO.md (a "Project files" section: saved / not saved / migration policy) and README only if it lists VJ features. Keep docs/APP_STRUCTURE.md's component list current if a panel was added.
10. Boundary checks: `npm run verify:css`, `npm run verify:dependency-boundaries`, `npm run verify:bundle-size`.
11. Build: `SKIP_WASM_BUILD=1 npm run build` must pass.
12. Confirm nothing outside the allowed surface changed: `git diff --stat origin/main...HEAD` must show no files under src/renderer/**, src/wasm/**, wasm_renderer/**, public/wasm/**, public/shaders/**, shader_definitions/**, storage_manager/**, .github/**. If any appear, revert them and say so.
13. Commit with scoped messages (`chore(project): wrap-up — lint, tests, docs`), push, and open a PR against main: title "feat(project): versioned project files — export/import a VJ session (#1393)". Body: what is saved / not saved, migration policy, measured test counts, remaining NOAH: items, "Closes #1393". Mark ready for review. DO NOT MERGE.

ACCEPTANCE
- [ ] Branch merges cleanly with main
- [ ] `npm run lint` clean; `npx tsc --noEmit` clean
- [ ] Jest green with measured counts in the PR body
- [ ] Every exported function in the new service/hook has a test; the guard test exists
- [ ] No TODO/stub left without a NOAH: prefix and a PR-body mention
- [ ] docs/VJ_STUDIO.md updated
- [ ] verify:css, verify:dependency-boundaries, verify:bundle-size green
- [ ] `SKIP_WASM_BUILD=1 npm run build` green
- [ ] Diff touches nothing in the forbidden paths
- [ ] PR open, ready for review, not merged
```

### G. Review prompts (Gemini Pro)

**G1 — kimi-cli diff review (before Jules)**

```text
Review this diff for ford442/image_video_effects (React 19, TypeScript 5.4, CRA/CRACO, WebGPU compute shaders; the renderer and WASM backend are out of scope and must be untouched). The objective was GitHub issue #1393: a versioned project file (src/contracts/project_file.json, src/services/project/**) that embeds the existing SharedChain (src/services/layerChainShare.ts) and optional VjSetExportPayload (src/services/vjSetExport.ts), adds activeSlot/source reference/render settings, validates with safe defaults, migrates explicitly, and imports in two phases (validate whole file → apply plan with warnings) without touching live state until apply.

[PASTE `git diff origin/main...feat/1393-project-files`]

Check, with file:line for every finding:
1. Architectural drift: did it build a third stack model instead of embedding SharedChain? Did it change layerChainShare's wire format or duplicate expandSharedChain's logic in useProjectFile?
2. Safety: can anything in the serialised file carry media bytes, data: URIs, MediaStream/track ids, permission state, or GPU objects? Is `additionalProperties:false` actually enforced by the validator?
3. Import atomicity: trace one malformed file and one file with an unknown shaderId through parse → plan → apply. Does any setter run before validation completes?
4. Migration: is v0 → v1 explicit and tested; is an unknown version rejected rather than guessed?
5. Performance: anything O(slots × catalog) on every render; anything that reads the full catalog synchronously in the panel.
6. Boundaries: any change under src/renderer/**, src/wasm/**, shaders, storage_manager, .github.
Rank findings blocking / should-fix / nit. No praise.
```

**G2 — Jules PR review (against objective + checklist)**

```text
Review this pull request for ford442/image_video_effects against two references.

Reference 1 — original objective (issue #1393): versioned ProjectFile v1 embedding SharedChain + optional VjSetExportPayload; activeSlot, source reference (never bytes/handles), render settings; validation with safe defaults; explicit migrations (v0 bare formats → v1, unknown → null); two-phase import with per-slot warnings; local export/import only; share links and preset packs unchanged.

Reference 2 — wrap-up checklist Jules was given: merge main; prettier on changed files only; `npm run lint` clean; `npx tsc --noEmit` clean; Jest green with MEASURED counts in the PR body; every exported function in src/services/project/** and src/hooks/useProjectFile.ts tested, including the "never serialises MediaStream/permission/data:" guard; no TODO without a NOAH: prefix; docs/VJ_STUDIO.md updated; verify:css, verify:dependency-boundaries, verify:bundle-size green; `SKIP_WASM_BUILD=1 npm run build` green; no files under src/renderer/**, src/wasm/**, wasm_renderer/**, public/wasm/**, public/shaders/**, shader_definitions/**, storage_manager/**, .github/**; PR open and not merged.

[PASTE PR TITLE, BODY, AND FULL DIFF]

Report:
1. For each checklist item: met / not met / cannot tell from the PR, with evidence.
2. Any objective item the PR silently narrowed (e.g. import applies before validation, migration missing, render settings dropped).
3. Any test that asserts the wrong thing or was weakened to pass.
4. Merge recommendation: merge / request changes (list them) / reject (why).
```

## Suggested timeline

| Offset | Step |
|---|---|
| 0:00 | Kick off kimi-cli (A). Paste issue B into GitHub as a draft issue. |
| 0:15 | Run C1–C3 in parallel; fold the useful parts into the issue; resolve the three open questions. |
| 0:45 | Hand D to Copilot with the expanded issue. |
| 1:30 | Claude Code E (deploy dry-run + pipeline rehearsal) while kimi iterates. |
| mid-day | Check `.swarm-state.md`; merge-order pass on the 19 open PRs (#1383 first). |
| end of day | Fill F's placeholders from `.swarm-state.md`, hand to Jules. Run G1 on kimi's diff before Jules starts, G2 on the Jules PR after. |

## Open questions

- **PR #1420** is merged into this routine branch; close it once this PR lands, or merge it first and I rebase — either is fine.
- **Merge order** for the 19 open PRs: is #1383 → #1419 → shader batches → #1422 → #1423 → #1424 → #1425 → #1415 acceptable? The 10-26 deferral chore (40 entries) depends on #1383 landing.
- **#1393 scope:** which render/audio settings should be in the project file? The issue says "relevant"; kimi is told to serialise only fields that already exist in app state. Name the ones you want if that's too narrow.
- **Workspace memory:** `memory/`, `MEMORY.md`, `SOUL.md`, `USER.md` are gitignored, so this scheduled run starts from `weekly_plan.md` alone every week. Intentional?
- **Stale PROJECT CONTEXT:** TypeScript is `~5.4.5` and the transformers dep is `@huggingface/transformers` v4 (not `@xenova/transformers`); still unfixed in the routine's block.
