# Split-Gen Eight — NOTES (2026-09-28)

Flow: coordinator audit + cards (BRIEFS.md) → 8 parallel agents, one file each → coordinator diff review.
All files left uncommitted on main (shared worktree).

| ID | Ideas in the diff | Floor fixes / default-look change | A packing |
|---|---|---|---|
| morphogenic-resonance | travelling morph front from the pointer (per-cell phase lag); crystalline facet spokes (`polyFacet`); veins conduct the treble discharge | none; cells no longer morph in lockstep, and formColor follows the per-cell phase (HEAD ran it on a different clock) | ACES display RGBA |
| aurora-borealis-loom | fell line + reed beat-up band (bass); slub yarn thickness + light pooling; pulsating aurora patches (3–12 s cells) | none; patches and fell band change the default | ACES display RGBA |
| volumetric-cloud-nebula | light-echo shell (8 s flash, one exp per step); absorbing dense cores via the formerly unused SIGMA_A; warp-flight star streaks (stable sky stars) | unbounded `finalCol + prev*0.85` trail (≈6.7× then clamped 5.5, blown out) → bounded mix; Reinhard → ACES; per-frame star snow → stable stars. Default look changes a lot (it was broken) | ACES display RGBA |
| gen-image-pyro | drag-damped spark flight; shell types peony/willow/ring; crossette split | y flipped (shells fell downward); pointer read as pixels → UV; image 2× zoom → full frame; uniform full-screen flash → falloff; Trail Length un-inverted (0.9025 at default kept); unread B write dropped; depth truthful; launch clock (every mortar went dark after ~27 s); ASCENT 1.12→0.76 (coordinator) so bursts open on screen; probe reads the photo not the clamped bottom row. Default look changes a lot (it was broken) | ACES display RGBA |
| film-gate-weave | frame-line reveal + neighbour frame; wandering scratches (C.g read ±1 px per frame); reel-change cue dot every 264 frames | none | (rgb.r, scratch, 0, alpha) kept |
| scanline-drift | tape-stretch shear into the next strip; h-sync porch at the wrap seam; drift-velocity smear | dead `plasmaBuffer[stripBin]` term removed (read 0; no look change) | ACES display RGBA |
| glass-brick-distortion | 6 fluted ribs per brick + crest glint; grout-edge mirror bevel + specular line; per-brick batch tint/thickness | none | ACES display RGBA |
| paper-cutout | height-weighted shadows; lit cut edge (white core) + far dark rim; hand-cut per-layer jitter | dead `plasmaBuffer[layerBin]` removed; peak limiter → ACES ×0.72: midtones kept, whites 1.0→0.72 (dimmer top sheets) | ACES display RGBA |

Kept verbatim everywhere: slider roles, saved params/updatedParams (byte-checked vs HEAD), bindings, 16×16.
HEAD springs in extraBuffer[133..138] (files 5–8) are no-ops (range zeroed per frame); left in place, none added.

Gates: precommit/naga 8/8; audit:extrabuffer PASS; audit:dead-sliders PASS (7 defs; pyro has only
updatedParams, so checked by hand); generate_shader_lists + check_duplicates OK (1386 unique); Jest 741 pass /
6 known `.js`-import suite failures (pre-existing on main); SKIP_WASM_BUILD=1 build green.
Real-GPU visual QA: external, not done.
