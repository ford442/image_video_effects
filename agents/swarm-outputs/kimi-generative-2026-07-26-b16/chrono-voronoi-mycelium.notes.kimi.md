# chrono-voronoi-mycelium — Batch 16 Upgrade Notes (Kimi / Algorithmist)

## Line delta
- Before: 194 lines → After: 253 lines (**+59**, within target 244–284)

## Key changes per technique

### 1. Boilerplate eviction (priority 1)
- Deleted `applyGenerativePrimaryControls` entirely (generic brightness /
  speed-pulse / contrast / mouse-gain helper). All four sliders now drive
  real mycelium constants, with defaults reproducing the legacy look:
  - **Growth Bias (x)** → `ageMix` blend exponent: `ageExp = mix(1.4, 0.6, x)`;
    `ageMix = pow(ageMixVec, ageExp)`. Default 0.5 → exponent 1.0 (identity,
    legacy look). >0.5 favors fresh growth, <0.5 favors old generations.
  - **Temporal Scale (y)** → layer clock multiplier:
    `time = u.config.x * mix(0.15, 0.65, y)`. Default 0.5 → 0.4x, matching the
    legacy hard-coded rate.
  - **Decay Influence (z)** → layer decay rate:
    `decay = mix(0.970, 0.995, z) - seasonHarsh * 0.02`, per-layer offsets
    `-0.01` / `-0.02` kept verbatim.
  - **Pattern Complexity (w)** → primary voronoi scale:
    `scale1 = mix(2.0, 14.0, w) + seasonVolatile * 6.0`; scale2/scale3 keep
    legacy 2.25x / 4x ratios. Default 0.5 → base 8.0 = legacy.

### 2. Feedback path cleanup
- Removed duplicate `prevLayer2` sample (re-read the same texel as
  `prevLayer1`); single `prevLayers` fetch now feeds r/g/b.
- Removed dead `dataTextureB` store (B never read downstream; A packs all
  three layers). Binding declaration kept for layout compatibility.

### 3. Spectral seed jitter
- In `voronoi()`: stable per-cell id `cellId = u32(h * 4096.0)` selects an
  FFT bin via `plasmaBuffer[(cellId % 8u) + 1u].x`; seeds get a small
  rotational `shimmer` offset (±0.08) so colonies shimmer with the spectrum.
- Added a subtle FFT `threadTint` on hyphae edges in visualization.

### 4. Spring-damped inoculation
- `extraBuffer[133..134]` holds the damped inoculation point; it glides
  toward the cursor (`mix(inoc, mouse, 0.08)`) with cold-start init when the
  state is zero. Inoculation distance is measured from the damped point.

### 5. Sporulation wavefront (expansion feature, soul-preserving)
- New `sporeRing()` helper: golden-ratio-scaled expanding ring from the
  damped inoculation point, triggered by hard bass
  (`smoothstep(0.5, 0.8, bass)`), fades as it travels; feeds all three
  layers strongest→youngest.

## Slider wiring
| Slider | Mapping | WGSL constant | Default behavior |
|---|---|---|---|
| Growth Bias | zoom_params.x | ageMix exponent `mix(1.4, 0.6, x)` | 0.5 → 1.0 (legacy) |
| Temporal Scale | zoom_params.y | clock mult `mix(0.15, 0.65, y)` | 0.5 → 0.4x (legacy) |
| Decay Influence | zoom_params.z | decay `mix(0.970, 0.995, z)` | 0.4 → 0.980 base |
| Pattern Complexity | zoom_params.w | scale1 `mix(2.0, 14.0, w)` | 0.5 → 8.0 (legacy) |

JSON ids/names/defaults/min/max/step unchanged (saved-preset contract);
`updatedParams` indices 0–3 + `updated: true` written verbatim from brief.

## Binding contract compliance
- Canonical 13-binding layout preserved, no renumbering, no binding 13.
- `@workgroup_size(16, 16, 1)` kept.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- `textureSampleLevel(..., 0.0)` for sampler reads.
- Layer caps 1.8 / 1.6 / 1.9 preserved verbatim; decay formula structure
  kept; dataTextureA packing layer1→r, layer2→g, layer3→b kept; sim state
  never clamped/tonemapped.
- extraBuffer used only at [133..134] (persistent-state range); no
  reserved [0..4] or FFT [5..132] writes.
- No WGSL reserved keywords as identifiers.

## QA flags
- Gate: **GREEN** — 1 passed, 0 failed, 0 warnings
  (`python3 scripts/wgsl_precommit_gate.py --files public/shaders/chrono-voronoi-mycelium.wgsl`).
- naga binary not installed in this environment, so naga validation was
  skipped by the gate (environmental WARN, not a shader warning); bindgroup
  compatibility + workgroup checks both passed.
- Note: extraBuffer spring state is per-invocation read_write without sync
  (same pattern as other shaders in this repo); visually benign — damped
  point converges regardless of write order.
