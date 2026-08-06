# gen-magnetic-dipole-field — Optimizer note (Batch 38, tracker #346)

## Weaknesses found (performance / elegance / motion)

1. **4× redundant field evaluation per pixel** — `sampleField()` (dipole field +
   two particle loops) was evaluated 4 times: 3× for chromatic R/G/B taps plus a
   ghost dipole. Particle loops (up to 11 + 8 hash-heavy iterations) were fully
   recomputed in every tap.
2. **Missing contract items** — no resolution bounds guard in `main`;
   `dataTextureA` was never written (feedback read from `dataTextureC` but the
   state channel was never stored → black history on engines that require A).
3. **Strobing hash jitter** — "magnetic storm shimmer" used
   `hashf(dot(uv,…) + time*8.0)`, a per-frame white-noise strobe that gets worse
   at speed.
4. **Slow, structurally-blind particle motion** — particles orbited in small
   circles around the dipole (`p_time * 0.3`), ignoring the field-line geometry
   that is the shader's soul; "Particle Speed" slider had limited range.
5. **No frame-rate independence / no HDR bound** — feedback `max()` accumulate
   with unbounded `prev` could ratchet brightness; motion was slow rather than
   fast.
6. Audio used `bass` only; alpha collapsed to 0 whenever `depth == 0`.

## Techniques applied (⚡ fast-motion ones called out)

- **⚡ Analytic closed-form field-line advection** — particles now ride actual
  dipole field lines using the closed form `r = L·sin²θ`; position is a pure
  function of `(hash seed, time)` — O(1) per particle, no per-frame integration,
  inherently frame-rate independent. Triangle-wave phase bounces particles
  pole-to-pole with **no wrap jump**. Speed scaled by the existing Particle
  Speed slider (`0.4 + p2·3.5`) with a bass boost — genuinely fast at high p2.
- **⚡ Velocity-aligned motion-blur feedback** — previous frame is fetched with
  `textureLoad` at `pixel − round(B_dir · blur_px)` so trails streak *along* the
  local magnetic field (particle velocity is tangent to B). Displacement clamped
  ≤ 22 px; **HDR history hard-clamped ≤ 6.0** (Batch-36 lesson) so speed can
  never blow up the loop. State written to `dataTextureA` every frame.
- **Loop/branch pruning via evaluation split** — single full `sampleField` call;
  the ghost dipole uses a `withParticles=false` cheap variant; chromatic
  aberration is now an **analytic tangential R/B split** (bounded by
  `field_intensity/(1+field_intensity)`) instead of 2 extra full evaluations.
  Net: ~4× less particle/field math per pixel.
- **Hoisted time-invariant terms** — dipole B-field factored into `dipoleB()`
  (shared by field lines, motion-blur direction, ghost); per-particle hashes are
  pure seed functions computed once per particle; named constants
  (`HDR_CAP`, `MAX_PARTICLES`, `MAX_IONS`, `TAU`) replace magic numbers;
  iteration counts explicitly bounded with `min(...)`.
- **Stability for speed** — storm shimmer converted to smooth temporal-coherent
  `valueNoise` (no strobe); all velocities/displacements clamped; audio adds
  guarded FFT bins 1–8 (`arrayLength` check) driving the fast-ion count and
  shimmer; alpha floored at 0.05 and depth term softened so the shader stays
  visible when source depth is 0.
- **HDR-ready pipeline** — HDR color is written to `dataTextureA`; ACES tone map
  is presentation-only, exposure lifted by `mids`.

## Slider wiring (all 4 LIVE, byte-exact JSON)

- p1 **Field Strength** → dipole moment + primary particle count (4–14).
- p2 **Particle Speed** → field-line advection speed + motion-blur length + pulse rate (SPEED governor).
- p3 **Line Density** → field-line density (4–24).
- p4 **Color Shift** → palette hue offset.

## Contract compliance

Canonical 13 bindings verbatim; Uniforms struct exact; 16×16×1; bounds guard
added; `writeTexture`/`writeDepthTexture`/`dataTextureA` written every frame;
`textureLoad`-only feedback; audio only from `plasmaBuffer[0].xyz` + guarded
FFT bins 1–8; no extraBuffer writes; semantic alpha; generated relief depth
(field intensity × particle density); no ripples used.

## Gate result

`python3 scripts/wgsl_precommit_gate.py --files …` → **PASS** (naga OK,
bindgroup compatible, no extraBuffer violations). `updatedParams` diff vs
`git show HEAD:…` → IDENTICAL. JSON edits additive only (features + description).
