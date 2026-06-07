# Batch 4D — bass_env Migration (Claude) (2026-06-07)

## Scope
8 Batch-1 shaders that read `plasmaBuffer[0].x` raw and used it directly to drive
visuals, causing percussive-transient strobing:

1. `gen-celestial-weave`
2. `gen-magnetic-kelp`
3. `gen-vortex-cathedral`
4. `gen-luminous-cauldron`
5. `gen-neon-snowfall`
6. `gen-bioreactor-bloom`
7. `gen-opal-circuit`
8. `holographic-crystal`

## Mandate Note (deviation from board text)
The board mandate said "store previous envelope in `dataTextureA.r`". All 8 shaders
already pack meaningful per-pixel state into `dataTextureA`'s RGBA channels (e.g.
`gen-celestial-weave` stores `fiber/knot/stars/alpha`), so overwriting `.r` with a
scalar envelope would destroy that data and break temporal feedback for other passes
that read `dataTextureC`. Per the precedent set in the 3E `electric-eel-storm` polish
pass, the envelope is instead stored in a dedicated `extraBuffer[0]` slot — a
storage buffer scalar untouched by any of these 8 shaders (verified via grep before
picking the index). This preserves the `dataTextureA` contract while still giving
every pixel access to the same persistent, smoothed envelope.

## Pattern Applied (uniform across all 8)
1. Added the canonical helper (only where missing):
```wgsl
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}
```
2. Immediately after `let bass = plasmaBuffer[0].x;`, inserted:
```wgsl
// ═══ CHUNK: bass_env smoothing (replaces raw-bass strobing) ═══
let prevBass = extraBuffer[0];
let smoothBass = bass_env(prevBass, bass, 0.8, 0.15);
extraBuffer[0] = smoothBass;
```
   (attack 0.8 / release 0.15 per board mandate — fast rise, slow decay so kicks
   read as punches rather than flickers)
3. Replaced every subsequent raw `bass` reference (color modulation, time-warp
   speed, threshold shifts, hue shifts, temporal-blend factors) with `smoothBass`,
   leaving the original `let bass = plasmaBuffer[0].x;` declaration and the helper
   function itself untouched.

## Per-Shader Call-Site Counts (raw bass → smoothBass)
| Shader | Sites migrated |
|---|---|
| `gen-celestial-weave` | 2 (weft time-warp, knot color weight) |
| `gen-magnetic-kelp` | 3 (frond phase, strand color, temporal blend) |
| `gen-vortex-cathedral` | 3 (spin rate, chroma, center-light glow) |
| `gen-luminous-cauldron` | 3 (bubble density, bowl glow, temporal blend) |
| `gen-neon-snowfall` | 3 (flake falloff, hue shift, temporal blend) |
| `gen-bioreactor-bloom` | 3 (grid drift speed, colony glow, temporal blend) |
| `gen-opal-circuit` | 4 (signal rate, opal-G hue, opal-B hue, temporal blend) |
| `holographic-crystal` | 3 (holo phase, holo-B hue, temporal blend) |

## Validation
- All 8: `naga {file}.wgsl` → **Validation successful**
- `node scripts/generate_shader_lists.js` → 1130 definitions regenerated, only
  pre-existing unrelated warnings (workgroup_size on showcase shaders)
- `node scripts/check_duplicates.js` → 1130/1130 unique IDs, no duplicates

## Visual Notes
- The smoothed envelope is most noticeable on shaders that previously used `bass`
  to drive timing/speed (`gen-vortex-cathedral` spin rate, `gen-bioreactor-bloom`
  grid drift, `gen-opal-circuit` signal pulse rate) — these now ramp musically
  instead of jumping frame-to-frame with the raw analyzer value.
- Color/hue modulation sites (`gen-neon-snowfall`, `gen-opal-circuit`,
  `holographic-crystal`) read as smoother chromatic breathing rather than flicker
  on percussive passages.

## Remaining Risks
- `extraBuffer[0]` is now claimed by all 8 of these shaders for the bass envelope.
  Each shader's compute pass is independent (separate bind groups / dispatches), so
  there's no cross-shader collision risk — but any future edit to one of these 8
  that wants to repurpose `extraBuffer[0]` for something else must account for this.
