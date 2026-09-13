# Idea Card — gen-liquid-neon-topography

```
SHADER: gen-liquid-neon-topography
IDENTITY: a forward-flying heightfield raymarch over domain-warped ridged-fBm terrain; dark metallic valleys, neon palette ridges with fresnel liquid edge glow and fog; mouse steers camera (x) and height (y).
KEEP VERBATIM: simplex noise + mapTerrain (domain warp 0.4, rotated octaves, 1-|h| squared ridges, *ridgeHeight*0.5),
  getDist floor offset, 100-step rayMarch, getNormal, neonPalette, camera rig (camTime, mx lookAt, my height),
  shading chain (baseColor, ridgeIntensity, fresnel^4, emission, fake SSS, fog), sky glow, slider roles
  (x Ridge Height, y Flow Speed, z Emissive Glow, w Contour Detail = octave count).
EXISTING IDEAS: none (no Ideas: line; file never upgraded).
ADD:
  1. Neon iso-height contour lines — thin glowing topographic contour bands on world height p.y, AA'd by
     distance, spacing densified by Contour Detail, flowing hue along the ridge palette; native because the
     effect is literally a *topography* with a "Contour Detail" slider that today draws no contours.
  2. Liquid neon pooling in the valleys — a flat, bass-lifted fluid level fills terrain below it; pooled
     pixels get a mirror-ish sheen that reflects the ridge palette (fresnel on the flat surface normal) plus
     slow ripple shimmer from the same simplex noise; native because "neon currents carve through" liquid
     terrain — the liquid now settles where the currents cut.
FORBID: springs, u.ripples shockwaves, IQ palette swaps (neonPalette stays as-is, not added), conveyors,
  new raymarch loops, extraBuffer state, dataTextureB.
A PACKING: ACES display RGBA (HEAD blended "history" from readTexture = the input image and sampled
  dataTextureC as fake audio — both packing lies. Now: display RGBA written to A, C read back via exact
  textureLoad as colour history for the existing 0.7 temporal blend; audio from plasmaBuffer[0].xyz).
```
