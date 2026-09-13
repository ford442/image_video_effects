# Idea Card — gen-liquid-rainbow-glass

```
SHADER: gen-liquid-rainbow-glass
IDENTITY: a 2D stack of nine flowing, saturated rainbow liquid layers seen through thick glass — fbm flow
  layers, oil-film interference, refraction-offset layer, chromatic bubbles, edge glow, ribbons, caustics —
  with a mouse-held vortex stir.
KEEP VERBATIM: noise/fbm/fbm3, liquidRainbow, liquidLayer, glassRefraction, oilFilm, vortexStir, all 9 layer
  compositions and weights, post chain (0.85 curve, bloom, saturation push, Sellmeier CA), acesToneMap,
  temporal mix(prev*0.96, color, 0.25), alpha formula, slider roles (x Intensity, y Speed, z Scale,
  w Color Shift), bass/mids/treble mapping.
EXISTING IDEAS: none named (no Ideas: line).
ADD:
  1. Meniscus rims — a bright refractive lip where the thick main liquid (layer 3) meets clear glass: a
     narrow band around layer3.a≈0.5 with per-channel offset bands (R outside, B inside) so the rim itself
     splits into a rainbow; native because the glass/liquid interface is where real refraction and
     dispersion concentrate, and it reuses the layer-3 alpha the file already computes.
  2. Viscous stir memory — the existing (but never displayed) C history is read back advected around the
     pointer by a slow swirl, so a stir leaves a lingering curl in the liquid that relaxes after release;
     native because the effect's one interaction is "mouse stirs the liquid" and liquid has viscosity —
     HEAD computed the temporal field then threw it away.
FORBID: springs, u.ripples shockwaves, new cosine/IQ palettes, conveyors, extraBuffer state, dataTextureB,
  replacing the layer stack.
A PACKING: display-history RGBA (HEAD packing kept: A = mix(prev*0.96, color, 0.25), alpha = effect
  strength); C now read via exact textureLoad (HEAD used filtering u_sampler). Floor fixes: mouse uv was
  divided by resolution a second time (pointer stuck at corner) → use zoom_config.yz directly; depth was
  written as constant 0 → glass thickness from layer coverage.
```
