# Notes — flow-lattice ten (2026-11-15)

Per shader: what stayed, the packing, and where each idea sits in the diff. Cloud VM has no GPU. These notes are structural. They are not visual QA.

Prelude migration on `pixel-wind-chimes`, `hypnotic-spiral`, `cellular-automata-3d`, `ion-stream`, `sphere-projection`, and `psychedelic-noise-flow` is infrastructure. It is not an idea.

## quantum-field-visualizer

- Kept: slits at x = ±0.12, barrier gaps at y = ±0.12, real/imag pair, phase hue, held-only collapse, photo mix. Params unchanged.
- Idea 1 after `|ψ|²`: `sinc²(k0 · y · 0.52)` into `enveloped`, then the collapse mixes from that. Energy still sets `k0`.
- Idea 2 before the photo sample: exact C at `uv.x − 0.012`, mixed by `smoothstep` of `enveloped`.
- A packing: ACES display RGBA. C is that display.
- Formula: neither idea is a §12.2 row.

## pixel-wind-chimes

- Kept: strip count, sway, wind, gap, five-neighbor search, rigid rotation, closest-Z, hinge specular. Params unchanged.
- The mouse push used `pow(dist_x * 5, 2)` with a signed `dist_x`. That is now `abs(dist_x)` so the push is finite on both sides of the pointer. Guard, not an idea.
- Idea 1 after the loop: `hanger` and `cord` in the gap, multiplied by `1 - found_hit`.
- Idea 2 inside the hit: exact C shifted by `win_y * win_ang_vel * 48` pixels. `win_ang_vel` is the derivative of the existing wind term.
- A packing: ACES display RGBA, unchanged.
- Formula: neither idea is a §12.2 row.

## interactive-pcb-traces

- Kept: cell hash, horizontal-first elbow, branch direction, via ring, drill, packet phase formula, hover / held / click, copper and solder, history glow. Params unchanged.
- Idea 1: `fillet` from distance to the pad along the pad leg, `traceWidth = baseWidth * (1 + fillet * 2.1)`.
- Idea 2: `n1`/`n2` inset from the elbow; primary distance is pad→n1→n2→edge. The branch meets `chamferMid`. `routeLength` follows that path so the packet stays on the copper.
- A packing: ACES display RGBA, unchanged. `upgraded-rgba` added to features; ACES was already in the file.
- Formula: neither idea is a §12.2 row.

## hypnotic-spiral

- Kept: log/Archimedean radius, arms, rotation, color cycle, warp, secondary arm, click twist, tangent photo ride. Params unchanged.
- Idea 1: `lead = cos(armPhase)` scales `rgb` by `1 + lead * spiralMask * 0.45`. `armPhase` is the argument the sine already used.
- Idea 2 after the tangent ride: exact C stepped against `tangent * sign(rotSpeed)`, mix `abs(rotSpeed) * 0.28` on the arm.
- A packing: ACES display RGBA, unchanged.
- Formula: neither idea is a §12.2 row.

## cellular-automata-3d

- Kept: born 4–6 / survive 5–7, 26-neighbor sum, 72-step march, spring in `extraBuffer[133..138]` at `(0,0)`, click shock, hash hue, C persistence. Params unchanged. The spring was already the camera; it is not a new idea.
- The shock front squared the radius instead of `pow` on a signed base, so a click cannot NaN. Guard, not an idea.
- Idea 1: `cellDensity` returns `shell = 1 - neighbors/16`. Emission is `*= 0.42 + 0.95 * state.y`.
- Idea 2: `newborn = born * (1 - current)`, added as a white spike `state.z * 0.7`.
- Idea 3: `fract((pos+1)*14)` darkens the cube face with `smoothstep(0.16, 0.0, edge)`.
- A packing: ACES display RGBA, unchanged. `upgraded-rgba` added. ACES was already on the display.
- Formula: neither idea is a §12.2 row. No step-count AO.

## gen-aetheric-tachyon-lattice

- Kept: six abs-and-rotate folds (0.5 then 0.3), three tube distances, tachyon product of sines, cyan/magenta/blue bands, held ray warp, bass on emission. Params unchanged. No fourth slider.
- The normal is divided by `max(length, 0.0001)`. Guard, not an idea. Gamma `pow` replaced by ACES (floor).
- Idea 1: `folds` counts `step(p, 0)` before each `abs`. `foldAmt = folds/12` heats emission toward amber and dulls diffuse (§12.2E).
- Idea 2: `dmid` is the middle tube distance. `junction = exp(-dmid * 14) * exp(-dmin * 6)` adds a white vertex.
- A packing: ACES display RGBA. C is not read. The previous A store was zeros. B is still the zero clear this file already wrote. Depth is `t/20` on a hit and `1` on a miss.
- Formula: fold-count material (§12.2E). Only file in the batch.

## ion-stream

- Kept: value-noise curl, magnetic bend, lanes, charge split, cyclotron `fieldB`, packets, click fronts, exact-C wake. Params unchanged.
- Idea 1: `pinch = 1 + sin(y · … - time · speed) * 0.42 * density` multiplies the helix amplitude and divides the core exponent.
- Idea 2: `packetWidth = 0.10 / (1 + fieldB * 2)` and `ionGlow *= (1 + fieldB * 1.35)`. The packet is `exp(-q²)` so a negative base cannot NaN.
- A packing: ACES display RGBA. C is that display. Floor adds ACES; the September tag claimed it and the shader clamped to 1.
- Formula: neither idea is a §12.2 row.

## sphere-projection

- Kept: sphere quadratic, yaw/pitch, held zoom, Lambert, meridians, parallels, click shells, rainbow slick, 0.2 history mix. Params unchanged.
- Idea 1 after the slick: `pow(1 - ndotv, 5) * hit` adds a cool rim (§12.2F). Lighting's Lambert term is untouched.
- Idea 2: Blinn `pow(max(dot(n, halfV), 0), 40) * light_param`. Lighting still means the key.
- A packing: ACES display RGBA. C is that display. Floor adds ACES; the August tag claimed it and the shader stored linear colour.
- Formula: Fresnel–Schlick (§12.2F). Only file in the batch.

## gen-hypnotic-vortex-tunnel

- Kept: layer count, contra-spin, log z, seam walls, horizon shear, accretion disk, iris, outer fade. The definition has no top-level `params` array; none was added. All four `x-meta.upgrade.params` fields are read (`Rings` / `Rotation Speed` / `Zoom` / `Distortion`).
- Idea 1 in `tunnelLayer`: `hoop = mix(ringMask, smoothstep(0.58, 0.9, ringMask), 0.7)`, then `combined = hoop * spokeMask`.
- Idea 2 after ACES: exact C stepped inward by `flight * 0.014`, `flight = 0.5 * (1 + bass * 0.2)` (the coefficient already in `zBase`). Mix is off inside the iris.
- A packing: ACES display RGBA, unchanged.
- Formula: neither idea is a §12.2 row. No cos⁴.

## psychedelic-noise-flow

- Kept: gradient noise, per-channel domain warp, Color Shift mix, filament sine, spectral add, held vortex, click fronts. Params unchanged. `n_r` is the same sample; it is now `noise(nArg)` so the finite difference shares it.
- Idea 1: `grad` from `nArg ± (0.55, 0)`, tangent perpendicular, added to the three offsets as `along`, `along * 0.85`, `along * 0.7`, scaled by the existing `strength` and the filament.
- Idea 2: exact C at `uv - smearR * (0.65 + speed_param * 0.5)`, mix `0.16 + distort_param * 0.14`, then ACES.
- A packing: ACES display RGBA. C is that display. Floor adds ACES; the May tag claimed it and the shader stored the raw sum.
- Formula: neither idea is a §12.2 row.
