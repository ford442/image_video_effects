SHADER: gen-photonic-crystal-brain
IDENTITY: Raymarched infinite cubic lattice of crystal "neurons" (smooth-unioned rods + nodes) flown through along z, cosine/OkLab volumetric synapse glow, blackbody + Fresnel rim shading, mouse pulls the lattice.
KEEP VERBATIM: map SDF (rods/sphere/disp), OkLab/blackbody/cosine palette functions, camera wobble, glow accumulation, lighting/fog, applyGenerativePrimaryControls post (default look).
ADD (2 native ideas):
  1. Bragg-reflection structural color: lambda = 2*n_eff*d*cos(theta) (n_eff 1.45, d from lattice spacing slider), 1st+2nd order mapped to spectral RGB; stop band drifts red->blue with viewing angle, vanishes outside visible. Treble scales strength.
  2. Line-defect waveguide spikes: sparse hashed cells (45%) carry a Gaussian photon packet travelling along one of their rods (random axis/direction), rate driven by mids — firing axons inside the crystal.
FLOOR FIXES: added dataTextureA write (same RGBA as writeTexture); ACES then controls, final clamp 0..1; semantic alpha = hit coverage (distance-fogged) + glow density (was luma+0.2); raymarched depth instead of passing readDepthTexture through; div-by-zero guard on spacing (4/max(x,0.05)); glow was plasma-bass-only (black at silence) -> 0.25 + bass*0.35; bands clamped; added click ripples (action-potential shells expanding through lattice in world XY, min(config.y,50)); added mouse-held (stronger lattice pull + stimulation glow); Mouse Influence slider now scales pull (0.4*w, default 0.5 == old 0.2). config.y had no prior reads (note matched zoom_config.y). No extraBuffer / C use.
FORBID: extraBuffer use, dataTextureB writes, replacing the lattice motif, ripple.w scaling.
A PACKING: ACES display RGBA in A (C unused)
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x (spacing + primary intensity), y (pulse speed), z (distortion + contrast), w (glow + mouse pull) live
