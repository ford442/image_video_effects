SHADER: crt-magnet (2nd pass)
IDENTITY: magnet over a CRT: convergence error, grille moire, purity stain, degauss, hex bloom
KEEP VERBATIM: existing 3 ideas, field/SDF, palette, echo, param ids
ADD:
  4. Bent raster — scan lines phased off displaced y; bow and bunch through the field
  5. Induced hum bar — rolling dark bar, rows wobble sideways inside the field, bass speeds it
RESCUES:
  - Spring + bass env in extraBuffer[133..139] (zeroed per frame) → never ran; moved to C state texels, sentinel -7.
  - Alpha = field*1.5 + env*0.3 → tube transparent outside the magnet; now 0.82..1.
  - Clamp ≥0 before ACES.
Stats (256px, 20f, t=3): idle meanL .512→.493 (scanlines), meanA .33→.90; held+audio .520→.514, meanA .69→.95.
Open: held+bass field covers most of the screen with orange palette (pre-existing); echo mixes ACES display into linear (pre-existing, mild).
