SHADER: gen_orb (JSON id "gen-orb", name "Lorenz Strange Attractor")
IDENTITY: Audio-reactive Lorenz strange attractor — RK4-integrated streams (8..14) projected with velocity-sized glow, bioluminescent depth halos, persistent scent trail.
KEEP VERBATIM: hash3, lorenzDerivative, rk4Step, acesToneMapping, stream loop (warmup 500 / 400 steps), hue ramp, halo/line glow, butterfly wing highlights, vignette, σ/ρ/β mappings.
ADD (2 native ideas):
  1. Lobe-switch sparks — white-hot pinpoints where a trajectory crosses x=0 (hop between the two wings), treble-brightened.
  2. Unstable fixed-point eyes C± = (±√(β(ρ−1)), ±√(β(ρ−1)), ρ−1) — projected cores + rings whose radius tracks √(β(ρ−1)) (moves with the σ/ρ/β sliders), bass-swelled.
FLOOR FIXES: plasmaBuffer[0].xyz clamped; textureSampleLevel(dataTextureC) -> exact clamped textureLoad; trail now feeds back the ACES display RGBA (same RGBA to writeTexture + dataTextureA, previously A held an HDR trail != output); readTexture composite removed (pure generative output, alpha = glow presence / trail coverage); resolution bounds check added; mouse added (hold+drag orbits/tilts camera; no effect when not held so default look unchanged); click ripples added (butterfly-effect kick on jitter amplitude + faint expanding ring, loop min(config.y,50)); projection factored into projectLorenz (identical math); header replaced; Uniforms comment lists sliders. JSON already compliant (params + updatedParams + features) — unchanged.
FORBID: extraBuffer use, dataTextureB writes, plasmaBuffer beyond [0], ripples[i].w scaling.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x(σ),y(ρ),z(β),w(trail persistence) live
