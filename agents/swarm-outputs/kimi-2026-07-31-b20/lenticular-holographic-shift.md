# Notes: lenticular-holographic-shift (Batch 20, Visualist)

## Line counts
- Before: 105 lines
- After: 166 lines (+61, inside target 155–195 / +50..+90)

## Bugs fixed
1. **A-slot role fix (priority 1):** `dataTextureA` previously received the mask
   quad `(strip, moire, viewAngle, semantic_alpha)`, poisoning chained slots that
   read C (= prev A) expecting COLOR. Now:
   - `dataTextureA` ← display color `vec4(col, semantic_alpha)`
   - `dataTextureB` ← mask/debug quad `vec4(strip, moire, viewAngle, semantic_alpha)`
     (write-only storage — fine for masks)
2. **Unused `input` sample** now drives flash luminance weighting (luma).
3. **Unused `hash21` helper** now drives fine print grain (anti-banding dither).

## Slider mapping (saved-preset contract — ids/defaults/ranges UNCHANGED)
| index | zoom_params | id | name | default | min | max | drives |
|---|---|---|---|---|---|---|---|
| 0 | x | shift | View Shift | 0.8 | 0.0 | 1.6 | `shiftAmt` — strip + chromatic channel shift amount (bass-modulated) |
| 1 | y | frequency | Lenticular Frequency | 0.55 | 0.1 | 1.0 | `freq = y*22+6` — strip density (6–28 strips) |
| 2 | z | color | Holo Color Shift | 0.4 | 0.0 | 1.0 | `colorShift` — holographic hue offset |
| 3 | w | beat | Audio Beat Pulse | 0.65 | 0.0 | 1.0 | `beat` — beat-driven interference gain (treble-modulated), also weights click flash |

Mapping was already shader-specific (not generic boilerplate); kept identical.

## Techniques implemented
- **Critically-damped 1D view spring:** `extraBuffer[133]`=position,
  `extraBuffer[134]`=velocity (only [133..255] used; [0..4] reserved, [5..132] FFT).
  Raw `mouse.x` is the spring target; thread (0,0) integrates
  `accel = k²(target−pos) − 2k·vel` (k=10 rad/s, dt=1/60). Slow
  `sin(time * 0.3) * 0.1` drift stays additive AFTER the spring.
- **Click holo flashes:** ripple loop guarded by `min(u32(u.config.y), 50u)`;
  each live ripple (`rp.z > 0`, age in (0, 1.2s)) adds an expanding moiré ring
  (`exp(-|dist − age·0.45|·16)`) with quadratic ~1.2s fade. Flash rides strip
  bands (`flashMask = clickFlash·band·(0.5+beat·0.5)`), mixes toward `holo` and
  adds a luma-weighted flare; also lifts depth slightly.
- **Vertical view tilt:** previously-unused `mouse.y` wired as strip-phase tilt
  `tiltPhase = (mouse.y − 0.5) * 0.3`, added into the strip phase (both axes play).
- **Print grain:** `hash21` dither `±0.0075` scaled by `(0.5 + moireMask)` —
  kills banding on smooth foil gradients.

## VERBATIM-preserved structures
- `hash21` helper (unchanged, now also used)
- Lenticular strip/band construction — core `fract(uv.x * freq + viewAngle * shiftAmt * 1.8 …)`
  and `smoothstep(0.0,0.18)−smoothstep(0.82,1.0)` band kept; only additive `tiltPhase`
  (mandated by brief)
- Three-channel view-angle offsets `0.012 / 0.003 / -0.009` (exact)
- Moiré interference `sin(strip*38 + viewAngle*14 + time*beat*4)` + `pow(…, 1.6)` mask (exact)
- Holo sin palette (`6.28318 / +2.094 / +4.188`) (exact)
- Vignette `smoothstep(0.72, 0.38, length(uv − 0.5))` + `col *= 0.7 + vign*0.3` (exact)
- Semantic alpha `clamp(0.68 + moireMask*0.55, 0.55, 1.0)` (exact)
- Immutable 13-binding layout, `@workgroup_size(16, 16, 1)`, Uniforms struct,
  `textureSampleLevel(…, 0.0)` sampler reads, writes to writeTexture /
  writeDepthTexture / dataTextureA every frame

## JSON changes
`shader_definitions/image/lenticular-holographic-shift.json`: added ONLY
`"updatedParams"` (index 0–3, names/defaults/min/max/step exactly per brief) and
`"updated": true`. `params` array untouched. JSON validates.

## Deviations
- `viewAngle` now derives from spring position (`viewPos`) instead of raw
  `mouse.x` — mandated by the brief (raw mouse.x is the spring target; drift
  added after the spring).
- Cleared ripples are all-zeros; guarded with `rp.z > 0.0` so dead slots don't
  flash at the origin during the first 1.2s after load.
- Depth line extended with `+ clickFlash * 0.15` (still clamped to 0.94).

## Gate result
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/lenticular-holographic-shift.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/lenticular-holographic-shift.wgsl — naga OK, bindgroup compatible
```
