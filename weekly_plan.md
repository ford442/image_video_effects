# image_video_effects — Weekly Plan

## Today's focus
<!-- Routine writes here each run. You can delete after day ends, or keep as history. -->
**2026-06-06 — Multi-slot layer-chain preset packs + shareable URLs (User Idea).**
Serialize the full multi-slot chain (up to `PHYSICAL_SLOT_LIMIT = 6` slots: per-slot shader id from `modes`, `SlotParams`, enabled flag, and chained/parallel blend mode) into a compact, versioned, URL-safe encoding. Add encode/decode that round-trips losslessly, hydrate state from the URL on app load (App.tsx already reads `window.location.search` + `window.location.hash`), a one-click "copy share link" action, and a curated "preset pack" gallery of named chains restorable in one click. Makes presets shareable beyond localStorage — the lever that unlocks the PUBLIC audience. kimi-cli swarm drives it.
- **Allowed to touch:** a NEW `src/services/layerChainShare.ts` (encode/decode/versioning), a NEW gallery component under `src/components/`, the share/gallery wiring in `src/App.tsx` and `src/components/Controls.tsx`, a NEW curated preset-pack JSON under `public/`, and new colocated `*.test.ts` files.
- **Must NOT touch:** `src/renderer/` (immutable engine), `src/AutoDJ.ts` + `src/services/{beatDetector,transitionOrchestrator,audioGraph}.ts` (AI VJ auto-transition — shipped, leave alone), any `shader_definitions/` / `public/shaders/` WGSL, the `storage_manager/` backend (that's the decoupled Copilot track today), and `scripts/`.

## Ideas
<!--
Write ideas here during the week as they come to you.
Routine prioritizes these over generated ideas.
Format: - [ ] Short description (optional: more context on next line indented)
Routine will mark picked items as "[in progress — YYYY-MM-DD]".
-->
- [x] AI VJ Mode — prompt-to-shader-stack generation via in-browser Gemma-2-2b
  Feed user vibe prompt → LLM picks N shaders + params from the 700+ library → renders a live VJ stack. Half-day prototype, multi-day polish.
  → Completed 2026-04-25 (buildShaderManifest all 15 categories, selectShadersFromLLM with params, vibe-prompt UI wired in Controls.tsx)
- [x] Shader metadata normalization + full-text search over 700+ library
  Reconcile `params_missing.md`, `SHADER_PARAMETER_AUDIT.md`, and `shader_params_extracted.json` into a single canonical metadata schema so the scanner/rating/AI-VJ paths share one source of truth. Full-day.
  → Completed 2026-05-02 (shaderCatalog.ts built, wired into ShaderBrowserWithRatings + AutoDJ.buildShaderManifest)
- [x] AI VJ stack persistence + history panel
  Add localStorage save/load of generated stacks, a "VJ history" panel showing last N stacks with their vibe prompts, and a one-click "regenerate variation" button. Surface live shader IDs in the UI. Half-day.
  → Completed 2026-05-23 (vjHistory.ts service, saveVJStack in AutoDJ.ts, collapsible VJ History panel with Restore + Regen buttons in Controls.tsx)
- [x] Per-shader param presets + AI VJ randomizer
  Build a preset system for param combos (keyed off shaderCatalog), add a "randomize params" operator that samples within min/max/step ranges for each shader in the active AI VJ stack. Enables live-performance use. Full-day.
  → Completed 2026-05-23 (vjPresets.ts: VJPreset + save/load/delete + randomizeParams with step-snap & [min,max] clamp; randomizeActiveParams() on Alucinate in AutoDJ.ts; Randomize Params / Randomize Slot / Randomize All Slots buttons + collapsible Presets panel save/restore/delete in Controls.tsx; tsc PASS). Verified in repo audit 2026-05-30.
- [x] AI VJ "auto-transition" / beat-aware sequencer
  Extend the AI VJ stack to auto-transition between generated stacks on a timer or audio-beat trigger, cross-fading params via the existing randomizeParams/preset infra. Turns one-shot generation into a continuous live set. Full-day. (Generated 2026-05-30 — was the Copilot track.)
  → Completed 2026-05-30 (commits 812b5ab feat + 60853dd fix). Full stack shipped: `beatDetector.ts`, `transitionOrchestrator.ts`, `audioGraph.ts`, `transitionMath.ts` + tests; `AutoTransitionConfig`, `startAutoTransition`/`stopAutoTransition`/`triggerNextTransition`/`buildTransitionTarget` on Alucinate (AutoDJ.ts); Auto-Transition panel (timer/beat source, interval, duration, randomize/cyclePresets mode) in Controls.tsx. Verified in repo audit 2026-06-06.
- [ ] Multi-slot layer-chain preset packs + shareable URLs [in progress — 2026-06-06]
  Serialize the full multi-slot chain (up to 6 slots: shaders + params + blend) into a compact shareable URL/JSON, with a curated "preset pack" gallery. Makes presets shareable beyond localStorage, unlocking the public audience. Half-to-full-day. (Generated 2026-05-30 — runner-up new idea.)

## Backlog
<!--
Unfinished items, known bugs, deferred ideas.
Routine maintains this automatically — you can add items too.
-->
- [ ] Storage Manager: verify `/api/images` and `/api/videos` streaming endpoints under load (thread-pool saturation, GCS token refresh edge cases) → **TODAY'S COPILOT TRACK** (concurrency tests + token-refresh resilience)
- [ ] Confirm CORS allowlist (`https://test1.1ink.us`) shipped to the VPS
- [ ] ~~`sync-images` / `sync-videos` admin endpoints need a dry-run mode~~ → **CLOSED 2026-06-06**: superseded by the two-phase **plan/apply intent flow** (`POST /api/admin/sync-images/plan` creates a no-write intent = dry-run; `/apply` executes). Old single-shot `POST /api/admin/sync-images` now returns a "gone" pointer to plan/apply.
- [ ] ~~Bind-group compatibility report triage pass~~ → **CLOSED 2026-06-06** (see Done): 966/971 compatible, 15 auto-fixed (naga-OK), 4 deferred to human redesign, 1 false positive.
- [ ] **4 bind-group layout-conflict shaders need human redesign** (deferred by the triage swarm — not auto-fixable): `plasma` (binding 12 uses `array<PlasmaBall,50>` instead of `array<vec4<f32>>`), `tone-histogram` + `tone-histogram-apply` (binding 10 `array<atomic<u32>>` histogram atomics need architectural fix), `deep-workgroup-multi-effect-blend` (`workgroup_size(16,16,4)` w/ `shared_tile[16][16][4]` — can't shrink wg without redesign).
- [ ] Add `_hash_library` to `TEMPLATE_FILES` in `scripts/bindgroup_checker.py` (false-positive library file with no `@compute` entry point — keeps polluting reports).
- [ ] **37 shader definitions reference missing local WGSL files** (surfaced by sync dry-run 2026-05-30) — triage whether these are intentional storage-only entries or broken refs.
- [ ] ~~Test runner broken: `typescript` missing from `node_modules`~~ → **CLOSED 2026-05-30**: `npm ci` restores it; CI already enforces `npm ci` before test via `ci.yml`.
- [ ] ~~`layerChain.spec.ts` — add a CI step to enforce `npm ci` before test~~ → **CLOSED 2026-05-30**: `ci.yml` already has `npm ci` + explicit TypeScript resolution gate before `npm test`.

## Done
<!--
Completed items, routine archives here with date.
Prune occasionally when this gets long.
-->
- 2026-06-06: Bind-group compatibility triage + auto-repair pass COMPLETE (kimi-cli swarm). Fresh checker run found 20 incompatible (the May-9 report was stale); 15 auto-fixed and all naga-OK via `scripts/fix_bindgroups.py` (+binding12 stubs, workgroup `(16,16)`→`(16,16,1)`, `custom_params`→`ripples`, +missing bindings 4–12). 4 deferred to human redesign (plasma, tone-histogram, tone-histogram-apply, deep-workgroup-multi-effect-blend — now backlog). 1 false positive (`_hash_library`). Final: 966 compatible / 5 incompatible / 3 templates / 971 total. Artifacts: `reports/bindgroup_{triage,fix_summary,fix_queue}.{md,json}`, `binding_fix_review.json`; scripts `triage_bindgroup_report.js`, `bindgroup_checker.py`, `fix_bindgroups.py`. Full log in `.swarm-state.md`.
- 2026-05-30: AI VJ "auto-transition" / beat-aware sequencer SHIPPED (commits 812b5ab feat + 60853dd fix). Services `beatDetector.ts` (adaptive bass-energy threshold, refractory debounce), `transitionOrchestrator.ts` (IDLE/WAITING/TRANSITIONING state machine, timer + beat sources, eased param lerp), `audioGraph.ts` (shared AudioContext, lowpass-isolated kick band), `utils/transitionMath.ts` — all with unit tests. `AutoTransitionConfig` + `startAutoTransition`/`stopAutoTransition`/`triggerNextTransition`/`buildTransitionTarget` on Alucinate; Auto-Transition panel in Controls.tsx (timer/beat, interval, duration, randomize/cyclePresets). Confirmed via repo audit 2026-06-06.
- 2026-05-30: Hardcoded SFTP password removed from `scripts/deploy.py` (line 251) and `scripts/deploy_app_only.py` (line 38). Both now read `DEPLOY_PASS` env var; `deploy.py` falls back to `getpass.getpass()` interactive prompt; `deploy_app_only.py` already had that fallback. **Rotate the DreamHost credential** — it was committed in plaintext to a public repo.
- 2026-05-30: Pipeline hygiene pass (Claude Code E task) — all 6 stages green: `npm ci` restored typescript@4.9.5; `npm run build` clean (963 shaders, Compiled successfully); `layerChain.spec.ts` 25/25 PASS; sync dry-run (34 to upload, no writes); deploy scripts verified correct; storage manager AST-clean. Closed two stale backlog items (test runner / CI enforcement — both already solved in ci.yml).
- 2026-05-23: Per-shader param presets + AI VJ randomizer — `vjPresets.ts` (VJPreset interface; savePreset/loadPresets/deletePreset, localStorage, max 50; `randomizeParams(shaderIds, catalog)` samples uniform [min,max], snaps to step, clamps overshoot), `randomizeActiveParams()` public method on `Alucinate` (`src/AutoDJ.ts`), and Controls.tsx UI: Randomize Params + Randomize Slot + Randomize All Slots buttons and collapsible Presets panel (save named / restore / delete). tsc PASS. Confirmed via repo audit 2026-05-30 (commits 1969be8, be1ccfa).
- 2026-05-23: AI VJ stack persistence + history panel — vjHistory.ts service (save/load/clear/removeEntry, max 20 entries, localStorage), saveVJStack wired into AutoDJ.generateFromVibe, collapsible "VJ History" panel in Controls.tsx with per-entry Restore (exact stack+params) and Regen (re-fires generateFromVibe with same vibe string) buttons, Clear History button.
- 2026-05-16: WGSL runtime-error fix pass — all 49 critical shaders in `reports/runtime_errors_report.json` fixed and validated via naga. Patterns: bulk canonical binding renames (videoSampler→u_sampler, outTex→writeTexture, etc.) resolved the majority; false-positive invalid_binding flags cleared for 8 multi-pass shaders; array_bounds ripple clamps added where needed. 49/49 naga OK per `.swarm-state.md`.
- 2026-05-09: Shader metadata normalization — `shaderCatalog.ts` service built (merges 15 category JSONs + shader_params_extracted.json, in-memory full-text index, module-level cache), wired into `ShaderBrowserWithRatings` (search) and `AutoDJ.buildShaderManifest()` (AI VJ path). Single source of truth confirmed in code audit.
- 2026-05-02: AI VJ Mode — Alucinate full-library manifest (all 15 categories, 918 shaders), LLM param suggestion (`selectShadersFromLLM` returns `{id, params}[]`), `onUpdateParams` callback, `generateFromVibe()` one-shot method, vibe-prompt text input + Generate button in Controls.tsx (kimi-cli swarm, confirmed via `.swarm-state.md` + code audit)
- 2026-04-18: Storage Manager CORS fix for `test1.1ink.us`; image/video streaming endpoints; sync-images/sync-videos admin endpoints (archived from prior notes)
- 2026-04-18: Obsidian Echo-Chamber generative shader merged (#536)
- 2026-04-18: Hyper-Refractive Rain-Matrix generative shader merged (#534)
- 2026-04-18: Bioluminescent Aether Pulsar generative shader merged
- 2026-04-18: WebGPU renderer polish — 405 play-count POST fix, bitonic-sort built-ins, sine-wave UnfilterableFloat (#532)
- 2026-04-18: Startup race, event leaks, rating cache stability fixes (#530)

## Last run
<!-- Routine writes summary here each run. Overwrites previous. -->
Date: 2026-06-06
Mode: User Idea (sole remaining unfinished idea: "Multi-slot layer-chain preset packs + shareable URLs")
Focus: Multi-slot layer-chain preset packs + shareable URLs — versioned URL-safe encode/decode of the up-to-6-slot chain (shaders + SlotParams + blend), URL hydration on load, copy-share-link, curated preset-pack gallery. kimi-cli swarm drives it.
Outcome: pending. (Reconciliation this run: last week's bind-group triage focus verified COMPLETE → archived to Done [966/971 compatible, 15 auto-fixed naga-OK, 4 deferred to human, 1 false positive]; 4 layout-conflict shaders + the `_hash_library` TEMPLATE_FILES note added to Backlog. The other runner-up idea "AI VJ auto-transition / beat-aware sequencer" was found already SHIPPED 2026-05-30 [commits 812b5ab + 60853dd] → marked done in Ideas + Done. Backlog item "sync-images/sync-videos dry-run" CLOSED — obsoleted by the plan/apply intent flow. Copilot track today = backend streaming-endpoint concurrency tests + GCS token-refresh resilience [decoupled from the frontend share work]. Note: recent_chats/conversation_search tools UNAVAILABLE again this run — no Claude.ai chat history; context drawn from repo + weekly_plan.md only.)
