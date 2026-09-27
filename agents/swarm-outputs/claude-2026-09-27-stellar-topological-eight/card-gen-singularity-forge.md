SHADER: gen-singularity-forge
IDENTITY (one sentence): a raymarched black hole with a fbm-turbulent torus accretion disk, a thin knotted jet, mouse lens pull and swirl-advected HDR trails.
KEEP VERBATIM: single 100-step primary march (count unchanged), black-hole/torus(pDisk.y*=5)/jet SDFs, gravity displacement, fbm disk turbulence, jet knot cadence (`knotPhase`), swirl-advected history read with exact `textureLoad(dataTextureC)`, mouse lens pull, camera, 4 params and their roles (Disk Density = torus thickness/rotation, Jet Intensity = jet glow + history gain, Gravity Warp = ray bending, Time Dilation = time scale), ACES only on writeTexture, semantic alpha, depth.
ADD (3 native ideas):
  1. Relativistic beaming + gravitational redshift on the disk. Per-step orbital velocity (tangent, beta ~ r^-1/2, capped 0.55) dotted with the ray gives a Doppler factor D; brightness ~ D^3 (approaching side blazing, receding side dim), times sqrt(1 - rs/r) gravitational dimming near the horizon, with a blue/red tint driven by log2(D*g). Replaces the old 3%-tint `doppler` that was applied to the whole frame. Visible with audio = 0; treble only sharpens the exponent.
  2. Log-spiral density-wave arms: shear phase is `m*theta + a*ln r - w*t` (m=3 grand-design arms, sharpened crests) instead of 16 radial spokes, so the disk reads as a winding galaxy-like spiral rather than a spoked wheel.
  3. Precessing helical jet: jet axis is displaced by a point-symmetric corkscrew `0.09*y*dir(phi)` with phi driven by the SAME ballistic age `|y|*0.18 - time*(0.9+bass*1.8)` as the knots, so knots ride the helix; slow whole-jet precession added.
FORBID on this file: lensed sky / photon ring / KIFS (gen-quantum-singularity-forge), extra marches or step-count increase, springs/ripples, palettes, a second geometry layer.
A PACKING: raw HDR (rgb) + semantic alpha in dataTextureA (kept; C is fed back raw, no decode needed); ACES only on writeTexture.

Silent bugs checked: A/C packing consistent (raw both ways); `normalize(p)` guarded by distToOrigin>0.01; no pow of negatives; audio from plasmaBuffer[0]. New code guards r and tangent normalisation. None found that needed a fix.
