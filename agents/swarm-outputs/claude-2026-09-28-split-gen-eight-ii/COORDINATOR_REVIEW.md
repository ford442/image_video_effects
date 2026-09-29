# Split-Gen Eight II — COORDINATOR REVIEW (2026-09-28)

Checklist per §9: card before diff · ideas pointable · KEEP holds · not boilerplate-dominated · no shared
overlay · A packing matches C read · params exact · springs/ripples only if native · gates.

Structural (coordinator-run): all 8 `params` arrays byte-identical to HEAD; `updatedParams` identical except
chrysalis (label "Shell Thickness" → "Shell Hole Width" — HEAD label was wrong, slider widens holes); no live
`extraBuffer[` reads/writes except crt-tv's HEAD inert spring (left, none added); no `plasmaBuffer[1..]` reads
(remaining hits are comments); every file writes dataTextureA + writeDepthTexture; naga + precommit gate 8/8.

| ID | Verdict | Notes |
|---|---|---|
| gen-cybernetic-plasma-orchid-nexus | PASS | petals were buried in the core at HEAD (axes swapped) — default look now shows petals + lip; CPU geometry port checked framing. ACES×1.5 exposure replaces Reinhard+gamma: GPU brightness check |
| gen-hyperdimensional-plasma-loom | PASS, look change | HEAD frame was ~85% source image (readTexture "trail"); now pure raymarch with exact-C trail 0.4. Dead strand-3 removed (no over-under). Camera anchored to cell corner; numpy clearance ≥0.20 |
| gen-cybernetic-aether-moth-chrysalis | PASS with scope note | Rotation Speed now spins about the long axis (in-plane tumble impossible for a hanging body); mouse orbit remapped to yaw + tilt. Voronoi early-out is a valid lower bound (holes only raise the SDF) |
| gen-neon-plasma-chrono-bloom | PASS | HEAD mouse time-dilation kept, not claimed as an idea. 4 snoise/step vs 3 (~1.33×) |
| crt-tv | PASS | scanlines were dead at HEAD (constant 0.5); grille now mean-1 so default is ~3× brighter than HEAD's 1/3-coverage grille; phosphor gamma decay blended at 0.25+0.3·glow to avoid blue wash. Glare added after A write (never persists) |
| silk-flow-advection | PASS with caveat | A packing kept (velocity). ACES on a photo filter compresses whites to ~0.79 and lifts mids — same trade as paper-cutout last batch. Optional sheen idea skipped (too close to gen-aurora-silk) |
| anamorphic-caustic-flare | PASS | A now pre-ACES HDR; feedback is a converging mix. 7 caustic evals vs 1 (cheap sin products) |
| gemstone-fractures | PASS, look change | pivot moved from screen centre to cell centre (HEAD shards left the image → repeat seams); spin bounded. Every shard gets a star: check busy-ness at small Facet Size on GPU |

No file shares an idea or overlay with another. No new springs, ripple shockwaves, or IQ palettes added.
Real-GPU visual QA is still required for all 8 — nothing here claims a look.
