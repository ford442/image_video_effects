SHADER: gen-prism-tide
IDENTITY: Refractive spectral tide — concentric RGB interference wavefronts with crests, foam, sparkle, OkLab prism palette mix, animated caustics, Mie haze, split-tone grade, ACES, premultiplied output.
KEEP VERBATIM: palette/OkLab/ACES/huePreserveClamp/ignDither, noise/fbm, mieScattering, caustics, per-channel dispersionR/G/B phase, crest/foam/sparkle, palette overlay, caustics, haze, split tone, alpha/depth formulas, premultiplied output.
ADD (2 native ideas):
  1. Cauchy prism dispersion — per-channel phase offset (n(lambda) - n_green) * |refraction field| * waveScale, n = 1 + 0.012/lambda^2, so RGB wavefronts split into spectral fringes where the water refracts (violet bends most); treble widens the split; vanishes when Refraction = 0.
  2. Click tide packets with water-wave dispersion — each click sums 4 wavenumbers obeying w^2 = g k tanh(k h) (long waves outrun short, packet spreads), height perturbs the tide phase; packet steepness past the Miche limit (~0.142) spills breaking foam.
FLOOR FIXES: textureSampleLevel(dataTextureC, uv) -> clamped exact textureLoad; dataTextureA previously held (crest, foam, sparkle, alpha) while C feedback read it as color -> now same final RGBA as writeTexture; plasmaBuffer[0].xyz clamped; click ripples added (none before); mouse-held added (cursor acts as a denser prism lens boosting local refraction); params array added to JSON (waveScale/refraction/pulse/saturation, values copied from updatedParams); header replaced; Uniforms comment lists slider names.
FORBID: replacing the concentric tide motif, extraBuffer use, dataTextureB writes, plasmaBuffer beyond [0], changing updatedParams.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (0 violations) / sliders x,y,z,w live
