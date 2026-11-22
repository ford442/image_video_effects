# NOTES — fork C (multi-fractal-compositor, volumetric-rainbow-clouds)

Files touched (uncommitted): `public/shaders/multi-fractal-compositor.wgsl`, `public/shaders/volumetric-rainbow-clouds.wgsl`, `shader_definitions/advanced-hybrid/multi-fractal-compositor.json` (description only), `shader_definitions/interactive-mouse/volumetric-rainbow-clouds.json` (description + `audio-reactive` feature; `params` untouched). HEAD copies: `.../scratchpad/c2/*_head.wgsl`. Cards: `BRIEFS-forkC.md`.

Harness: `.../scratchpad/c2/mr2.mjs` = `agents/mr.mjs` + `FFT='{"10":0.8}'` env that writes `extraBuffer[0..132]` (stock harness leaves the FFT bins at 0, so `extraBuffer[10]` was never exercised). `sheet.py` makes raw|over-white contact sheets. Sheets: `s3/s4/s5/s6.png` (compositor), `s1/s7.png`, `vrc_flash_diff.png` (clouds).

## multi-fractal-compositor — 2nd+ pass (Upgraded 2026-11-01, 2026-11-22)

- **Checklist:** ACES present on clamped display RGB ✓; audio `plasmaBuffer[0].x` (chroma) ✓ + `extraBuffer[10]` (FFT bin 5, read-only, legal; misnamed `clickIntensity`, left); no A/C use (consistent); no extraBuffer writes; alpha is semantic (`calculateVolumetricAlpha`). **No HEAD defect found** beyond dead computes (`mousePos`, `baseColor`) which I left. Not a rescue file.
- **COMMON correction:** this file is *not* the clouds' pass-2 partner (`prismatic-3d-compositor` is). Stand-alone photo zoom tunnel.
- **KEPT VERBATIM:** five staggered exp2 layers, sin² windows, zoom-dispersion taps (×0.982/×1.018), flow-noise warp (Domain Warp), FFT vortex, bass chroma split, edge glow, fog (Fractal Blend), alpha, depth out, ACES, four slider roles (params byte-exact; JSON `params` untouched).
- **ADD:**
  - **Idea 3 Droste spiral twist** — `spinAngle += DROSTE_TWIST(0.30 rad) × 2.3219281 × layerPhase` (= 0.30 rad per octave of the layer's own zoom). Folded into the existing rotation: 0 extra trig/taps.
  - **Idea 4 expanding annulus windows** — `ringW = 0.05 + 0.95·exp(-((r − mix(0.06,0.9,phase))/0.14)²)` (r aspect-corrected, height units) weights each layer's colour in the composite (`ringAcc/ringWeight` replace `ghostAcc/ghostWeight`) and sets the composite's presence (`ringWeight/ghostDensity × 2.2`). `ghostAcc/ghostWeight` removed (now unused).
- **Verified:** ring-only (twist 0) vs HEAD at defaults: 30 % px >4/255, mean abs 3.6 (first attempt, floor 0.35/width 0.22, was only 9.8 %/1.3 → invisible, so I tightened it; presence-gating raised it to ~36 %/5.0 for the pre-×2.2 version). Twist-only vs HEAD: 84 % px, mean abs 19.3. Both: 84.5 % px, mean abs 20.0 (t=4); 82 % (t=20); 80 % (mouse (0.15,0.2), warp 0.5, fog 0.5). meanL 0.656 → 0.650 (t=4), 0.665 → 0.663 (t=20). Presence debug (mean clamp(presence·2), t=1..6): HEAD ~0.94 flat, NEW ~0.78 (0.63..0.92) with stdL 0.14..0.29, i.e. the rings visibly carve the frame. NaN 0 at defaults, sliders 1,1,1,1 + mouse (0,0)+down + FFT10=1 + audio 1,1,1, and sliders 0,0,0,0.
- **Default picture changes a lot** (rotated, ring-weighted ghost copies). Identity (photo zoom tunnel with lens fringe) still reads in the sheets; if the user finds 0.30 rad/octave too strong it is one constant (`DROSTE_TWIST`).
- **A packing:** none (writes no A, reads no C). **Timing:** unresolved (see below). **Gates:** precommit 1/1, naga-wasm 1/1, dead-sliders 0, extraBuffer audit pass.

## volumetric-rainbow-clouds — 2nd+ pass (Upgraded 2026-11-01, 2026-11-22)

- **Checklist:** ACES ✓ (clamped input); no audio at HEAD (none claimed); no A/C; no extraBuffer use; outputs RGBA + depth packing read by `prismatic-3d-compositor`, unchanged.
- **RESCUE R1 (verified):** `viewDir = normalize(-viewPos)` with `viewPos.z = 0` → the view vector had no z → `specular` was **exactly 0 everywhere** (HEAD with `specular := 0` is bit-identical, 0.0 % px, at Light Intensity 4, mouse (0.2,0.3)). Fixed: `normalize(vec3(-viewPos.xy, 1.0))` (the camera is in front of the slab; HG's `cosT = lightDir.z` already assumed +z). 11.4 % px change (mean abs 0.75/255) at Light Intensity 4; **9.7 % px / mean abs 1.09 at defaults, t≈0, audio 0** (rescue alone). Also removes the undefined `normalize(vec3(0))` at the exact centre pixel of even-sized frames. Default picture changes only by that glint.
- **KEPT VERBATIM:** trilinear value noise + 6-octave fbm with `abs()` density, three layers, Beer-Lambert opacity/alpha, rainbow-by-normal hue, light-march self-shadow, HG silver lining, scattering-angle corona, fog+ACES, depth packing, params (Scale, Flow Speed, Density, Light Intensity), the mouse-down perspective pull.
- **ADD:**
  - **Idea 5 wind shear** — per-slab drift `windVec = (1, 0.4·layer) × (0.06 + 0.06·layer + 0.02·layer²) × flowSpeed × time` subtracted from the noise xy (speeds 0.06/0.14/0.26 noise-units/s, headings sheared). Zero extra taps; shadow march and normal taps share `noisePos`. At t=0 identical to HEAD (+R1 glint); the clouds now slide past each other as time advances.
  - **Idea 6 in-cloud lightning** — `flash = smoothstep(0.25,0.6, plasmaBuffer[0].x) × exp(−7·fract(2.5t)) × exp(−10·|uv−strikePos|²)`, `strikePos = hash3d(floor(2.5t))`; adds `transmittance·(1−layerTransmittance)·mix(cold white, layer hue, 0.4)·flash·6.0` per slab (pre-ACES). Bass 0 → no change. Measured at t=4.04, bass 1 vs 0: max +78/255, 50 % px >8, lit region in the strike cell's neighbourhood (`vrc_flash_diff.png`). First gain (×2.5, falloff 14) was only +42/255 on this pale cloud, raised to ×6/10.
- **JSON:** `audio-reactive` added (now true: plasmaBuffer.x drives the flash); description appended. `params` unchanged.
- **NaN 0** at defaults, 512², Scale 5/Flow 2/Density 2/Light 4 + audio 1,1,1 + mouse (1,0)+down, Scale 0.1 with everything 0 (blank by Density 0, expected).
- **A packing:** none. **Gates:** precommit 1/1, naga-wasm 1/1, dead-sliders 0, extraBuffer pass.

## Timing — NOT resolved (box load 26–36 from other forks)

`mr_ab.mjs` 256², 6–8 cycles, interleaved, repeated: compositor ratio (min / paired-median) 2.15/1.94, 0.99/1.18, 1.35/1.45; clouds 1.43/0.88, 0.85/0.92, 1.31/1.20; single-idea variants of the compositor (notwist 1.04/0.77, noring 0.88/0.89) — i.e. noise ±50 %. Analytic estimate: compositor adds ~15 flops/layer (one `exp`, one `length`) against 4 taps + 2 noise per layer; clouds adds 2 hashes + 1 `exp` per pixel and one `mix` + `hsv2rgb` per layer against ~12 six-octave fbm calls. Expected ≤ 1.1× each. **Coordinator: re-time on a quiet box.**

## Open calls for the user (clouds, left unchanged)

1. `cameraZ = zoom_config.w` is the mouse-down flag: a click instantly doubles the perspective divisor (a pop; easing would need state).
2. Density is `abs(fbm)` (ridged), which is the source of the black marble veins; a billow/coverage re-map would change the whole picture, so not done.
3. Compositor: `DROSTE_TWIST` strength (0.30 rad/octave) and the ring floor/width are by eye on a synthetic image, not on real photos.
