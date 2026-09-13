# Idea Cards — turtle + weaver (2026-09-13)

```
SHADER: gen-luminescent-cyber-chrono-void-turtle
IDENTITY: raymarched obsidian space-turtle whose ellipsoid shell is split into 3D-Voronoi plates with cyan/magenta plasma glowing in the plate gaps, over an fbm nebula starfield
KEEP VERBATIM: sdEllipsoid body + head + two fins smin'd; voronoi() plate extrude/gap hollow; volumetric glow accumulation 0.02/(|shell|+0.01); obsidian base + spec lighting; camera orbit; nebula fbm background; param roles x=Shell Complexity, y=Plasma Intensity, z=Chrono-Distortion (mouse gravity well), w=Swim Speed
ADD:
  1. Chronal plate drift — each Voronoi plate (cell id hash) rises/sinks on its own phase, bass-kicked; the shell literally "shifts plates" as the description says, instead of one global extrude
  2. Chrono-distortion time dilation — inside the mouse gravity well plate drift/plasma phase runs slower (well already warps space; now it warps time, matching the slider name)
  3. Scute growth rings — concentric annuli inside each plate (from voronoi F1) etched into the obsidian and lit faintly by gap plasma, like real turtle scutes
  4. Void wake — plasma glow leaves a persistent wake that streams outward from the turtle at Swim Speed via exact dataTextureC history
FORBID on this file: spring cursor, IQ cosine palette overlay, click shockwave overlay beyond repairing the existing (dead) ripple code, replacing Voronoi plates with hex tiling
A PACKING: raw linear wake emission RGB (pre-tonemap HDR) + a = wake energy; C read by exact textureLoad at outward-advected coord
```

```
SHADER: gen-luminescent-nebula-silk-weaver
IDENTITY: volumetric raymarch of periodic silk tubes bent by curl-noise flow, cosine-palette colored with fresnel iridescence and magenta audio flares on a dark violet void
KEEP VERBATIM: snoise/curlNoise + 2 fbm octaves; fract-grid tube SDF length(q.xz)-width; matID from snoise; volumetric density accumulation loop, fresnel iridescence, emission band sin(dO*5 - t*10); mouse-down vortex pull; camera pan; ACES; params x=Flow Complexity, y=Ribbon Width, z=Iridescence, w=Audio Pulse
ADD:
  1. Plucked-thread standing waves — each thread (grid cell id) vibrates as a string sin(k*y)*cos(wt+phase), amplitude driven by bass * Audio Pulse; mouse vortex adds tension (damps vibration near the pull)
  2. Dew beads along silk — periodic droplet swellings along each thread widen the tube; beads get a treble-lit glint in the volume shading
  3. Silk afterglow — persistence of the woven light via exact dataTextureC history so the textile "breathes" instead of flickering
FORBID on this file: spring cursor, ripple shockwaves, replacing curl tubes with a different web geometry (orb web / hex), new palette
A PACKING: linear HDR composite RGB (pre-ACES) + a = accumulated silk density; C read by exact textureLoad at same coord. (HEAD read C as "frequency data" via filtering sampler — that was a packing/audio lie; audio now from plasmaBuffer[0])
```

## NOTES — gen-luminescent-cyber-chrono-void-turtle

- Kept verbatim: body/head/fin ellipsoid smin, Voronoi plate extrude + gap hollow, glow accumulation, obsidian diffuse/spec, camera orbit, fbm nebula, raymarch loop, all 4 param roles; gamma after tonemap kept so obsidian stays lifted.
- A packing: raw linear wake emission RGB (pre-tonemap, capped 4.0) + a = wake energy. C read with exact `textureLoad` at radially advected coord (`srcCoord`). No dataTextureC write.
- Ideas in diff:
  1. Chronal plate drift — `voronoi()` now returns plate id (`.z`); `plateLift` in `map()` (IDEA 1 comment), bass-kicked, also widens plasma seams in `localGlow`.
  2. Time dilation — `dilation` / `localTime` in `map()` (IDEA 2), drives plate drift + ring creep via `gDilation`.
  3. Scute growth rings — `groove` / `ringPhase` in the hit branch of `main()` (IDEA 3), per-plate stone tint by `gPlateId`.
  4. Void wake — `prevWake` / `wakeRGB` in `main()` (IDEA 4), speed from Swim Speed.
- Floor fixes: audio was `u.config.y` (ripple count) -> `plasmaBuffer[0]` bass (plates/glow), mids (glow hue, ring light), treble (star twinkle). Mouse was divided by resolution (already UV) -> fixed + world Y flip. Dead ripple code (tested padding `.w`) repaired to age from `.z`, bounded by `min(config.y, 5)`. Reinhard -> ACES. Alpha = coverage+fresnel, glow, wake, cloud density. Depth = 1 - t/20 on hit (was constant 0). `sdEllipsoid` k1 and mouse normalize divisions guarded.
- Gates: naga OK; wgsl_precommit_gate PASS (naga + bindgroup, 0 extraBuffer violations); audit_dead_sliders scans 0 defs for this id (JSON has only `updatedParams`, no `params`) — manually verified all 4 zoom_params read and visible.
- JSON: `features` [] -> mouse-driven, audio-reactive, upgraded-rgba. Nothing else touched.

## NOTES — gen-luminescent-nebula-silk-weaver

- Kept verbatim: simplex/curl noise + fbm, fract-grid tube SDF, matID, volumetric loop with cosine palette, fresnel iridescence, emission band, mouse-down vortex, camera pan, ACES helper, all 4 param roles.
- A packing: linear HDR composite RGB (pre-ACES, capped 8.0) + a = silk density (live or decayed). C read with exact `textureLoad(dataTextureC, coords, 0)`. HEAD sampled C via sampler as "frequency data" — removed (audio lie).
- Ideas in diff:
  1. Plucked-thread standing waves — `cell`/`phase`/`pluckAmp`/`standing` in `map()` (IDEA 1); amplitude `gPluck` = (idle + bass) * Audio Pulse, damped by vortex `tension`.
  2. Dew beads — `bead` widens tube in `map()` (IDEA 2); glint term using `beadHere` in `raymarch()`, treble-driven.
  3. Silk afterglow — `prev`/`lingering`/`linearOut` trailing max in `main()` (IDEA 3).
- Floor fixes: audio now plasmaBuffer[0] bass/mids (pulse), treble (glint). Semantic alpha from density; depth from first density hit (`SilkResult.firstHit`), previously no depth write; dataTextureA written; vortex normalize guarded.
- Gates: naga OK; wgsl_precommit_gate PASS; audit_dead_sliders AUDIT PASS (0 new dead sliders).
- JSON: appended mouse-driven, upgraded-rgba to `features` (audio-reactive already present). `params` untouched.
