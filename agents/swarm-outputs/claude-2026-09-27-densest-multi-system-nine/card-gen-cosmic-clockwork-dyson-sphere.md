```
SHADER: gen-cosmic-clockwork-dyson-sphere
IDENTITY: a camera orbits a 5-fold KIFS brass lattice of boxes, tori and struts carved around a glowing
  Voronoi-roughened plasma core.
KEEP VERBATIM: noise/fbm, SDF primitives, map() KIFS + 3 tori + strut + event-horizon carve (body unchanged, now
  returns (d, dCore) as mapFull), normal/AO, getPlasmaColor, click shock rings (age = time - ripple.z, no .w),
  stepped rotation, camera orbit + mouse yaw/pitch, key light + brass base colour, core halo term, bass bloom,
  click gear ticks, hold glow, 120-step march / t>30 cut, 4 slider roles (Mechanical Complexity / Clock Speed /
  Plasma Intensity / Gear Ratio), saved params. applyGenerativePrimaryControls still never called (left).
ADD (native ideas):
  1. Plasma conduits (L443-453) — glowing seams on the F2-F1 borders of the existing p*5 Voronoi (F2 was computed
     and never read), palette from getPlasmaColor, pulses travelling outward along the radius, feed dimming with
     distance from the core. The description always promised "plasma conduits"; HEAD had none.
  2. Beer-Lambert chromatic transmittance (L256-264, L344-390, L455, L468-469) — plasma density integrated along
     the march (step capped to 0.1 inside the shell so the carved core is sampled), emission weighted by running
     transmittance, per-channel sigma (blue absorbed first). Brass behind the plasma is dimmed and reddened;
     integrated emission replaces the per-step volAccum sum; alpha uses plasma opacity.
  3. Core as light source (L266-282, L404-429) — brass lit from the direction of the singularity with
     inverse-square-ish falloff, a 14-step soft shadow toward the core (lattice casts radial shadows), analytic
     plasma optical depth reddening the core light, core specular; f0 is now real brass (HEAD's "Brass F0" was
     steel-grey 0.56).
FIX: voronoi3 double-added `neighbor` (points at 2*nb+h -> F1/F2 jump ~0.1-0.2 at every integer cell face, F2-F1
  borders < 1% of volume) -> `point - f`; core halo fed negative coreDist into exp() (up to ~7x gain, flat-white
  core) -> max(coreDist, 0); camera starts inside brass at ~6.5% of poses at default sliders (numpy port of
  map(ro): min d -0.17) -> near-clip escape before sphere tracing; voronoi3 recomputed per march step -> reused
  from mapFull; A/C double tone-map -> C blended after ACES in display space; depth passthrough -> march depth
  (near=1, miss=0). "Y-flip" was a no-op -> behaviour kept, false comment/header claim removed.
JSON: dead first "params" (hyphen ids) deleted; the surviving underscore-id block is byte-exact (node deepStrictEqual
  on params + updatedParams). features += audio-reactive, mouse-driven, upgraded-rgba; description appended.
FORBID: gear meshing / counter-rotation / escapement / tooth sparks (furnace + shipped clockworks), refraction through
  core (furnace), springs, new ripples, extraBuffer state.
A PACKING: ACES display RGBA; C read as display history and blended after the tone-map.
```

STATUS: final
