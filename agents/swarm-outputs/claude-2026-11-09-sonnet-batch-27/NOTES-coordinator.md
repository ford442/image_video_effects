# NOTES — coordinator (anamorphic-flare)

Harness: SwiftShader WebGPU render harness (rgba32float, extraBuffer rewritten every frame). Structural / PNG evidence only — **no real-GPU visual QA claimed.**
All renders: `node $H/render.mjs <wgsl> <png> --size … --frames … --params … --mouse … --src photo --hdr 2.5` with `H=/tmp/claude-0/-home-user-image-video-effects/d42ad8f0-8e0e-5ffd-959e-50bf3ecd73aa/scratchpad/harness`. Isolated-flare renders use a scratch copy with `aces(baseColor.rgb + flareColor)` → `aces(flareColor)` so the flare is seen on black.

## anamorphic-flare (`public/shaders/anamorphic-flare.wgsl`, JSON `interactive-mouse/anamorphic-flare.json` unchanged)

**Identity kept:** cursor light → threshold-gated horizontal blue streak + blue line, hex ghosts along the optical axis, central glow, rays, starburst, rainbow halo, ACES, flare alpha. Params `width / intensity / color / threshold` → `zoom_params.xyzw` unchanged and all four still consumed (dead-slider audit PASS).

**KEEP VERBATIM (checked in the diff):** gate (`highlightGate` from the pixel under the cursor), streak/blue-line construction (`hStreak`·0.9 + `vStreak`·0.1, `baseTint`, blue-line offset 0.018 / 0.85 length / 0.55 gain), ghost count and `ghostOffset` / `ghostSize` laws, `centralGlow` constants, starburst/halo/rainbow maths, bass/treble gain, ACES, alpha, depth passthrough.

**A packing:** ACES display RGBA (unchanged). No state, no springs, no ripples.

### Ideas (each findable by its `// ── Idea n` comment)
1. **Oval 2:1 anamorphic ghosts** — `ANAMORPHIC_SQUEEZE` (L78) applied to the ghost disc coordinates in `ghostElement` (L84) and to the outer aperture in the loop (L186). An anamorphic lens squeezes the image 2:1, so iris images are hexagons stretched ×2 along x; HEAD drew round hexes. (Tactic 5, device artifact; not a §12.2 row.)
2. **Power-law glare tail** — `glareTail()` (L114) = `r0²/(d²+r0²)·exp(-2d)` in aspect-corrected distance, added at L195. §12.2F **Soft inverse-square** (this file only). Probe, post-ACES, 0.1 / 0.2 / 0.3 frame-heights above the source: with 0.49,0.56,0.64 / 0.074,0.095,0.13 / 0.006,0.008,0.009 vs without 0.33,0.41,0.53 / 0.027,0.038,0.060 / 0.000,0.001,0.001 — a veil that reaches ~0.2 instead of ending in the core.
3. **Per-channel streak extent** — `anamorphicStreak` (L61–70): `ext = (1−0.45dd, 1, 1+0.8dd)` with `dd = 0.25 + dispersion` scales the streak length per channel, so the colour fringe lives in the extent (blue-white core, deep-blue tail) instead of HEAD's blue-tint-multiplied-by-distance. The 0.25 baseline makes it readable at the default Color Shift 0 (HEAD's `spectralDispersion` was (1,1,1) there). `spectralDispersion` is kept for the ghosts.

### Rescues (not counted as ideas; found by rendering HEAD)
- **R1 aspect-correct radial terms** (L141): glow, rays, starburst, halo and ghost shapes were measured in raw uv → ellipses on 16:9 (visible in the 512×256 HEAD render). Streak and blue line stay in uv. Identical at aspect 1.
- **R2 ghost aperture centre mismatch** (L181–186): HEAD centred the outer aperture at `0.5 + (0.5−L)·offset·2` but the disc at `… + offset`, so the product of the two hexes was a clipped sliver / parallelogram (the only "ghost" visible in HEAD renders), not an iris image. Both now share the ghost centre. This is a **deliberate default-look change**: ghosts are now whole soft oval hexes, so per-ghost gain is ×0.55 and the disc edge is softened (`hexagonAperture(…, soft)`) to keep the total flare weight near HEAD. The card said "ghost geometry stays HEAD's"; the renders showed that geometry was a bug, so the card was amended here rather than silently.
- **R3 `pow(sin(..), 4.0)`** in `volumetricRays` (L97): negative base is undefined (NaN on real GPUs); rewritten as `sin⁴` product, identical for valid inputs.

### Default-look change: yes (ideas + R2). Harness numbers (photo, `--hdr 2.5`, mouse 0.62,0.36, params 0.5,0.5,0,0): meanL 0.5752 → 0.5685, stdL 0.2047 → 0.2103; params 0.5,1,0.5,0: meanL 0.6236 → 0.6106, stdL 0.2025 → 0.2095; nan 0 in every render (192 + 576, audio 0.8,0.5,0.9, params 1,1,1,0.4).
Formula rows: Soft inverse-square (F). Lens-flare ghosts row NOT used.
Gates: Naga (naga-wasm) valid; `wgsl_precommit_gate.py` pass; dead sliders PASS.
Open: the horizontal streak is hard to see on a bright sky (also true of HEAD — ACES compresses blue added to pale blue); it reads clearly on darker backgrounds. Real-GPU QA external.
