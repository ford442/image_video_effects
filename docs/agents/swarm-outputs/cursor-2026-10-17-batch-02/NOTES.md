# Cursor batch-02 — notes

2026-10-17. Idea cards were written in `BRIEFS.md` before the WGSL edits.

## quantum-foam-pass2

- Kept: curl advection, quaternion rotate, RGB dispersion, anisotropic mix, spectralPower, emission threshold.
- Ideas in the diff: curl comet (`flowDir`, `tailCol`, `comet`); film scintillation (`spark` on `emission`, bass on the twinkle rate).
- Packing: `dataB` and `dataA` are `(finalColor.rgb, emission)`. The graph copies B into C before pass 3. Exact `textureLoad` on C.
- Pass 2 does not ACES. Audio is `plasmaBuffer[0].x`.

## quantum-foam-pass3

- Kept: 3×3 glow, purple depth haze, vignette, saturation/contrast grade, ACES, gamma, intensity early-out.
- Ideas in the diff: `sampleGlow` smears along the emission gradient (`flowDir`, Flow Speed); Beer veil `transmitted = particleColor * exp(-thick * …)` (Diffusion Rate).
- Does not write A. Pass 2 owns the particle pack.

## liquid-pass1

- Kept: laplacian / biharmonic split, click packets, ambient waves, meniscus, A = `(h_prev, h_curr, velocity, age)`.
- Ideas in the diff: crest lean `newHeight - (slopeX + slopeY) * newVelocity`; capillary fringe from `zoom_params.w` (Color Shift), previously unread on this pass.
- No ACES on the stored heights. Pass 2 reads `C.g`.

## liquid-pass2

- Kept: height normal, Schlick Fresnel, per-channel Beer absorption, turbidity = Color Shift. Does not write A.
- Ideas in the diff: fold caustic `pow(saturate(-curvature * 6.0), 2.0)`; wetting rim `wetRim` on the depth edge.
- Turbulence and Ripple Strength are read here (they were dead on this file). Display is ACES.

## vortex-pass1

- Kept: four cores, Biot-Savart tangent + inflow, confinement, fbm turbulence.
- Ideas in the diff: pairing jet `pairN` between cores 0 and 1; viscous memory blend when `C.a > 1.5`.
- Audio is `plasmaBuffer[0].x`. The old `zoom_config.x` factor was time, so the spin grew without bound.
- Packing: `(vx, vy, vorticity, velMag + 2)`. The +2 sits above any display alpha so pass 2 can tell the field from a color buffer.

## vortex-pass2

- Kept: per-channel trail blur, hsv curl tint, palette grading, the four slider roles.
- Ideas in the diff: when `C.a > 1.5`, the trail is centered on `uv - velocity` and a Rankine eye darkens the core; eyewall braids are `sin(dot(uv, tangent) * 48)`.
- Does not write A, so pass 1's field survives the chain. Photo-as-flow remains when C is not that field. Display is ACES.

## chromatographic-fluid

- Kept: seven-node graph, dye.rgb + temperature, Jacobi viscosity split, shared wind, phase change, hold paint, click splash.
- Ideas in the diff: `chromatographic-advect.wgsl` steps R/G/B by `lag` from Viscosity Split (red shorter, blue longer); `chromatographic-render.wgsl` adds a pale front where dye is present and the downwind neighbor is empty.
- A stays raw dye + temperature. ACES only on the render color.

## sim-fluid-feedback-field

- The catalog id dispatches pass 1 only (`nextShader` is null). Pass 2 and pass 3 files are not in the chain and were left alone.
- Kept: curl seed, viscosity damping, radial mouse push. Slider roles stay x viscosity, y turbulence, z mouse force.
- Ideas in the diff: semi-Lagrangian mix of `adv.xy` with the curl seed; dye in `A.z` that warps the photo and scales with Glow (`zoom_params.w`, previously unread).
- Packing: raw `(velX, velY, dye, 1)`. ACES is on `writeTexture` only.

## gen-spectral-ferrofluid

- Kept: four dipoles, flux spirals, Cotton-Mouton tint, meniscus mounds, Rosensweig crowns, Barkhausen flicker, A = `(fMag*0.25, fieldDir.x, fieldDir.y, alpha)`.
- Ideas in the diff: mirror beads at radius 0.11 (inside the 0.23 crown); Bloch wall `smoothstep` on `dot(fieldDir, prevFieldDir)`.

## gen-aethereal-ferrofluid-chrono-core

- Kept: sphere, Rosensweig needles, 12-tick clock ring, seam bioluminescence, held-pointer dipole, display A packing.
- Ideas in the diff: `bulb` subtracted from the needle distance; equatorial `exp(-p.y * p.y * 90)` sheet multiplied by `(1 - tick)`.

## Floor and gates

- Prelude include. Seven pasted headers migrated (`quantum-foam-pass2/3`, `vortex-pass1/2`, `chromatographic-advect/render`, `sim-fluid-feedback-field-pass1`). Saved `params` values unchanged.
- Naga 12/12 on the touched WGSL. extraBuffer clean. Dead sliders clean (pass 3 and spectral have no top-level `params`).
- Jest: 158 passed, `ShaderValidator.naga.test.tsx` failed once under the full run (duplicate "Broken Shader" text) and passed alone. `SKIP_WASM_BUILD=1` build succeeded.
- Real-GPU visual QA: external.
