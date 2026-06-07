# Visualist Upgrade Notes: lava-lamp-blobs

## Key Visual Improvements
1. **Blackbody temperature blobs** — core and halo colors now derive from audio-reactive color temps (2000K–7000K) for realistic lava warmth
2. **3-point lighting approximation** — key light (warm core) + fill (cool halo via OkLab mix) + rim (hot grazing-angle Fresnel edge)
3. **Subsurface scattering glow** — light penetration at blob edges adds organic translucency
4. **Volumetric haze** — Beer-Lambert depth atmosphere softens blobs far from center
5. **Full tonemap & dither stack** — HDR accumulation, hue-preserving clamp, ACES, IGN dither, sRGB gamma, premultiplied alpha
6. **Bloom-weight alpha** — compositing-friendly bloom contribution in alpha channel

## Line Count
190 lines (target ~170, ±20% ✓)

## Issues
None. Blob field math, binding contract, and Uniforms struct unchanged.
