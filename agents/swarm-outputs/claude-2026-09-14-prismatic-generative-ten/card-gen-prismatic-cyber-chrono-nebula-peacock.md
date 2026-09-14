SHADER: gen-prismatic-cyber-chrono-nebula-peacock
IDENTITY: Raymarched quantum-glass peacock body (cylinder + head) with a polar-repeated fractal-folded tail train, golden eye-spot glow, and a blue FBM nebula backdrop; mouse acts as a gravitational singularity.
KEEP VERBATIM: sdSphere/sdBox/sdCylinder, smin, hash33, nebulaFBM, body SDF + bob/rotation, polar feather repetition (12 + spread*8), 4-iteration fold, eye-spot glow accumulation, RGB-offset IOR refraction on body, teal->magenta iridMix, camera.
ADD (2 native ideas):
  1. Barbule thin-film interference: keratin film (n=1.56), thickness swept along the vane (330-480nm + spread), per-wavelength phase 2·n·d·cosθt / λ(650/530/450) mixed 50/50 with the original teal/magenta base and driving the fresnel rim; mids speed the thickness sweep.
  2. Zoned ocellus eye-spots: at feather hits the fold-space point is re-derived (featherFold helper shared with map) and shaded into concentric pupil / cobalt / bronze / teal / gold-halo zones, scaled by audio.
FLOOR FIXES: removed fake audio (u.config.y and u.config.y*zoom_params.w) -> plasmaBuffer[0].xyz clamped, Audio Reactivity (w) kept as gain; added dataTextureA write (same RGBA as writeTexture) and writeDepthTexture; clamped ACES helper; alpha hardcoded 1.0 -> coverage (glass fresnel / feather diffuse+ocellus / nebula density + eye glow + ring); added mouse-held (deepens gravity well x2.2) and click ripples (min(u32(config.y),50) loop: expanding gold/teal display rings + train-rattle shiver in feather fold rotation); header replaced; JSON params gained id/mapping, features added. No C feedback, no extraBuffer, no B write.
FORBID: replacing the fractal train or body, extraBuffer use, dataTextureB writes, scaling clicks by ripples[i].w, generic palette/bloom overlays.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live (x spread+film, y body IOR, z nebula, w audio gain)
