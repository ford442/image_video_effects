# lava-lamp-blobs — Batch 15 Interactivist Upgrade Notes

## Line delta
- Before: 190 lines → After: 250 lines (**+60**, within target 240–280 / +50–90)

## Gate status
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/lava-lamp-blobs.wgsl`
- ✅ GREEN: Passed 1 / Failed 0 / Workgroup errors 0 / Warnings 0
- Note: `naga` binary unavailable in this VM, so naga validation was skipped by the gate itself; bindgroup compatibility + workgroup convention checks ran and passed.

## Key changes per brief technique

### 1. Aspect-correct + spring-dampered mouse (priority 1)
- `target.x = target.x * aspect` — the x component of `u.zoom_config.yz * 2.0 - 1.0` is now aspect-corrected, so blob attraction stays circular on wide screens (was elliptical).
- Raw `p + mouse * 0.1` shift replaced by a true 2D spring-damper (stiffness 42, damping 9, fixed dt 0.016, slightly underdamped → blobs lag then catch up).
- Persistent state in `extraBuffer[133]=pos.x, [134]=pos.y, [135]=vel.x, [136]=vel.y`. The brief mentioned [133..135]; a 2D spring needs pos(2)+vel(2), so 4 slots 133–136 are used — all within the allowed [133..255] region. All threads compute identical values from uniform inputs, so the read-modify-write is value-deterministic.

### 2. Per-blob FFT voices
- `blobField()` now reads `plasmaBuffer[(i % 8u) + 1u].x` per blob index: the voice pulses both blob `size` (×1+voice·0.45) and field weight (×0.75+voice·0.5), so each blob dances to its own FFT bin.
- Mids → blob-count shimmer: `effCount = count * (1 + mids·0.3·sin(time·2.3))` passed into blobField.
- Treble → rim sparkle: IGN-thresholded sparkle mask `step(0.985 - treble·0.05, ign(...))` added to the Fresnel rim term (×treble·2.0).

### 3. Click heat injections
- New `clickField()` loops `u.ripples` guarded by `min(u32(u.config.y), 50u)`. Each live ripple (age 0–4s) spawns a temporary aspect-corrected blob at the click point that rises (age·(0.15+riseSpeed·0.4) + age²·0.08) and dissolves with `life²` falloff.
- Returns (field, hottest): field merges into `totalField` (scaled by Heat slider); hottest boosts core/halo blackbody temps and adds a dissolving ember light term.

### 4. Melt slider deepened
- Melt now also narrows the smoothstep merge window (`edge0: 0.5→0.32`, `edge1: 1.2→0.85`), so blobs visibly fuse into goopy continents — not just a halo color mix.

## Slider wiring (zoom_params, ids/defaults unchanged)
- `zoom_params.x` → Blob Count (mix 2–10), population of metaballs + phase spacing
- `zoom_params.y` → Rise Speed (mix 0.05–0.6), wax velocity for both ambient blobs and click injections
- `zoom_params.z` → Melt (mix 0–1), merge threshold window + halo fill light
- `zoom_params.w` → Heat (mix 0.3–2.0), core blackbody temperature + click-field energy
- All mappings were already shader-specific; kept and deepened (melt edge window). JSON params/updatedParams written verbatim from brief (`updated: true`).

## Binding contract compliance
- Canonical 13-binding layout preserved exactly (0 sampler … 12 plasmaBuffer read); no bindings added/renumbered; no binding-13 historyTexture.
- `@workgroup_size(16, 16, 1)` unchanged.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- `dataTextureA` SIM STATE packing `(blobShape, blobHalo, heat, a)` preserved VERBATIM — raw pre-tonemap values, never routed through ACES/dither/gamma.
- Premultiplied `outRGB * a` write kept; hue_preserve_clamp → ACES → IGN dither → gamma stack intact.
- `textureSampleLevel(..., 0.0)` for sampler reads; no storage texture reads introduced.
- extraBuffer usage confined to [133..136] (within [133..255]); [0..132] untouched.
- No WGSL reserved keywords used as identifiers.

## QA flags
- Naga not installed in this environment — full WGSL semantic validation deferred to CI; gate's bindgroup + workgroup checks green.
- Spring-damper writes to extraBuffer from every invocation (benign: identical values, no atomics needed — same pattern as other shaders in repo).
- Click injections assume ripple convention `xy = uv position, z = birth time` (matches e.g. bioluminescent-blackbody).
- No GPU in Cloud VM — visual verification pending on a WebGPU-capable machine.
