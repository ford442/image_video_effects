# BRIEFS — fork D (written before WGSL edits)

SHADER: vortex-prism (2nd pass; Oct-5 ideas: 7-tap spectrum fan, Rankine core, shear caustics)
IDENTITY: pointer-centred twist of the image with per-wavelength twist angles (prismatic fan) and a Rankine eye.
KEEP VERBATIM: 7-tap fan + spectral response, Rankine profile, shear caustics, prismatic alpha, 4 param roles.
RESCUE: none at HEAD (renders fine, meanL 0.51).
ADD:
  1. Spiral-arm interference — the twist angle gains a log-spiral term sin(k·ln r − 2θ) inside the outer band, so the swirl breaks into two winding arms instead of a uniform smear.
  2. Precessing eye — the vortex centre orbits the pointer on a small circle (mids widen it), so the eye wanders like a real vortex core.
  3. Dispersion rim — at the effect radius boundary a thin spectral ring (red outside, blue inside) where the twisted light exits the vortex.
FORBID: springs, extraBuffer state, palettes.
A PACKING: ACES display RGBA (unchanged).

SHADER: quantum-fractal (2nd pass; Oct-16 ideas: phase fringes of psi1, photo pulled by psi2 phase)
IDENTITY: two entangled tunnelling Julia iterations, interference of their magnitudes coloured by a cosine palette over the photo.
KEEP VERBATIM: quantumFractal iteration, entanglement/probability chain, phase fringes, phase pull, 4 param roles.
RESCUE: Iterations slider dead — u32(max(10, slider 0..1)) is always 10. Map 0..1 → 10..90 (default 0.5 → 50).
ADD:
  1. Nodal lines — where the two wavefunction magnitudes cancel (|mag1−mag2|≈0) thin dark destructive-interference seams are cut through the colour.
  2. Tunnelling halo — iteration count at escape is returned; late-escaping orbits (near the set boundary) glow violet-white, scaled by Edge Glow (the slider's name finally does something visual).
  3. Measurement collapse — a disk around the pointer collapses the superposition to the plain photo with a bright fringed rim; bass widens the disk.
FORBID: springs, extraBuffer state.
A PACKING: ACES display RGBA (unchanged).
