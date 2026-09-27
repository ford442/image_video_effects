# Idea Card - gen-abyssal-chrono-coral (2026-09-27)

```
SHADER: gen-abyssal-chrono-coral
IDENTITY (one sentence): folded-fractal (abs-fold / rotate / smin) coral raymarched down a fast abyssal current, with glowing tip nodes and a cursor time-dilation well.
KEEP VERBATIM: fold loop + smin, growthRings, polypDetail, gravitationalLensing, abyssPalette, domain repetition + fbm3 warp, 4 params
  (x=Coral Density, y=Branch Complexity, z=Bioluminescence Intensity, w=Time Dilation Field = well radius), well/dilation numerics
  (local_time = base_time + smoothstep(w,0,dist)*12*(1+held)), age-based sediment rings from u.ripples (age = time - rp.z, no .w), held bloom,
  audio from plasmaBuffer[0].xyz, semantic alpha, ACES display trail in A.
ADD (3 native ideas):
  1. Growth-band strata - sawtooth ledges carved into each branch radius along its own axis (p.y after the fold), so a branch reads
     as accreted layers (nautilus / tree-ring ledges). Band phase rides `time` inside map(), which is already local_time, so bands
     visibly age faster inside the dilation well with no new state. Ledge line + band tint are shaded from a private g_band written by map().
  2. Gravitational red/blue shift with an Einstein-ring rim - inside the well the light is red-shifted (spectral matrix, not a palette swap),
     at the well edge a thin blue-shifted lensing ring brightens where coral/glow sits behind it. Uses the existing well radius; visible with audio = 0.
  3. Growth-front budding - tip-node radius swells in a travelling wave (sharp leading edge, slow decay) keyed on tip depth and local_time;
     the swelling nodes also burn hotter. The front runs faster in the well.
FORBID on this file: new springs / ripple layers, polyp crown (sibling gen-coral-reef-colony owns it), forking branches, skeleton/bleach memory,
  star polyps, altitude/curtain colour, any second palette stamp.
A PACKING: keep - ACES display RGBA in A (prev.rgb*0.94 mix, read back as colour from dataTextureC, alpha = semantic coverage). No change.
```

## Cleanup / bugs
- The `extraBuffer[133..138]` cursor spring never persisted (buffer zeroed every frame; `SPRING_INIT` always 0, so `smoothMouse == mouse`
  every frame). DELETED (byte-for-byte same picture). Header/description no longer claim "spring-smoothed cursor" / bounded extraBuffer state.
- `fres = pow(1.0 - max(dot(n,-rd),0.0), 3.0)` could see a slightly negative base (dot > 1 by rounding): clamped with max(...,0.0).
- No zero-C early return, no ripple.w use, no dead mask, no filtering sampler on C in HEAD.
- All four sliders were already live and distinct (density/radius, iteration count, glow gain, well radius).
