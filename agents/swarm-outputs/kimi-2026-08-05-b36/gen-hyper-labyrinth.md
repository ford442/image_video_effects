# gen-hyper-labyrinth — Visualist upgrade (Batch 36, tracker #326)

201 → 268 lines (+67). Gate: **PASS** (naga OK, bindgroup compatible, 0 extraBuffer violations).

## What changed

**Lighting (new):**
- 3-point rig replacing the single diffuse light: dynamic-temperature warm key
  (`keyTemperature` drifts ember-amber ↔ arc-white with time + bass), cool
  cyan-blue fill from the opposite octant, violet ambient. Two distinct
  light temperatures as required.
- Blinn-style HDR specular from the key light on the metallic walls.
- Fresnel rim kept (shader's soul) but treble-reactive and re-tinted electric blue.

**Atmosphere (new):**
- Volumetric proximity glow accumulated inside the existing raymarch loop
  (`exp(-|d|*9)*0.02` per step, bounded ≤ 2.0) — neon haze/god-ray bleed near walls.
- Fog now inscatters: scatter color picks up persisted neon + proximity glow
  instead of a flat dark blue; void pixels are tinted by nearby neon haze.

**Color/grading (new):**
- ACES filmic tone map with mids-driven exposure (0.85 + mids*0.25).
- HDR throughout: veins reach ~6–7 pre-tonemap (glow slider × bass pulse × FFT
  shimmer), rim up to ~3.7 — well above the >1.0 highlight bar.

**Audio (new):** bass → vein pulse amplitude + key warmth; mids → exposure;
treble → rim strength; guarded FFT bins 1–8 (`arrayLength > 13u`) → spectral
shimmer on the neon veins. No hash-based fake spectrum.

**Feedback (new — invariant fix):** `dataTextureA` was never written; now it is
the neon-history channel. Emissive is persisted (`max(neon, prev*0.90)`), giving
afterglow smear while orbiting; written every frame along with writeTexture and
writeDepthTexture.

**Depth (fixed):** was `t/50` (far-is-one); now `exp(-t*0.12)` — near-is-one,
miss ≈ 0.0025 (effective far plane).

**Alpha (fixed):** was hardcoded 1.0. Walls = 1.0 (opaque by design); void =
`clamp(0.08 + volGlow*0.55, 0, 0.85)` — semi-transparent haze.

## Preserved
Canonical 13-binding header, Uniforms struct field order, 4D gyroid SDF, camera
rig, all 4 sliders live in updatedParams index order (x=scale, y=morph speed,
z=glow, w=thickness). JSON: only `features` array populated (additive);
`updatedParams` byte-exact.

## Perf estimate
+1 exp per raymarch step (100 max) and +1 textureLoad per pixel; map() call count
unchanged. ≈ +3–5% GPU cost over the original at 1080p.
