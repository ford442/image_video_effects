# gen-symbiotic-cyber-fungal-core-reactor (tracker #336) — INTERACTIVIST upgrade

## Weaknesses found (original 184-line shader)

1. **Fake audio** — `let audio = u.config.y;` read `config.y` (rippleCount) as
   "audio-reactive spore emission". No `plasmaBuffer` use at all.
2. **Broken Mutation Rate slider** — `mutation_rate = u.zoom_config.w`, which is
   engine-owned mouseDown (>0.5 pressed). The declared slider could never be live.
3. **1:1 mouse mapping** — the core singularity teleported to the raw cursor
   every frame; no inertia, no attractor dynamics, no click behavior.
4. **No feedback memory** — `dataTextureA` never written, `dataTextureC` never
   read; zero temporal accumulation.
5. **Contract gaps** — no `writeDepthTexture` write, hardcoded alpha `1.0`,
   ripples ignored, no tone mapping.

## Techniques applied (interactivity domain)

1. **Mouse gravity-well attractor** — spring-damper smoothed cursor
   (extraBuffer[133..136] pos/vel, canonical gen-lichtenberg-storm layout) plus a
   slow autonomous drift; the core *hunts* nutrients instead of teleporting.
2. **Click spore-burst shockwave** — rising-edge detector (extraBuffer[137/138])
   spawns a bounded (`exp(-age*1.4)`) expanding ring that swells the gyroid field
   in `map()` and flashes the surface; hold-to-mutate reuses `zoom_config.w`
   truthfully as a mutation surge (`0.1 + mutate*0.5`, preserving the old 0.1
   default rate). Engine ripples (guarded `min(u32(u.config.y),50u)` loop) add
   nutrient rings that feed the bloom.
3. **Real audio morphing** — bass → core growth pulse + glow gain + warm vein
   emission; mids → gyroid lattice phase morph + drift amplitude; treble →
   surface spore sparkle; guarded FFT bins 1–8 (`extraBuffer[6..13]`,
   `arrayLength` guard) split into fft_lo/fft_hi driving bioluminescence and
   emission rate.
4. **Temporal feedback memory** — `dataTextureC` read via non-filtering
   `textureLoad`; trail buffer (`dataTextureA.rgb`, decay 0.90–0.96 driven by
   Mycelium Spread) + nutrient channel (`.a`); history steers the live frame so
   growth self-organizes along established channels.

## Slider wiring (all live, shader-specific)

- **p1 Core Density** → core singularity radius (bass-modulated) + negative-color-space threshold.
- **p2 Mycelium Spread** → gyroid/core blend **and** feedback trail persistence.
- **p3 Quantum Noise** → cellular-fbm noise amplitude in the distance field.
- **p4 Temporal Shift** → global time scale (mutation, camera, drift).
- `zoom_config.w` ("Mutation Rate" control) is engine-owned mouseDown — rewired as
  hold-to-mutate surge (truthful uniform semantics; slider slot documented, the 4
  real sliders moved to updatedParams).

## Contract compliance

- Canonical 13 bindings verbatim; Uniforms struct exactly `config, zoom_config, zoom_params, ripples`. ✅
- `@compute @workgroup_size(16, 16, 1)` + resolution bounds guard. ✅
- Every frame writes: `writeTexture`, `writeDepthTexture` (raymarch hit depth
  `t/10`, miss = 1.0 — real generated depth), `dataTextureA` (trail+nutrient). ✅
- Audio ONLY `plasmaBuffer[0].xyz` + guarded FFT bins 1–8 (no hash spectrum). ✅
- Feedback reads via non-filtering `textureLoad(dataTextureC, px, 0)` only. ✅
- Ripple loop guarded `min(u32(u.config.y), 50u)`. ✅
- Semantic alpha (luminance density + glow + ripple, clamp [0.06, 1.0]). ✅
- Persistent state ONLY extraBuffer[133..138], single-writer guard
  `gid.x==0u && gid.y==0u` + `arrayLength` check; FFT bins read-only. ✅
- No `textureSample`/`dpdx`/`tan`; ACES tone map added; soul preserved
  (raymarched gyroid mycelium + core singularity + negative color space).

## JSON

Additive: appended `workgroup_size`, `updated` (true), `supportsDepth`,
`supportsDof`, `features`, truthful description extension, and **4 new indexed
updatedParams** (index 0–3 = zoom_params.x/y/z/w mapping order) copied from the
existing controls — ids/labels, defaults, min/max/step verified programmatically
to match (`Core Density 1.0/0.1–5.0/0.1`, `Mycelium Spread 0.5/0–1/0.05`,
`Quantum Noise 0.3/0–1/0.01`, `Temporal Shift 1.0/0–2/0.1`). The `zoom_config.w`
"Mutation Rate" control is intentionally excluded (engine-owned mouseDown
channel). Effective defaults preserved — WGSL still consumes raw zoom_params
ranges directly.

## Gate result

`python3 scripts/wgsl_precommit_gate.py --files …` → **PASS** (naga OK,
bindgroup compatible, 0 extraBuffer violations). Dead-slider audit: PASS (0 dead).
