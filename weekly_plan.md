# image_video_effects — Weekly Plan

## Today's focus
**2026-04-25 — AI VJ Mode: expand Alucinate to the full 961-shader library + add param suggestion.**
Extend `src/AutoDJ.ts` (`Alucinate` class) to (1) build a unified cross-category shader manifest from all 15 category JSON files at runtime instead of a filtered generative-only subset, (2) add LLM-driven param suggestion alongside shader ID selection so each slot gets tuned params, and (3) wire a vibe-prompt text input in the Controls UI that fires a one-shot generation without waiting for the 25-second auto-loop cycle.

## Ideas
<!--
Write ideas here during the week as they come to you.
Routine prioritizes these over generated ideas.
Format: - [ ] Short description (optional: more context on next line indented)
Routine will mark picked items as "[in progress — YYYY-MM-DD]".
-->
- [in progress — 2026-04-25] AI VJ Mode — prompt-to-shader-stack generation via in-browser Gemma-2-2b
  Feed user vibe prompt → LLM picks N shaders + params from the 700+ library → renders a live VJ stack. Half-day prototype, multi-day polish.
- [ ] Shader metadata normalization + full-text search over 700+ library
  Reconcile `params_missing.md`, `SHADER_PARAMETER_AUDIT.md`, and `shader_params_extracted.json` into a single canonical metadata schema so the scanner/rating/AI-VJ paths share one source of truth. Full-day.

## Backlog
<!--
Unfinished items, known bugs, deferred ideas.
Routine maintains this automatically — you can add items too.
-->
- [ ] Storage Manager: verify `/api/images` and `/api/videos` streaming endpoints under load (thread-pool saturation, GCS token refresh edge cases)
- [ ] Confirm CORS allowlist (`https://test1.1ink.us`) shipped to the VPS
- [ ] `sync-images` / `sync-videos` admin endpoints need a dry-run mode before first prod run
- [ ] Follow-up on immutable-let auto-fix scan — `IMMUTABLE_LET_FIX_REPORT.md` still has outstanding entries per scan logs
- [ ] Bind-group compatibility report (`bindgroup_compatibility_report.json`) lists shaders flagged for mismatched layouts — unresolved
- [ ] Runtime-error report (`runtime_errors_report.json`) needs triage pass
- [ ] Multi-slot regression harness still unbuilt — `slotOrchestrator.ts`, `multipassRegistry.ts`, `bindGroupValidator.ts` exist but no Jest test suite covers them; last week's focus did not land

## Done
<!--
Completed items, routine archives here with date.
Prune occasionally when this gets long.
-->
- 2026-04-18: Storage Manager CORS fix for `test1.1ink.us`; image/video streaming endpoints; sync-images/sync-videos admin endpoints (archived from prior notes)
- 2026-04-18: Obsidian Echo-Chamber generative shader merged (#536)
- 2026-04-18: Hyper-Refractive Rain-Matrix generative shader merged (#534)
- 2026-04-18: Bioluminescent Aether Pulsar generative shader merged
- 2026-04-18: WebGPU renderer polish — 405 play-count POST fix, bitonic-sort built-ins, sine-wave UnfilterableFloat (#532)
- 2026-04-18: Startup race, event leaks, rating cache stability fixes (#530)

## Last run
<!-- Routine writes summary here each run. Overwrites previous. -->
Date: 2026-04-25
Mode: User Idea
Focus: AI VJ Mode — Alucinate full-library + param suggestion + vibe-prompt UI
Outcome: pending
