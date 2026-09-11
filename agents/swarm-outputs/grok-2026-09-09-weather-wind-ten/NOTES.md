# Weather / wind / condensation ten — NOTES

Per shader: kept verbatim, packing, which ideas are in the diff.

## snow
- Kept: speed/density/wind/accumulation; hex SDF; 3 layers; up-facing accumulation; melt.
- Ideas in diff: `tumble` arg to `snowflake` (rotates hex arms); `snow_acc *= 1.0 - prev_snow * 0.85` land fade.
- A packing: A.r accumulation (raw). Display ACES.

## raindrop-ripples
- Kept: intensity/decay/speed/shield; height+prev; mouse shield + rim wake.
- Ideas in diff: Verlet `lap * waveC` (speed was unused); `caustic` from `-lap`.
- A packing: A.rg height/prev (raw). Exact C.

## bubble-wrap
- Kept: scale/popStrength/refraction/highlight (JSON still “Unused”); pop timestamp; elastic collapse; wrinkle; burst ring.
- Ideas in diff: hex row offset; 6-neighbor `neighborPops` chain pop + weaken.
- A packing: A.rg popped/time (raw). Exact C. Display ACES.

## pixel-wind-chimes
- Kept: strip_count/sway/wind_speed/gap; top pivot; mouse Gaussian push.
- Ideas in diff: `hinge_amt` at local_pos.y≈0; `best_z` from `sin(angle)`.
- A packing: ACES display RGBA (HEAD never wrote A).

## sim-smoke-trails
- Kept: density/turbulence/rise/dissipation; A = density,temp,vel; bottom+mouse+ripple seeds.
- Ideas in diff: vorticity confinement from neighbor vel; `smokeTemp *= mix(1.0, 0.90, uv.y)`.
- A packing: raw fields. Exact C. ACES display only.

## radiating-haze
- Kept: speed/intensity/satThresh/radius JSON roles; HSV neutrals; persist A.r.
- Ideas in diff: 4-neighbor sat bleed; waves from `mouse` origin.
- Floor: Uniforms canonicalized (JSON sliders were landing on swapped zoom_config). ColourMode extras derived from audio, not stolen sliders.
- A packing: persist A.r. Exact C. Display ACES.

## radiating-displacement
- Kept: speed/strength/satThresh/radius; HSV lock; click ripples.
- Ideas in diff: `waveDisplacement(uv, mouse, …)` (HEAD used centre=uv so dist=0); RGB phase-split of the same wave.
- Floor: Uniforms canonicalized so sliders actually drive the wave.
- A packing: ACES display RGBA (HEAD never wrote A).

## interactive-pixel-wind
- Kept: strength/turbulence/trails/shift; mouse windDir; fbm curls; existing CA from shift.
- Ideas in diff: `lumaW` on offset; upwind luma `shadow`. Exact C history.
- A packing: ACES display RGBA.

## lidar
- Kept: speed/width/contours/edges; scan_pattern 3 modes; point cloud; height colour.
- Ideas in diff: echo in A (was B); `tick` along beam. Held=radial, held+rim=spiral, else linear. Persistence from treble, not mouse.x.
- A packing: echo A.r. Exact C. Display ACES.

## rain-lens-wipe
- Kept: strength/decay/radius/density; rainDistortion; streakPacket; wipe A.r; click fronts.
- Ideas in diff: `meniscus` from wipe gradient; `bead` hang below wiped C.
- A packing: wipe A.r (raw). Display ACES.

No new extraBuffer owners. Saved params byte-exact.
