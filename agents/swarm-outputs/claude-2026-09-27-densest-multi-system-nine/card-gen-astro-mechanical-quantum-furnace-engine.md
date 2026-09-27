```
SHADER: gen-astro-mechanical-quantum-furnace-engine
IDENTITY: a brass KIFS gear-train with teeth and rivets around a white-hot fbm plasma sphere, a plasma exhaust
  pillar through it, over a nebula starfield, with trails.
KEEP VERBATIM: noise/fbm/hash, KIFS fold loop incl. the non-mirror (1,1,1) fold and 0.2+i*0.05 per-level twist,
  torus gear SDF + 26-tooth / 13-rivet greeble, core fbm sphere + cavity carve, stream pillar noise, magnetic well,
  click rings (capped, age = time - z, no .w), 120-step march at 0.6 step factor, brass/plasma/nebula shading math
  (moved into shadeBrass/shadePlasma/nebula helpers, arithmetic unchanged), exhaust glow + Emission Threshold step,
  4 slider roles (Gear Complexity / Plasma Intensity / Refraction Index / Emission Threshold), saved params.
  The spring code is kept but is INERT (extraBuffer[133..] is zeroed every frame, so smoothMouse == rawMouse).
ADD (native ideas):
  1. Refraction through the plasma core — at a core hit, refract(rd, n, 1/refIndex) on the fbm-bumped surface,
     exit through the core sphere with a second refract(…, refIndex), and re-march the scene with the core
     removed, so the gear train and exhaust pillar are seen bent through the furnace. Composited by facing ratio
     only (limb stays opaque white-hot, centre is a ~40% window); no path-length absorption (that is dyson's
     Beer-Lambert). Makes the "Refraction Index" slider actually refract (1.0 = straight through); the old
     envWarp fbm frequency use is kept.
  2. Meshing gear train — every gear turns on its own axle (tooth/rivet angle advances; the torus is axially
     symmetric so only the teeth move), and the abs() mirror folds give neighbours opposite handedness so across
     each fold plane two gears counter-rotate with teeth travelling together = meshing. Alternate KIFS levels also
     counter-rotate ((-1)^i) at a 1.4^i gear ratio (small, deeper = faster). The tooth banding in shading now reads
     the local gear angle, so the stripes sit on the teeth and turn with them.
  3. Piston-chuff exhaust — the pillar always streams (turbulence floor 0.25 instead of 0 at audio=0) and swells in
     travelling puffs fired 4x per gear revolution (locomotive exhaust beat), coupling the gear train to the
     exhaust; audio still adds turbulence on top.
FIX: A stored post-ACES colour while C was re-blended as HDR and ACES'd again (double tone-map) -> A now stores the
  pre-ACES HDR blend (clamped 0..64), ACES only on writeTexture. Depth was far=1 (miss=1.0) -> near=1, miss=0.
  Header claimed live "bounded extraBuffer[133..138] state" -> marked inert. No pow-NaN / ripple.w / dead-mask /
  zero-C sites found. Step factor unchanged (0.6).
FORBID: Keplerian astrolabe gearing (celestial loom), escapement tick / mesh flash / gear-tooth sparks (clockworks),
  Cauchy dispersion / TIR (geode; TIR at exit falls back to the straight internal ray), core-as-light-source /
  Voronoi conduits / Beer-Lambert (owned by dyson-sphere).
A PACKING: raw HDR trail RGB (pre-ACES, clamped 0..64) + semantic alpha; C is read back as HDR (consistent).
```

STATUS: final
