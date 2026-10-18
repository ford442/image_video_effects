# Cursor batch-05 — notes

2026-10-18. Cards in `BRIEFS.md` were written before the WGSL.

## fabric-of-reality

Kept: Verlet (position, previous), top-row pin, gravity curve, mouse push and rip, wind, four-neighbor Jacobi, tear threshold, self-heal in the constraint pass, B = (strain, tear, weave phase, debris age), SSS, spotlight, render commits positions.

Ideas in the diff:
- Shear springs in `fabric-constraint.wgsl`, and the same diagonals in the tear mask.
- Catenary tension in `fabric-verlet.wgsl` (`vel.x` toward the rest column, scaled by gravity).
- Open weave and frayed ends in `fabric-render.wgsl`.

`dataTextureB` is write-only, so the render cannot load the tear mask. It recomputes the same structural and bias strain from the position field. The tear pass still writes B. Display ACES is `writeTexture` only. A stays (position, previous).

Constraint, tear, and render were migrated to `#include "_prelude.wgsl"` before the ideas. Position reads are exact `textureLoad`s.

## digital-glitch-pass1

Kept: byte corruptors, block shift, spring, held intensify, capped ripples, A = (displacedUV, intensity, blockSeed).

Ideas: macroblock motion carry from C.rg (Error Propagation carries, Decay Rate releases); Schmitt-trigger scan tear. Audio is `plasmaBuffer[0]` only. The old `plasmaBuffer[band + 1]` read is gone. No ACES on A.

## digital-glitch-pass2

Kept: field from C, neighbor bleed, bit-depth decay, symmetric chroma split, invert blocks, scanlines, vignette, ACES. Does not write A.

Ideas: chroma delay line (Error Propagation); block residual quantization (Bit Manipulation). Corruption Intensity now scales the bit-flip probability on this pass.

## pyramid-downsample-pass1

Kept: 18×18 tile, binomial K0/K1, original image on `writeTexture`, blur in B.

Ideas: bilateral range weight (High Freq Amp tightens it); low-band settle against last frame's blur (Low Freq Amp). B.a is the range agreement.

## pyramid-bandprocess-pass2

Kept: high residual, neon edges, bass hue rotation, low LFO, reconstruction mix.

Ideas: anti-halo clamp on the residual boost; chroma fringe along the photo gradient.

This pass no longer writes A. A would win the feedback copy and replace the blur. C stays the blur from B.

## pyramid-composite-pass3

Kept: loud interior, quiet exterior, mouse centre, ROI radius, luminous ring.

Ideas: the interior samples a magnified UV; the ring splits red and blue along its radius. ACES on the display. Does not write A or B.

## gen-magnetic-dipole-field

Kept: dipole, gyro-helix, loss cone, oval, belts, bow shock, ghost dipole, motion-blur history, planet.

Ideas: iron-filing clumps along `stream_val`; magnetic null where this dipole and the ghost cancel, drawn after the history smear. A stays ACES display RGBA.

## gen-ethereal-chrono-fluid-symbiote

Kept: fluid and crystal SDFs, smooth-min, meniscus, veins, twinning, chrono smear.

Ideas: step-count occlusion from the march; chrono shells on the fluid, spaced by Chrono Warp. A stays ACES display RGBA.

## gen-stable-fluids-jos-stam

Kept: viscosity, curl, dye, color, semi-Lagrangian velocity, diffusion, one Jacobi pressure step, projection, confinement, buoyancy, baroclinic jets, enstrophy shimmer. A = (vel, pressure, dye).

Ideas: MacCormack correction on the dye, clamped to the neighborhood; no-slip fade at the frame, stronger with Viscosity. ACES on the display only.

## fire_smoke_volumetric

Kept: temperature gradient, Worley embers, exact-load advection, ignition rings, Beer slab, depth alpha, the existing spring. A = (smoke RGB, density).

Ideas: buoyancy lift in the hot core; soot cap from advected density above the flame; red fringe on the silhouette. Header migrated to the prelude before the ideas. ACES on `writeTexture` only.

## Formula names

| Shader | Formula |
|---|---|
| fabric-of-reality | shear springs; catenary; yarn gaps (no §12.2 row — cloth family) |
| digital-glitch-pass1 | macroblock motion carry (§12.2B); Schmitt-trigger lock (§12.2B) |
| digital-glitch-pass2 | chroma delay line (§12.2B); block residual quantization (§12.2B, DCT-style) |
| pyramid-downsample-pass1 | bilateral range weight (§12.2A) |
| pyramid-bandprocess-pass2 | anti-halo envelope (§12.2A) |
| pyramid-composite-pass3 | lens magnification; rim split (optical, not a shared row) |
| gen-magnetic-dipole-field | filing clumps; magnetic null |
| gen-ethereal-chrono-fluid-symbiote | step-count AO (§12.2E) |
| gen-stable-fluids-jos-stam | MacCormack advection (§12.2D) |
| fire_smoke_volumetric | Boussinesq buoyancy (§12.2D); soot cap; red fringe |

No §12.2 row is on more than two files. MacCormack is only Stam. Buoyancy on the fire is the hot-core lift; Stam's older buoyancy on dye was already there and was kept.
