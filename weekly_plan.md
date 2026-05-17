# image_video_effects — Weekly Plan

## Today's focus
**2026-05-16 — AI VJ stack persistence + history panel.**
kimi-cli adds localStorage save/load of generated VJ stacks to `src/AutoDJ.ts` (intercept `onUpdateStack` / `onUpdateParams` callbacks to persist `{vibeText, shaderIds, params, timestamp}[]`), extracts a thin `src/services/vjHistory.ts` service (get/save/clear, max 20 entries), and wires a collapsible "VJ History" panel into `src/components/Controls.tsx` immediately below the vibe-prompt section — showing last N stacks with vibe text, shader IDs, timestamp, a one-click restore button, and a "regenerate variation" button that re-fires `generateFromVibe` with the same vibe string. Do not touch `src/renderer/`, `reports/`, or `public/shaders/`.

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
- [in progress — 2026-05-16] AI VJ stack persistence + history panel
  Add localStorage save/load of generated stacks, a "VJ history" panel showing last N stacks with their vibe prompts, and a one-click "regenerate variation" button. Surface live shader IDs in the UI. Half-day.
- [ ] Per-shader param presets + AI VJ randomizer
  Build a preset system for param combos (keyed off shaderCatalog), add a "randomize params" operator that samples within min/max/step ranges for each shader in the active AI VJ stack. Enables live-performance use. Full-day.

## Backlog
<!--
Unfinished items, known bugs, deferred ideas.
Routine maintains this automatically — you can add items too.
-->
- [ ] Storage Manager: verify `/api/images` and `/api/videos` streaming endpoints under load (thread-pool saturation, GCS token refresh edge cases)
- [ ] Confirm CORS allowlist (`https://test1.1ink.us`) shipped to the VPS
- [ ] `sync-images` / `sync-videos` admin endpoints need a dry-run mode before first prod run
- [ ] Bind-group compatibility report (`reports/bindgroup_compatibility_report.json`, 22k-line JSON) needs triage pass — many shaders flagged for mismatched layouts
- [ ] Test runner broken: `typescript` missing from `node_modules`; run `npm install` in project root before `npm test` / Jest will fail with MODULE_NOT_FOUND. `npm run build` is unaffected.
- [ ] `layerChain.spec.ts` (292-line multi-slot regression harness) passes structurally but cannot run until the `typescript` dep is restored — add a CI step to enforce `npm ci` before test.

## Done
<!--
Completed items, routine archives here with date.
Prune occasionally when this gets long.
-->
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
Date: 2026-05-16
Mode: User Idea
Focus: AI VJ stack persistence + history panel (localStorage save/load, VJ history panel in Controls.tsx, regenerate-variation button)
Outcome: pending
