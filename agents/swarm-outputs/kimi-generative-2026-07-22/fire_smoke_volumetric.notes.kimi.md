# Notes: fire_smoke_volumetric (Visualist upgrade, 2026-07-22)

**Role:** Visualist
**Gate:** `wgsl_precommit_gate.py` — exit 0, naga OK, bindgroup compatible, 0 warnings

## Key changes

- **Worley-noise ember sparks**: added `worley()` (3×3 cell search via canonical `hash21`/`hash22`) and an `emberField()` helper. Cells scroll upward (`uv.y * 9.0 - time * 1.6`), sharpened with `pow(1-w, 14)`, per-cell twinkle, masked by `fireShape` and faded toward the top, tinted by the existing chromatic temperature gradient. Restrained: scaled by `fireIntensity * 0.35`, alpha contribution clamped to 0.25 max so embers never dominate the smoke.
- **Feedback stability clamp**: temporal smoke path is now `min(prevSmoke * decay, vec3(1.2))` before blending, and the `dataTextureA` write (which feeds next frame's `dataTextureC`) is explicitly clamped at 1.2 — smoke buffer can never run away or lock to white (luma-echo-warp lesson). Note: `dataTextureA` now carries the persistent smoke state rather than `finalColor`, matching the feedback semantics.
- **Treble-reactive edge flicker**: turbulence amplitude now multiplied by `edgeFlicker = 1.0 + treble * 0.8`, so the flame silhouette crackles on high-frequency audio content.
- **Slider rewiring** (all 4 now drive real shader constants; ids/defaults/mappings untouched):
  - `fireIntensity` (p1): core heat — drives gradient temp, ember intensity, and a brightness scale on `fireColor`.
  - `smokeDensity` (p2): soot density AND volumetric slab thickness (`0.6 + p2 * 2.4`), which feeds both `opticalDepth` and `volumetricAlpha`; also lengthens the smoke trail via `decay` and `smokeBlend`.
  - `depthWeight` (p3): now also lowers the far-layer occlusion floor (`mix(0.45, 0.15, p3)`) in `depthLayeredAlpha`, not just the blend weight.
  - `turbulence` (p4): flame-silhouette distortion amplitude, bass-boosted and treble-crackled; also bends the ember column sideways.
- Core algorithm preserved: same hash-driven silhouette, chromatic temperature gradient, physical transmittance, depth-layered alpha, ACES output, all 3 mandatory writes every frame.

## Line count delta

- Before: 117 lines
- After: 181 lines (+64, within the +50…+90 / 167–207 target)

## QA flags

- **No GPU in this VM** — naga validation and bindgroup compatibility pass, but visual QA is deferred to a real GPU run.
- **Eyeballed constants to verify visually**: ember scroll speed (1.6), cell scale (9.0), sharpen exponent (14), ember gain (0.35) and ember alpha cap (0.25); feedback clamp at 1.2; slab thickness range (0.6–3.0); treble flicker gain (0.8). These were tuned by reasoning, not by looking at output.
- **Verify on GPU**: embers should read as sparse rising sparks, not static dots or noise; smoke trail should not accumulate to white over time at high Smoke Density; treble hits should visibly crackle the flame edge without jittering the whole silhouette.
