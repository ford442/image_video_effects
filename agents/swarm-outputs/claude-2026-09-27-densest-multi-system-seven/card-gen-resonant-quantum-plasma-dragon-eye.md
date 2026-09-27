# Idea Card — gen-resonant-quantum-plasma-dragon-eye

```
SHADER: gen-resonant-quantum-plasma-dragon-eye
IDENTITY (one sentence): a raymarched dragon eyeball inside a bioluminescent scale socket, vertical slit pupil
  holding a gold supernova, green/gold/abyss fibre iris ring, orbiting camera, mouse-look + gravitational lens,
  bass-dilated pupil, volumetric quantum-plasma haze.
KEEP VERBATIM: map() SDF family (eyeball sphere r=2, fibre ring at r=0.8 with Iris-Complexity polar fbm, slit
  ellipse 0.15+dil*0.4 / 0.6+dil*0.3, scale shell r=2.3 with fbm), mouse look-at rotation + lens (Aberration),
  camera orbit, pupil nova / iris ring / sclera veins / scale SSS shading, background plasma, 16-step volumetric
  plasma loop, CA tint, 4% C persistence, ACES*1.15. updatedParams byte-exact (Plasma Density, Iris Complexity,
  Pupil Sharpness, Aberration).
ADD (native ideas):
  1. Dilator-fibre stroma — the bare sclera cap between the slit and the fibre ring (HEAD painted it white with
     veins) becomes iris tissue: radial dilator fibres (count from Iris Complexity), gold pupillary zone -> green
     ciliary zone -> abyss root, and guanine iridophore flecks (reptile iris) that twinkle with view angle.
     Why: HEAD's iris is only a thin ring; this is the dragon eye's own iris deepened.
  2. Hippus coupling — the pupil breathes autonomously (slow irregular hippus, visible with audio=0), and the
     stroma is anchored margin-to-root, so fibres compress and crimp as the slit widens (bass adds on top).
     Why: fuses the pupil-dilation system and the iris system, which HEAD kept independent.
  3. Corneal dome — Fresnel sheen reflecting the plasma, a Purkinje catchlight from the key light, and refraction
     parallax that makes the stroma sit behind the cornea as the camera orbits. Why: an eye has a cornea; HEAD
     had none.
  4. Tapetum eyeshine — the pupil nova flares retroreflectively when the camera crosses the gaze axis, and the
     eye's light illuminates the EXISTING volumetric plasma density as a gaze shaft along the mouse-look axis
     (occluded behind the eyeball). Why: couples the volumetric plasma subsystem to the eye/mouse-look subsystem.
FORBID on this file: spring cursor, click ripples, IQ palette, bismuth hopper/oxide/crystal ideas (sibling
  dragon-core owns those), a breath plasma jet cone (shipped gen-ethereal-cyber-plasma-void-dragon owns that),
  collarette zigzag / Fuchs crypts (shipped gen-iris-bloom-fractal owns those).
A PACKING: ACES display RGBA (as HEAD); C persistence now mixed in display space so C decodes consistently.
```

## Slider wiring
- Pupil Sharpness was DEAD (HEAD computed `sharpPupil` and never used it). Now it is the slit's superellipse
  exponent n = clamp(2 * psDefault / pupilSharpness, 1, 4): at the saved default n = 2 exactly = HEAD ellipse
  (checked numerically, max |diff| ~1e-7); higher = sharper cat-slit tips, lower = rounded-rectangle slit.
- Plasma Density: background plasma, volumetric haze, gaze shaft. Iris Complexity: ring fbm + stroma fibre count.
  Aberration: lens, CA ripple, CA tint (unchanged).

## Silent bugs fixed
- Unbounded iris/pupil primitives: fibre ring (`abs(r-0.8)`) and slit ellipse were infinite cylinders along z, so
  from side views of the orbit a glowing slab/tube ran across the whole screen through the scale shell. Both are
  now bounded to the front cap of the eyeball (z<0, |p| < R + small). This changes side views (intended fix).
- `extraBuffer[0]` write: HEAD stored its bass envelope in extraBuffer[0], which the engine overwrites with raw
  bass every frame (and pixel 0's write raced other workgroups). Now stateless: smoothBass = plasmaBuffer[0].x.
- `textureSampleLevel(dataTextureC, …)` -> exact `textureLoad(dataTextureC, coord, 0)`; C (ACES display) was
  mixed into HDR pre-ACES; now mixed after ACES.
- `pow(1.0 - cosi, k)` bases clamped with max(…, 0) (cosi can exceed 1 by an ulp -> NaN).
- Hardcoded alpha 1.0 -> the `presence` HEAD already computed (hit alpha + plasma glow).
- Iris ring shading used world-space p while its geometry lives in mouse-rotated eye space; now eye space.
