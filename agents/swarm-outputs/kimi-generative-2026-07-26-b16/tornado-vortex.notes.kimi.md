# tornado-vortex — Interactivist upgrade notes (Batch 16)

## Line delta
- Before: 200 lines → After: 256 lines (**+56**, within the +50–90 expansion window; target band 250–290 ✅)

## Key changes per technique

### 1. Dead physics activated (priority 1)
`vRadial` and `vVertical` were computed but never consumed. Now they drive the debris loop:
- **Radial inflow:** `dRadius` gains `vRadial * dh * 9.0` (clamped ≥ 0.004), and `dAngle` gains `vRadial * dh * 20.0` — particles visibly spiral inward over their lifecycle.
- **Vertical updraft:** `dPos.y` gains `dLift = vVertical * dh * 3.0`, and a `liftGlow = 1.0 + vVertical * 6.0 * dh` term brightens debris as it climbs the funnel.
The advertised "radial inflow / vertical updraft" behavior in the JSON description is now real.

### 2. Click-spawned satellite vortices
- Loop over `u.ripples[]` guarded by `min(u32(u.config.y), 50u)`.
- Each click spawns a mini Rankine satellite (`select()` core/outer branch of its own) at the click point, with circulation `0.12 * decay²`, core radius growing with age, and a hard ~2s lifetime (`alive` mask via `step`, no `continue`/branch divergence tricks).
- Satellites dent the main funnel wall (`+ satellite * 0.018` in `funnelDist`), tug debris positions (`satellitePull`), render an OkLab-mixed mini-condensation body (`satBase` mix at `satBody * 0.45`), and contribute to depth + bloom alpha.

### 3. Per-bin treble lightning
- New `plasmaBin(idx)` helper reads engine FFT bins 1–8 from `plasmaBuffer[1].xyzw` / `plasmaBuffer[2].xyzw` (`plasmaBuffer[0]` stays the bass/mids/treble bands).
- `hiSum` (bins 5–7) drives **branch count** (`branchCount = 5 + floor(hiSum * 7)`, replacing the fixed `angle * 9.0`), strike probability threshold, and blackbody temperature shift (+4000K).
- `binSum` (bins 0–7) modulates flash clock rate and bolt energy. Strikes now follow hi-hats, not just the global treble band.

### 4. Slider wiring (existing ids/defaults preserved — saved-preset contract intact)
| index | id | mapping | shader-specific constant driven |
|---|---|---|---|
| 0 | intensity (0.5) | zoom_params.x | Rankine circulation, inflow/updraft strength, fog density, condensation width |
| 1 | spin (0.5) | zoom_params.y | `spinSpeed = y * 5.0` → funnel spiral phase rate + debris swirl rate |
| 2 | debris (0.4) | zoom_params.z | debris **count** (`8 + i32(z*24)`), particle size, brightness |
| 3 | lightning (0.3) | zoom_params.w | flash probability threshold + bolt energy scale `(0.5 + w*0.5)` |

## Binding contract compliance
- Canonical 13-binding layout unchanged; no bindings added/renumbered; no binding 13.
- `@workgroup_size(16, 16, 1)` kept.
- Writes `writeTexture`, `dataTextureA` (display color), and `writeDepthTexture` every frame.
- `textureSampleLevel(..., 0.0)` for depth read; `textureLoad` n/a (no storage texture reads needed).
- `extraBuffer` untouched (no persistent state used).
- No WGSL reserved keywords used as identifiers.

## Caution items — preserved verbatim
- Rankine vortex `select()` core/outer branch: byte-identical.
- `blackbodyRGB` coefficients, OkLab matrices: byte-identical.
- Tonemap stack `hue_preserve_clamp(color, 8.0)` → `aces(color * 1.5)` → IGN dither: byte-identical.
- `dataTextureA` still stores display color, not sim state.

## QA flags
- Gate: **GREEN, 0 warnings, 0 errors** (`Passed: 1 | Failed: 0 | Workgroup errors: 0 | Warnings: 0`).
- ⚠️ naga binary not installed in this environment — gate ran bindgroup + workgroup checks; naga step auto-skipped (environment limitation, not a shader issue). No tint/wgsl_reflect available either. WGSL written conservatively (no `continue`, no dynamic vector-component pitfalls beyond `v[idx % 4u]` which is valid WGSL).
- JSON extracted verbatim from the brief's fenced block (validated parseable; `updated: true`, 4 params + 4 updatedParams).
- Visual check not possible here (headless VM, no WebGPU adapter) — recommend a quick visual pass on a GPU machine, especially satellite-vortex scale (0.16 radius mask) and debris lift factor.
