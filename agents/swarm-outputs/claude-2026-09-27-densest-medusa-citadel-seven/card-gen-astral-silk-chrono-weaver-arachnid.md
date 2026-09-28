```
SHADER: gen-astral-silk-chrono-weaver-arachnid
IDENTITY: a glowing raymarched spider (body, abdomen, 8 animated leg capsules) with rotating glowing silk threads over
  dust and stars.
KEEP VERBATIM: body/abdomen/leg capsule SDF and leg gait (moved into mapSpider(); tips hoisted out of the march, same
  values), emissive shading + chrono pulse, star/dust background, the 6 rotating weaving threads (same endpoints, colour,
  flicker), ACES, slider roles as READ (x -> hue, y -> activity speed, z -> silk/leg thickness, w -> body brightness and
  now shockwave amplitude), saved params byte-exact (JSON z default 0.5 < min 1.0 — left as is, noted).
ADD (native ideas):
  1. Leg-anchored radial spokes — each leg tip holds a spoke out to a fixed anchor ring (r 3.6, y -0.7) at the leg's
     rest angle, so the gait wobble tugs the spoke. Drawn with exact ray-to-segment closest approach (silkSeg), which
     also replaces HEAD's single sample at ro+rd*t*0.6 for the 6 weaving threads.
  2. Orb-web capture spiral — 6 turns (48 chords) linking neighbouring spokes, u = 0.14 + 0.8*s^1.4 so spacing
     tightens toward the hub; chord ends ride the spokes, so inner turns jitter with the gait, outer turns stay taut.
  3. Hub shockwave fronts — two travelling rings (period ~1/(0.22*(0.6+0.4*y))) leave the hub and fade to the anchor
     ring, brightening body/legs then every silk strand they cross. Amplitude = w*1.6*(1+1.5*bass): "Shockwave
     Intensity" is now true; visible at audio 0.
FIX (all verified at HEAD):
  - Mouse dead: L86 divided 0..1 zoom_config.yz by resolution -> m≈(-1,-1), camera pinned ~1.8 rad overhead.
    Now m = yz*2-1, pitch = 0.45 - m.y*0.9 (mouse 0.5 -> 26° 3/4 view; top 1.35 rad, bottom -0.45).
  - L169 exp(-td*(28-thick*12)) coefficient negative for z > 2.33 -> whiteout. Now max(…, 8).
  - L150 normalize(pHit) fake normal -> central-difference SDF normal.
  - Feedback: A held ACES colour, re-blended as HDR and ACES'd again. A now stores HDR pre-ACES (clamped 0..64);
    carry weight kept at HEAD's 0.05+0.01*bass (raising persistence would be the forbidden "silk afterglow via C").
  - Depth t/12 inverted -> hit: 1 - t/12, miss: 0.
  - "chromatic-aberration" was a constant tint shift: tag dropped from header, code kept (relabelled), clamped >= 0.
  - aces-tone-map tag dropped from header Features (not a feature tag). JSON features: upgraded-rgba, audio-reactive,
    mouse-driven (all true).
  - Alpha: spider opaque (1), silk/void by luminance (HEAD's formula).
FORBID: plucked standing waves, dew beads, silk afterglow via C, agate banding, thread thin-film, tension sheen,
  over-under interlacing, spring cursor, screen-space ripples.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha.
WHERE: silkSeg L104-121; Idea 3 shockFront L123-133 + body L209-210 + per-strand multipliers; Idea 1 L244-250
  (anchors built L179-182); Idea 2 L252-267; fixes tagged "// FIX" (L95, L144, L228, L272, L289).
DEFAULT-LOOK SHIFT (GPU QA): camera no longer overhead (3/4 view); weaving threads are now full lines rather than
  blobs; a hub+8 spokes+6-turn spiral web surrounds the spider; periodic bright rings run outward.
```

STATUS: final
