# NOTES — fork C (mycelium-network, phase-memory-weave), both first pass

## mycelium-network
SHADER: mycelium-network
IDENTITY: per-cell hyphal trees (trunk + ≤5 branches) with travelling nutrient pulses, worley thickness, cursor tropism, bass heartbeat.
KEEP VERBATIM: cell seeding, branch kernel, pulses, params (density/angle/pulse/glow).
ADD: 1. anastomosis bridges — tips fuse to 4-neighbour tips (pair-keyed hash, continuous across cells) with a back-and-forth nutrient shuttle; 2. fruiting primordia — ~30% of trunk tips carry a cream knot with dark rim that swells on bass.
FORBID: spring cursor, ripple rings, IQ palette. A PACKING: display RGB (pre-ACES color) + alpha (unchanged).
Rescues (HEAD): click packet stored in extraBuffer[133..136] (re-uploaded every frame → never fired) → newest u.ripples entry; strands sub-pixel at ≤384 px (meanL 0.009) → 1.1 px floor on trunk width; writeTexture was color*alpha (double-darkened) → straight RGB; `pulse` / `tipGlow` added to glow unmasked → rectangular alpha/depth slabs per cell → masked by strand.
Left: branches start from each pixel's own closest trunk point, so near-parallel branches render as striped bars (HEAD geometry, identity; not touched).
meanL 384: HEAD 0.009 → 0.038 (click 0.041). nan 0.

## phase-memory-weave
SHADER: phase-memory-weave
IDENTITY: complex Ginzburg-Landau / Allen-Cahn field with slow memory, fluid↔crystal palette, opalescent interfaces.
KEEP: state packing (psiR, psiI, slowMem, activity), params, palette, ring forcing.
ADD: 1. phase-vortex cores — winding number around the 4-neighbour loop; |w|≈1 cores glow warm (+1) / cool (−1); 2. memory ghost contours — iso-lines of slowMem drawn where memory disagrees with the present field.
A PACKING: raw sim state (unchanged).
Rescues (HEAD): picture was per-pixel white noise on diagonal stripes — laplacian scaled by eps*mobility (~0.005/frame, never coarsened) → diffusion 3*eps (≤0.225, stable); per-pixel turbulence hash → bilinear value noise; seed was a linear fract ramp (stripes) → hash. Click rings compared ripple.z (raw s) with time*0.5 → never fired → u.config.x; once live they flooded the frame to crystal → ×0.12 per-frame. Dead extraBuffer spring removed (never persisted); 'spring-interaction' feature dropped.
meanL 256: HEAD 0.354 (noise) → 0.33 (domains + cores). Slider extremes 0/1 at audio 0.8: 0.30/0.34, nan 0.

## Gates
naga-wasm 2/2, precommit 2/2 (0 extraBuffer violations), dead-sliders 0 new.
## Perf (192 px, 12 frames, load ~34 — noisy)
mycelium after trim (bridges 4 tip evals, was 8): 0.89/1.12/0.93 → ≈1.0 (pre-trim 1.8×). phase-memory: 1.11/1.70/1.01 → ≈1.1.
