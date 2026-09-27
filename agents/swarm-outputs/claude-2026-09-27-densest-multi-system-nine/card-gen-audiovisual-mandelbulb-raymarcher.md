```
SHADER: gen-audiovisual-mandelbulb-raymarcher
IDENTITY: a fast-morphing Mandelbulb coloured by orbit trap through a hue wheel, ridged greeble shell,
  spectral haze, cursor glow, click shock rings.
KEEP VERBATIM: OkLab + psychePalette + blackbody, power-morph DE + greeble ridge, orbit-trap hue (orbit / orbitCol /
  fractalCol), 90-step march at 0.92 and 0.0009 hit, trap micro-bands, fresnel rim, haze / shock flare / treble
  sparkle / cursor bloom, click shock rings, held spin-throttle + dolly, camera orbit, 4 slider roles
  (Iterations / Escape Radius / Glow / Video Blend), escapeRadius (6..8) far clip + depth normalisation,
  saved params. Inert extraBuffer[133..138] spring left in place (zeroed per frame, so smoothMouse == mouse).
ADD (native ideas):
  1. Escape-time strata — the DE now exports a smooth escape count nu = i - log(log r / log B) / log(power);
     the surface is terraced into onion shells (one per escape iteration) with a thin hue-stepped contour line
     at each integer crossing. These are the Mandelbulb's own escape-time level sets.
     Escape Radius (y) now ALSO drives the real bailout B = 2.4 * exp2((y - 0.5) * 1.4)  (1.48 .. 3.90).
     numpy port (96x64 rays, powers 5.4/8/10.6, iters 5/9/14): B(0.5) == 2.4 exactly in f32 -> default surface is
     byte-identical to HEAD; across the whole slider range the hit mask is 99.97% identical (the set boundary does
     not depend on B), 0 NaN/inf, and the strata slide by ~0.60 +- 0.10 of a shell. So the slider's visible job is
     "slide the strata shells", distinct from the other three.
  2. DE soft shadow (20 steps, IQ penumbra k=8, 0.4 fill floor) + 5-tap normal AO (k=2) — the bulb read flat
     (no occlusion at all); crevices between greebled lobes now darken and lobes shadow each other.
  3. Trap-coloured silhouette halo — the march tracks the closest approach (min DE), the orbit trap and |p| at that
     point; missed rays grazing the bulb glow in the hue the surface would have there (same orbit formula),
     exp(-minD * 30). Scaled by Glow (its HEAD miss term 0.02/(t^2+0.1) ~ 0.0003 at t~7 is dead; kept verbatim).
     numpy: ~30% of missed rays have minD < 0.05 -> a halo band a few pixels wide around the silhouette.
FIX:
  - header claimed "held power surge" (g_power never reads held) and "bounded extraBuffer[133..138] state"
    (zeroed every frame) -> header corrected.
  - double tone-map: A stored post-ACES colour, next frame C was mixed into pre-ACES HDR and ACES'd again ->
    A now stores the HDR scene colour (post-trail, pre-CA/exposure); C decodes as the same HDR.
  - "CA" (L324) is a constant R+/B- tint, not an aberration: left as-is (part of the HEAD look), noted.
FORBID: springs, new ripples, IQ palette stamps, a different fractal, sibling ideas (4D W-slice, etc.).
A PACKING: A.rgb = linear HDR scene colour after trail blend (pre-CA tint, pre-exposure/ACES), A.a = semantic alpha.
  C is read as that same HDR colour for the 6% trail; writeTexture alone gets ACES.
```

STATUS: final
