# image_video_effects — Weekly Plan

## Today's focus
<!-- Routine writes here each run. You can delete after day ends, or keep as history. -->
**2026-05-30 — Bind-group compatibility triage + auto-repair pass (New Idea).**
Parse `reports/bindgroup_compatibility_report.json` (22k lines, many shaders flagged for mismatched bind-group layouts), categorize the mismatch classes, and auto-apply canonical binding renames (the pattern proven in the 49-shader naga fix pass) to clear flagged shaders — with naga validation gating every fix. This is the largest open backlog risk and directly de-risks multi-slot shader stacking (mismatched layouts break stacking). kimi-cli swarm drives it. Allowed to touch shader source dirs (`shader_definitions/`, `public/shaders/`), `reports/` (read + write the triage output), and a new `scripts/` triage helper. **Must NOT touch `src/renderer/` (immutable engine) or `src/`.**

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
- [ ] AI VJ "auto-transition" / beat-aware sequencer
  Extend the AI VJ stack to auto-transition between generated stacks on a timer or audio-beat trigger, cross-fading params via the existing randomizeParams/preset infra. Turns one-shot generation into a continuous live set. Full-day. (Generated 2026-05-30 — runner-up new idea; now the GitHub-issue / Copilot track.)
- [ ] Multi-slot layer-chain preset packs + shareable URLs
  Serialize the full 3-slot chain (shaders + params + blend) into a compact shareable URL/JSON, with a curated "preset pack" gallery. Makes presets shareable beyond localStorage, unlocking the public audience. Half-to-full-day. (Generated 2026-05-30 — runner-up new idea.)

## Backlog
<!--
Unfinished items, known bugs, deferred ideas.
Routine maintains this automatically — you can add items too.
-->
- [ ] Storage Manager: verify `/api/images` and `/api/videos` streaming endpoints under load (thread-pool saturation, GCS token refresh edge cases)
- [ ] Confirm CORS allowlist (`https://test1.1ink.us`) shipped to the VPS
- [ ] `sync-images` / `sync-videos` admin endpoints need a dry-run mode before first prod run (note: `npm run sync:shaders:dry` exists for shader sync)
- [ ] Bind-group compatibility report (`reports/bindgroup_compatibility_report.json`, 22k-line JSON) needs triage pass — many shaders flagged for mismatched layouts → **TODAY'S FOCUS**
- [ ] Test runner broken: `typescript` missing from `node_modules`; run `npm ci` in project root before `npm test` (react-scripts test / Jest) or it fails MODULE_NOT_FOUND. `npm run build` is unaffected. Confirmed still broken 2026-05-30.
- [ ] `layerChain.spec.ts` (292-line multi-slot regression harness, `src/__tests__/`) passes structurally but cannot run until the `typescript` dep is restored — add a CI step to enforce `npm ci` before test.

## Done
<!--
Completed items, routine archives here with date.
Prune occasionally when this gets long.
-->
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
Date: 2026-05-30
Mode: New Idea (Ideas list exhausted — all 4 prior ideas completed)
Focus: Bind-group compatibility triage + auto-repair pass (kimi-cli swarm over reports/bindgroup_compatibility_report.json → categorize mismatches → canonical-rename auto-repair gated by naga).
Outcome: pending. (Prior in-progress item "Per-shader param presets + AI VJ randomizer" verified COMPLETE this run and archived to Done. Test runner still broken — typescript missing from node_modules; folded into Claude Code hygiene + Jules wrap-up. Note: recent_chats/conversation_search tools were unavailable this run — no Claude.ai chat history; context drawn from repo + weekly_plan.md only.)
