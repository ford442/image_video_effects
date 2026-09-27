```
SHADER: gen-astral-plasma-accretion-forge
IDENTITY: a noisy Keplerian-twisted disk of blackbody plasma with pole flares around a small black sphere.
KEEP VERBATIM: hash3/snoise/fbm, rotX/rotY/rotZ, the flattened-torus + fbm + pole-flare smooth-min SDF in map(),
  the static 1/(r+0.1) spiral twist and rigid time*spin rotation, get_color() blackbody ramp, 80-step march with
  the d<0.1 density rule and 0.05 min step, camera + held-mouse orbit, the 0.2 black sphere, fake volumetric bloom
  (now x0.3 behind the horizon, see 3) and flare glow. 4 slider roles: Core Density x (opacity), Spin y (0 freezes everything), Flux z (bloom),
  Core Temp w (temperature). Saved params byte-exact.
FLOOR (legacy file had none): audio from plasmaBuffer[0].xyz (removed the fake
  textureSampleLevel(dataTextureC,(0.1,0.5)) audio — once A is written that would be a self-feedback loop);
  ACES instead of Reinhard; semantic alpha = max(plasma coverage 1-T, horizon occluder, glow luma);
  write dataTextureA (display RGBA) + real depth (first plasma / horizon hit, near=1, miss=0);
  JSON: additive updatedParams, features (mouse-driven: held drag orbits the camera — true; audio-reactive;
  upgraded-rgba), description.
ADD (native ideas, all visible at audio = 0):
  1. Dust-lane absorption — the march becomes front-to-back emission/absorption with transmittance T. Core Density
     is the extinction coefficient (HEAD: it only set the early-break threshold; the new integral converges to the
     same 1/density emission budget; numpy port: mean frame luma 0.0135 -> 0.0084 from ACES toe + redshift + dust). A cool dust field in the disk midplane
     (azimuthally elongated noise in the sheared frame) emits 10% and absorbs 9x, so dark lanes cut across the
     plasma and hide what lies behind them. Dust sublimates inside r_sub = 0.9 + 0.5*CoreTemp: the hot inner
     rim stays clean and a hotter core pushes the lanes outward.
  2. Keplerian shear lanes — differential rotation Omega ∝ r_xz^-1.5 (normalised to 1 at the torus centreline
     r=1.5) on top of HEAD's rigid spin, so the inner rim laps the outer rim and fbm plasma + dust lanes shear into
     trailing spirals. Two-phase flow-map (16 s period, triangle crossfade) keeps the winding bounded forever.
     Spin still scales every term (0 freezes). Also fixes HEAD rebuilding the frame with 3D r as the xz radius.
  3. Gravitational redshift — g = sqrt(max(1 - rs/r, 0) / (1 - rs/1.5)), rs = 0.55: observed temperature *= g,
     emission *= g (stylised; bolometric would be g^4). The temperature peak lifts off the inner rim into a
     plateau, the inner rim dims and reddens toward the well, the far outer disk warms slightly (g>1 relative to the
     centreline), and pole jets (audio) rise out of a dark, red base. Consequence: HEAD's faint lilac core puck
     (the audio=0 flare disc at r<0.3) no longer emits, so the horizon now occludes the part of the fake core bloom
     behind it (x0.3) — the small black sphere reads as a crisp black dot in the glow instead of a dark dot in a ring.
FIX: black hole zeroed ALL colour incl. emission in front of it (L194-195) -> the march now stops at the horizon so
  only the far side is occluded; fake C-audio self-feedback removed; 3D-r xz radius (L79) fixed.
  snoise's unused n/step left verbatim (harmless).
FORBID: relativistic beaming crescent, phononic spiral waves, photon-sphere subrings, click lensing, lensed halo,
  springs, ripples, time dilation (bismuth-loom), beam/bunch dispersion (collider).
A PACKING: ACES display RGBA (new; nothing reads C any more).
```

STATUS: final
