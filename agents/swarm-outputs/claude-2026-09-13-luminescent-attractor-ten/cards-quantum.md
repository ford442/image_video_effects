# Idea Cards — quantum pair (claude-2026-09-13-luminescent-attractor-ten)

```
SHADER: gen-luminescent-quantum-flora-symphony
IDENTITY (one sentence): a raymarched smooth-union bloom (capsule stem, emissive core bulb, KIFS petal lattice) swirled around the mouse, floating in a hex spore lattice.
KEEP VERBATIM: map() SDF (stem capsule, core bulb, KIFS fold loop, smin blend, material ids); adaptive folds/steps from Petal Complexity; mouse Gravity Twist + orbit camera; spore volumetric accumulation + hexBorder lattice; slider roles x=Petal Complexity, y=Gravity Twist, z=Spore Density, w=Core Intensity; ACES; depth from hit t.
ADD (native ideas):
  1. Golden-angle phyllotaxis florets on the core bulb — a flower's centre is a Vogel seed spiral; the bulb currently is a flat emissive blob. Mids brighten florets.
  2. Petal veins + backlit translucency — recover the KIFS fold-space coordinate at the hit point, draw radial veins in it, and let the key light bleed through petals from behind (thin-tissue glow).
  3. Stem nodes + rising sap pulse — node rings at intervals along the capsule and a luminous pulse climbing from ground to bloom, bass-accelerated.
FORBID on this file: spring cursor, ripple shockwaves, IQ cosine palette, replacing the KIFS petals with a different flower/fractal, rewiring sliders.
A PACKING: ACES display RGB + spore accumulation in .a (HEAD packing kept; C is not read by this shader).
```

```
SHADER: gen-luminescent-quantum-glass-phoenix-egg
IDENTITY (one sentence): an iridescent noisy glass egg, refracting into an fbm plasma core, in cosmic fog with god-ray bursts.
KEEP VERBATIM: mapEgg / mapCore SDFs; outer shell march + refracted 64-step volumetric core march with tendrils; iridescent_shell Fresnel; key/fill/rim lights; bg dust, fog march, god rays; hue-preserving clamp + ACES + IGN dither; slider roles x=Plasma Hue, y=Core Activity, z=Glass Refraction, w=Glow Intensity.
ADD (native ideas):
  1. Voronoi hatch-cracks in the shell — a 3D cellular crack network on the shell surface, opening with Core Activity + bass (and wider while the mouse is held), through which inner ember light leaks as hot seams.
  2. Glass caustic threads — interference of two drifting noise fields gives thin focused caustic filaments on the shell where the core's light is concentrated by the glass; mids brighten.
  3. Ember afterglow memory from C — exact textureLoad of dataTextureC.x (previous ember heat), decayed and max'd with this frame's emission, so bass flares leave a cooling glow around the core/cracks.
FIX (floor, stated honestly): config.y (ripple count) was used as audio in mapCore and bloom -> plasmaBuffer[0].x bass; mouse was divided by resolution (always ~0, dead) -> uv 0..1 mapped to -1..1; "prev frame" persistence sampled readTexture (the input image, not history) -> removed in favour of idea 3; refract eta 1/max(refr,0.1) was >1 across the slider range (total internal reflection -> zero ray, core collapsed) -> IOR 1.0..1.6 from the same slider.
FORBID on this file: spring cursor, ripple shockwaves, IQ palette, turning the egg into a phoenix creature/bird, new sliders.
A PACKING: raw fields — x=ember heat (decayed emission memory, read back from C.x), y=core density, z=fog accum, w=alpha. Not tone-mapped.
```

---

## NOTES — gen-luminescent-quantum-flora-symphony

- **Kept verbatim:** `map()` (stem capsule, core bulb, KIFS fold loop, smin, material ids), `calcNormal`, `hexBorder`, adaptive folds/steps, orbit camera + mouse Gravity Twist, raymarch + spore accumulation, hex spore field, ACES, alpha, depth, slider roles.
- **A packing:** unchanged — ACES display RGB + spore accumulation in .a. C is not read.
- **Ideas in the diff:**
  1. Phyllotaxis florets — `fn phyllotaxis()` (Vogel golden-angle search, ~L135) applied in hit shading block "Idea 1" (~L230), core material only, mids-brightened.
  2. Petal veins + backlit translucency — `fn petalFrame()` (~L121, re-runs the warp+fold loop) used in "Idea 2" (~L236): radial veins + midrib in fold space, back-light tissue glow, treble lifts veins; petal material only.
  3. Stem nodes + sap pulse — "Idea 3" (~L249): node rings from `fract(p.y*2.5)`, gaussian sap front climbing the stem, phase nudged by bass (bounded).
- **Header:** standard banner with Features/Upgraded/Ideas/A packing; old history kept below.
- **JSON:** added `"features": ["mouse-driven","audio-reactive","upgraded-rgba"]` (key was absent). `updatedParams` untouched; the definition has no `params` key.
- **Gates:** `naga` Validation successful; `wgsl_precommit_gate.py --files` PASS (extraBuffer violations 0); `audit_dead_sliders.py --files` AUDIT PASS (note: it scanned 0 definitions because neither JSON has a `params` key — grep confirms all four `zoom_params.xyzw` are read).
- **Concern:** existing read of `extraBuffer[5..36]` as FFT bins kept as-is (read-only, gate clean).

## NOTES — gen-luminescent-quantum-glass-phoenix-egg

- **Kept verbatim:** `mapEgg`, `mapCore` fbm core (only its audio term fixed), shell march, 64-step refracted volumetric core + tendrils, `iridescent_shell` Fresnel, key/fill/rim lights, bg dust, fog march, god rays, hue-preserving clamp, ACES, IGN dither, slider roles.
- **Floor fixes:** `u.config.y` (ripple count) used as audio in `mapCore` and bloom -> `plasmaBuffer[0].x` (bass, bounded 0.12 / 0.2 gains). Mouse was `zoom_config.yz / resolution` (always ~0, so camera ignored the pointer) -> `yz*2-1`. "Temporal persistence" sampled `readTexture` (input image, not history) -> removed, replaced by Idea 3. `refract` eta `1/max(refr,0.1)` was >1 for the whole 0..1 slider range (TIR -> zero ray -> core march stuck at entry point) -> IOR `1 + refr*0.6`; slider still "Glass Refraction".
- **A packing:** raw fields — x=ember heat (max(emission, C.x*0.93)), y=core density, z=fog accum, w=alpha. Not tone-mapped. Read back via exact `textureLoad(dataTextureC, …, 0)`; nothing written to C.
- **Ideas in the diff:**
  1. Voronoi shell cracks — `fn crackEdge()` (~L125, F2-F1 cellular edge) used in hit block "Idea 1" (~L294): width from Core Activity × (1+bass×0.6) + mouse-held widening; shell darkens along seams, ember light leaks scaled by core density.
  2. Glass caustic threads — `fn causticThreads()` (~L147) used in "Idea 2" (~L304): dual-noise zero-crossing filaments, masked by (1-fresnel) and core density, mids-brightened.
  3. Ember afterglow — "Idea 3" (~L339): decaying heat from C.x; residue above current emission adds warm glow and alpha.
- **JSON:** `features` `[]` -> `["mouse-driven","audio-reactive","upgraded-rgba"]`; added trailing newline (file had none). `updatedParams` untouched; no `params` key exists.
- **Gates:** `naga` Validation successful; `wgsl_precommit_gate.py --files` PASS; `audit_dead_sliders.py` AUDIT PASS (0 defs scanned — no `params` key; all four `zoom_params` read).
- **Concerns:** JSON `updatedParams` names (Scale/Intensity/Speed/Detail) do not match the WGSL roles (Plasma Hue/Core Activity/Glass Refraction/Glow Intensity) — pre-existing, left for coordinator. Depth convention here is `t*0.1` on hit / 1.0 background (pre-existing, kept). Afterglow needs real-GPU check for ghosting when the mouse orbits quickly.
