# Optimizer note — gen-chrono-kitsune-prism-weaver (tracker #338)

## Weaknesses found
- **Uniform-truth violation**: `audio = u.config.y` (that's rippleCount), and the
  mouse was computed as `zoom_config.yz / dim` — but `zoom_config.yz` is already
  0–1 uv (Batch 23 normalized-pointer bug class). Both fixed.
- **Missing writeDepthTexture store** — never written; contract requires it every frame.
- **Alpha hardcoded 1.0**; LDR tone map (`col/(1+col)`) baked into the feedback
  chain, clipping the temporal accumulation to LDR.
- **Feedback read via `textureSampleLevel(dataTextureC, u_sampler, …)`** — contract
  requires non-filtering `textureLoad` for rgba32float feedback.
- **Perf**: 6-tap central-difference normal; tail-count `clamp(floor(...))`
  recomputed inside every SDF evaluation of the march; no ray early-out for the
  large background; magic numbers everywhere (80 steps, 40.0 far, 0.7 relax, …).
- **Dead logic**: `if (d == d_tails || d < d_body)` float-equality material test.

## Techniques applied (Optimizer domain)
1. **Bounding-sphere early-out** — analytic ray–sphere test against a bound
   (center (0,0,14.5), r=12) covering body + all tail arcs; background rays skip
   the entire march. At 16:9 roughly half the screen avoids ~72 SDF evaluations.
2. **Tetrahedral normals** — 4 SDF taps instead of 6 (−33% normal cost).
3. **Hoisting** — `tail_count` (i32) and `weave` computed once per frame and
   passed into `mapKitsune`/`calcNormal`; `1/count` precomputed; all magic
   numbers promoted to named module-scope constants.
4. **HDR-ready pipeline** — HDR color + HDR feedback mix (decay-bounded,
   `min(col, HDR_CEIL=8)`), stored to dataTextureA for slot chaining; ACES tone
   map applied only for presentation (writeTexture).

## Slider wiring (all 4 live, byte-exact JSON params)
- p1 Prism Hue Shift → hue offset for surface + glow palettes (existing role).
- p2 Tail Count → `tail_count = clamp(floor(p2*9), 3, 9)` (existing role).
- p3 Weave Tightness → `weave = 1 + p3*3` tail wave frequency (existing role).
- p4 Chrono Echo → feedback mix factor + displacement amplitude + click-boosted
  echo warp.

## Performance notes
- March bounded: `RAY_STEPS=72`, `SURF_EPS=0.01` break, `FAR_CLIP=40` break,
  plus bounding-sphere pre-test (biggest win).
- Normal: 4 taps. Tail loop bounded 3–9 (slider-driven), `smin` chain unchanged.
- Guarded FFT bin loop bounded 1–8 with `arrayLength` check.

## Contract compliance
- Canonical 13-binding header verbatim; Uniforms struct exactly
  `config, zoom_config, zoom_params, ripples` (reordered to canonical).
- `@compute @workgroup_size(16, 16, 1)` + resolution bounds guard. ✔
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame. ✔
- Audio ONLY `plasmaBuffer[0].xyz` (bass glow/hue, mids hue/exposure, treble
  shimmer) + guarded FFT bins 1–8 (read-only, indices 5–12). ✔
- Feedback reads via `textureLoad(dataTextureC, clamped_px, 0)` only;
  dataTextureA = HDR history, writeTexture = presentation. ✔
- Semantic alpha = presence intensity (hit + glow + luma), not hardcoded. ✔
- Real generated depth: `t/FAR_CLIP` hit distance with glow relief, 1.0 on miss. ✔
- No persistent extraBuffer state used; no ripple loops (none needed). ✔
- No reserved identifiers; no textureSample/dpdx; textureSampleLevel removed. ✔

## JSON
`updatedParams: [0,1,2,3]` byte-exact (verified vs `git show HEAD:`). Additive
only: description extended truthfully, features += temporal-feedback,
hdr-output, semantic-alpha, depth-output.

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files …` → **PASS** (naga OK,
bindgroup compatible), exit 0.
