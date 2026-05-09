# image_video_effects — Weekly Plan

## Today's focus
**2026-05-09 — Systematic WGSL runtime-error fix pass over the 49 critical shaders in `reports/runtime_errors_report.json`.**
kimi-cli iterates over every shader with `status: "critical"` (invalid_binding × 8, sampler_mismatch × 15, division_by_zero guards, array_bounds clamps, missing_write stubs). For each shader: read the error payload from the report, open the WGSL source in `public/shaders/`, apply the minimal targeted fix, re-validate with `naga` (or `wgsl-analyzer` if available), update `reports/runtime_errors_report.json` in-place to mark the shader clean. Save progress to `.swarm-state.md` at each iteration boundary. Do not touch `reports/bindgroup_compatibility_report.json` or any TypeScript/React files.

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
- [ ] AI VJ stack persistence + history panel
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
Date: 2026-05-09
Mode: New Idea
Focus: Systematic WGSL runtime-error fix pass (49 critical shaders from runtime_errors_report.json)
Outcome: pending
