SHADER: gen-prismatic-bismuth-lattice
IDENTITY: Orbiting camera around a folding bismuth hopper-crystal fractal with thin-film iridescence and temporal trails.
KEEP VERBATIM: bismuthDE fold/rotate/hopper-step/box structure, iridescence(), calcNormal, orbit camera, raymarch, 0.6 trail mix.
ADD (2 native ideas):
  1. Hopper terrace ledges: winning box's local frame re-derived (bismuthLocal), face-dominant Chebyshev distance quantized into 5 concentric square stair-steps; grooves darken diffuse and catch specular/treble glints.
  2. Bi2O3 oxide tarnish order: two-beam thin film (n=2.45, Snell, RGB 650/532/450 nm) whose thickness grows toward outer terraces (cooled first), with fold depth and mids; blended 45% with the original iridescence. Click ripples launch oxidation fronts that thicken film as rings sweep outward.
FLOOR FIXES: header replaced; textureSampleLevel(dataTextureC) -> clamped exact textureLoad with ACES-inverse decode; Reinhard approx -> real ACES; alpha now crystal coverage (fog-attenuated) + trail density + oxidation fronts (was max(input.a,...)); depth write added; plasmaBuffer clamped, treble now used; dead sliders wired with defaults reproducing old look: Complexity x -> fold iterations round(x)+1 (default 3 -> 4 original), Crystal Scale z -> DE space scale (default 1 = identity), Fog Density w -> fog start 7-10w (default 0.2 -> 5 original); Iridescence y keeps camera zoom and also scales film thickness (default 0.5 -> x1). Mouse added: key light follows mouse (centered mouse = original light), held orbits/dollies camera; ripples added. JSON features + params array added.
FORBID: dataTextureB writes, extraBuffer use, fake audio, replacing the hopper fractal.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live
