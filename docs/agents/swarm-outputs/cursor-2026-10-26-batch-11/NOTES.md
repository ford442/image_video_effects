# Cursor batch-11 — notes

2026-10-26. Cards in `BRIEFS.md` were written before the WGSL edits.

Saved `params` were not renamed or re-defaulted. Seven pasted headers were migrated to `#include "_prelude.wgsl"` (`viscous-drag-bilateral`, `interactive-ripple`, `rgb-ripple-waves`, `velvet-vortex`, `vortex-drag`, `sim-volumetric-fake`, `raindrop-ripples`). That swap is not the upgrade.

## viscous-drag-bilateral

Kept the 5×5 bilateral, the pointer drag, the click fronts, and the raw packing (displacement, edge confidence, coating).

The displacement mix now uses an isotropic 9-point neighbor mean (§12.2D). Last frame's edge confidence reduces that mix. Viscosity still sets the blend. No spring.

## liquid-viscous-grokcf1

Kept the FBM warp, the helical flow, the spring, the ripple shear, and the vein.

The trail is a MacCormack step on the existing forward/back history samples (§12.2D), then the same trail mix. A rim lights where the pre-smoothstep density crosses 0.55, in the existing nebula hue.

## liquid-perspective

Kept the three Gerstner waves, the Jacobian parallax, Snell/Fresnel, and the chromatic split.

Phase speed scales as sqrt(kMid / k), mixed at 0.7 so the middle wave keeps its clock (§12.2D). Steep Jacobian slopes go pale. Speed and intensity keep their roles.

## interactive-ripple

Kept the pointer packet, the depth-scaled speed, the crest chroma, and the caustic/bloom/film chain. A stays offset, height, alpha.

Click envelopes keep a disc and gain a ring at age × wave speed. The existing caustic brightens in signed troughs. No new solver.

## rgb-ripple-waves

Kept the radial RGB sines, Beer–Lambert at 650/550/450 nm, and the green crest. No click system was added.

Each channel's clock scales by sqrt(λ / 550) (§12.2D). The channel-phase slider is B in a Cauchy curve (§12.2F), red anchored. Sample UVs are clamped. ACES is on the display.

## velvet-vortex

Kept the spring, the arm count, the per-arm bin, and the click twist. The spring write is a single thread at (0,0).

Nap sheen follows the swirl tangent. Spring speed narrows the radius (§12.2C). Pulse still multiplies it. ACES is on the display.

## vortex-drag

Kept the spring, the helix, the ribbon palette, and the pinch scaling of the rotated vector.

Positive pinch multiplies the twist; a bulge reduces it. The photo under the ribbon darkens before the palette thread is added.

## liquid-glitch

Kept the block quantize, the pointer wake, the shard bursts, and the spring.

The bad-row offset fades along x, with a light streak in the tail (§12.2B). Green stays on the smear; red and blue lag by the chromatic-shift distance (§12.2B).

## sim-volumetric-fake

Kept the radial march, the depth occlusion, the motes, and the moving light. No pointer was added.

Extinction from scattering and dust multiplies the existing attenuation (§12.2F). The alignment glow is a Henyey–Greenstein lobe on the same angle (§12.2F), with the peak matched to the old term.

## liquid-viscous-simple

Kept `flowField`, the pointer vortex, shear-thinning, and the fresnel. No spring.

Analytic curl of `flowField` adds a small confinement swirl (§12.2D). High shear mixes in a sample taken along that flow.

## liquid-mirror

Kept the height/velocity step, the glitter, the energy blur, and the raw packing.

Velocity loses a curvature term (§12.2D). The lip of the push mask adds a ring of impulse. Smoothness still damps.

## raindrop-ripples

Kept the rain hash, the shield, the slope refraction, and the caustic from a negative Laplacian. A.rg stays height and previous height. waveC is still the speed slider.

The Laplacian is 9-point and scaled to the old 5-point magnitude (§12.2D). Steep `|lap|` spends extra decay. The decay slider remains the base.

## Floor

Bindings via prelude. 16×16. Exact `textureLoad` of C where C is read. A packing as in each card. ACES on display RGB only; raw fields are not tone-mapped. Saved params byte-exact. `viscous-drag-bilateral` features gained `audio-reactive` and `upgraded-rgba`. `velvet-vortex` features gained `upgraded-rgba`.

## Gates

Naga 12/12. Precommit 12/12 (extraBuffer, bind group, no pasted headers). Dead sliders 0 new. Vitest 1435 passed. `SKIP_WASM_BUILD=1` build passed. Real-GPU visual QA: external.
