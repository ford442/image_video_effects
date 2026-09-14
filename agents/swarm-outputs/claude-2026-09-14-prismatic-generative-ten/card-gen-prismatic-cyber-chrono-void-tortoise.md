SHADER: gen-prismatic-cyber-chrono-void-tortoise
IDENTITY: Raymarched biomechanical cosmic tortoise — smooth-union SDF body/limbs/head/tail with swimming gait, chrono-glass shell intersected with a KIFS pocket dimension, hex-scute seams, abyssal mote sea with ripple rings.
KEEP VERBATIM: rot3D, smin, sdCapsule, hexBorder, moteField, kifs, map (mouse gravitational drag + held twist), calcNormal, adaptive raymarch + KIFS LOD, soft shadow, ripple loop, slider semantics (Time/Audio Reactivity/Brightness/Evolution Speed).
ADD (2 native ideas):
  1. Scute growth annuli — concentric keratin growth rings inside each hex scute (hexCell centre distance, 4-7 rings per scute seeded by cell id), drifting outward with chrono time; treble*AudioReactivity sharpens ring lines.
  2. Hawksbill tortoiseshell mottling — per-scute melanin blotches over amber keratin; backlit amber windows transmit the prismatic pocket glow while dark patches occlude it (bass lifts backlight).
FLOOR FIXES: removed forbidden extraBuffer[5..36] FFT read (hue phase now driven by plasmaBuffer mids); plasmaBuffer[0].xyz clamped 0..1; dataTextureA now receives the same final RGBA as writeTexture (was mat id in alpha); alpha = body coverage when hit / mote+ripple glow density in the sea (was luma); header replaced; JSON gained params array (ids time/audioReactivity/brightness/evolutionSpeed) + features. No dataTextureC use, no dataTextureB write, no extraBuffer use.
FORBID: extraBuffer reads outside 133..138, u.config.y as audio, replacing the tortoise/KIFS shell motif, generic palette overlays.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live
