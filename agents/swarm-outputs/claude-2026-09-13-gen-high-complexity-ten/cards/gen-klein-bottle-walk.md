# Idea Card — gen-klein-bottle-walk

```
SHADER: gen-klein-bottle-walk
IDENTITY: a full-screen parametric (u,v) walk over a Klein-bottle-style tube surface — FBM-textured hue skin,
  finite-difference normal, a slowly orbiting diffuse/specular light, scrolling as time advances the walk.
KEEP VERBATIM: kleinBottlePoint() parametrisation, walkU/walkV = time*speed + uv*2π mapping (0.7 v ratio),
  fbm surface texture, cross(du,dv) normal, orbiting lightDir, hue2rgb colour chain (kb.z / noise / mids hue,
  treble saturation, bass value + radius), semantic alpha formula shape, ACES display.
EXISTING IDEAS: none named (2026-06-06 pass was hygiene: ACES/audio/header).
ADD:
  1. Orientation-reversing seam — every time the walk wraps around v the surface comes back mirror-flipped
     (texture u -> -u, normal inverted so the lit side becomes the unlit side), with a thin incandescent
     glide seam drawn where the flip happens; native because non-orientability is the one thing that makes
     this surface a Klein bottle rather than a torus, and it reuses walkV / the existing normal.
  2. Walker footprint trail — the previous frame is read from C with exact textureLoad a few pixels back
     along the walk direction and its highlights are kept as a decaying streak behind the scrolling surface;
     native because the effect is a *walk*, and the trail follows the existing walkU/walkV velocity.
FLOOR: zoom_params were shifted by one (x unused; Walk Speed slider drove nothing, Light Intensity drove
  texture) — realign to JSON slider names: x Walk Speed, y Texture Density, z Light Intensity, w Color Shift.
FORBID: spring cursor, click ripples, IQ cosine palette, raymarching a different 3D object, conveyors, dataTextureB.
A PACKING: ACES display RGBA (unchanged); C now read via exact textureLoad as colour history.
```
