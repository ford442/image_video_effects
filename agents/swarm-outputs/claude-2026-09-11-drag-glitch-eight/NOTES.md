# NOTES — drag-glitch-eight (2026-09-11)

All 8 files already sat on the plumbing floor (13 bindings, `@workgroup_size(16,16,1)`,
ACES, semantic alpha, spring/ripple systems where applicable) before this batch. This
was pure Idea-Card work: 2 native ideas per shader, kept the existing algorithm/kernel/
param roles verbatim.

| ID | Kept verbatim | Ideas actually in the diff | A packing |
|---|---|---|---|
| `glitch-ripple-drag` | spring in extraBuffer[133..138], displacement formula, quantized-angle glitch, persistence trail | velocity-scaled chroma spread (`chromaSpread`); held-pointer strobe latch (`waveTime`) | display RGBA (unchanged) |
| `pixel-drag-smear` | brush/strength/decay/mode params, curl noise, lumaMix, velocity tint, comb/spectral, ripple fronts | bristle streak sampling (3-tap average along `offset`); treble-split pigment bleed (`bleedR`/`bleedB`) | display RGBA (unchanged) |
| `slinky-distort` | coils/amplitude/depthWeight/tightness, normal+tangent displacement, colorShift, bass crest, advanced alpha | elastic overshoot echo (lagged spiral phase read from `dataTextureC`); treble compression pulse (`compression` term in `spiralPhase`) | display RGBA — newly read back C for the echo (HEAD wrote A but never read C) |
| `cyber-trace` | spring-follow in extraBuffer[133..138], HSL hue-cycle, history decay, band shimmer, glow/alpha | velocity-oriented arc stamp (capsule distance along `mouseVel`); treble circuit sparks (hashed perpendicular ticks) | history RGB in A (unchanged) |
| `neon-contour-drag` | dual-scale sobel blend, mouse warp, hue by distance/time, contourRunner/hueConveyor, click rings, hotCore, emissive alpha fn | edge-tangent glow streaks (sobel now returns gradient direction, re-samples along tangent); bass core pulse (`hotCore` threshold reactive to bass) | emissive RGBA, no history (unchanged) |
| `cyber-slit-scan` | slit column sampling, diagonal-tear source-row logic, conveyor decay, click-front glow, hue rotation | second lagged scan head (phase-offset sweeping band, own slit column/hue); treble artifact bursts (`bitCrushEffective`) | display RGBA in A (unchanged) |
| `temporal-echo` | accumulativeAlpha/depthLayeredAlpha fns, brightness-driven history_offset, ripple-pin logic, echoDecay blend | user-controlled echo depth (`temporalOffset`, previously read but unused — now an additive frame-lag bias); bass-transient echo pinning (single-writer prevBass in extraBuffer[133], rising-edge detection) | accumulated RGBA in A (unchanged) |
| `viscous-drag` | RG offset diffusion/advection via C, viscosity/dragStrength/recovery/scale, vortexForce, click force/pressure, specular lighting, ACES | shear-thinning viscosity (prior frame's `.w` dragEnergy thins the diffusion mix locally); bass jet surge (secondary jet direction blended in on bass) | RG offset/thickness/dragEnergy raw sim state (unchanged) |

## Fixes applied alongside the ideas (floor, not the upgrade itself)

- `temporal-echo`: `audioOverall` was reading `u.zoom_config.x`, which duplicates
  `config.x` (time) per `docs/BINDING_CONTRACT.md` — not audio. Real audio now reads
  `plasmaBuffer[0].x`. Also removed a dead, unused `prev` sample that used a filtering
  sampler on the `rgba32float` history texture (against the "exact load" convention),
  and clamped the `past` history lookup coordinates, which were previously unbounded
  and could read outside `dataTextureC`.
- `cyber-slit-scan`: three pre-existing `color.rgb = …` / `outputColor.rgb += …`
  swizzle assignments failed `naga` ("WGSL does not support assignments to
  swizzles") — this was already broken before this batch (naga wasn't installed in
  this session until now). Rewrote as whole-vector reconstructions. Also renamed the
  JSON's 4th param from `"Unused"` to `"Artifact Amount"` — the WGSL already reads it
  as `artifactAmt` and uses it; the label was a pre-existing lie (§8 "tell the truth").

## Gates

```
python3 scripts/wgsl_precommit_gate.py --files <8 files>   # naga OK, bindgroup compatible — 8/8
npm run audit:extrabuffer                                   # 0 new violations
python3 scripts/audit_dead_sliders.py --files <8 ids>        # 0 dead sliders (temporalOffset now wired)
node scripts/generate_shader_lists.js                        # clean regen
npx craco test --watchAll=false --ci                          # 97 suites, 662 passed / 1 skipped
SKIP_WASM_BUILD=1 npm run build                               # compiled successfully
```

`naga` was not installed in this session (`cargo install naga-cli --locked`, ~90s).
`node_modules` was also absent; `npm install` (~40s) was run once to enable Jest/build.

Real-GPU visual QA: external — this session has no GPU.
