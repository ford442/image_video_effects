SHADER: gen-stellar-plasma-ouroboros
IDENTITY (one sentence): a hex-scaled serpent tunnel (cylinder carved by polar-repeated hex prisms, path-distorted) around a boiling blackbody/OkLab plasma core, with Fresnel rim and a mouse gravity nudge of the ray.
KEEP VERBATIM: sdCylinder / pModPolar / sdHexPrism carve and `max(cylD, -hexD)`, path distortion + rotation, 100-step march (`t += d*0.5`), fbm plasma glow accumulation, blackbody + OkLab surface colour, readTexture reflection, star fallback, Fresnel rim, mouse rd nudge, 4 params (Scale Density / Plasma Intensity / Anomaly Gravity / Time Warp) with roles and updatedParams byte-exact.
ADD (2 native ideas):
  1. Peristaltic plasma bolus — a soft pulse (period 16 z-units, travelling +z with Time Warp) that hinges the scale plates outward as it passes: the hex prism is tilted about its inner edge (z shift proportional to radial offset) and swung outward, displacing `hexD`. Native: it moves the exact scales the effect is built from, like a swallowing gullet. Visible at audio = 0 (mids only add amplitude).
  2. Seam light — plasma leaking through the hex gaps: an `exp(-|hexD|)` contour glow on the hit surface, gated by the bolus phase (dim ember between boluses, hot as it passes), coloured by blackbody and flickered by the existing fbm. Native: it lights the seams the carve already creates. Treble adds a slight flicker.
FORBID on this file: spring, ripples, C feedback "for completeness", IQ palettes, particle overlays, lensed sky / photon ring, beads along cylinders.
A PACKING: display RGBA (ACES) — HEAD never wrote dataTextureA.

Floor fixes:
- dataTextureA now written = display RGBA. The shader reads no C, so no C load is invented.
- ACES on display RGB with exposure 0.8 (0.5 -> ~0.54, 1.0 -> ~0.75; default look stays close, HDR glow now rolls off instead of clipping).
- Alpha: coverage/glow = mix(0.2, 1, max(surface hit, 1-exp(-1.5*glowLuma), seam)); floor 0.2 kept from HEAD.
- Depth: made truthful from march distance: hit ? clamp(1 - t/50, 0, 1) : 0 (near = 1; same convention as chrono-void-stag). HEAD passed readDepthTexture through.
- Audio: bass = plasmaBuffer[0].x (plasma boil offset, rim power/colour, as before); mids = bolus hinge amplitude; treble = seam flicker.
