# BRIEFS — fork B (written before WGSL edits)

SHADER: temporal-frequency-decomposition
IDENTITY: per-pixel Hann-windowed temporal DFT over the history ring; oscillating pixels glow, hue rotated by DFT phase, sprung lens + click pings.
KEEP VERBATIM: Hann DFT loop, ring-depth floor, click tuning-fork pings, lens sharpen, phase->hue, 4 param roles.
RESCUE: (a) on a 1-layer ring (VRAM floor) frames=1 so the "DFT" is just the current frame → whole image glows (yellow wash, minirender meanL 0.69). (b) plasmaBuffer[1..8] band voices are never uploaded (only index 0) → dead. (c) extraBuffer[133..137] lens spring is zeroed each frame → no-op; use raw cursor.
ADD:
  1. DC notch — subtract the windowed temporal mean from every sample before the DFT, so static pixels cancel exactly (fixes the 1-layer wash and the bright-static leakage).
  2. Second-harmonic voice — a 2×freq bin in the same loop; its share of energy shifts the glow toward the complementary hue, so square/strobe flicker reads differently from smooth sine motion.
  3. Treble shimmer bands — the dead per-band voices are replaced by 8 vertical bands gated by a hashed treble flicker (real plasmaBuffer[0].z).
FORBID: springs, palettes beyond hue2rgb.
A PACKING: display RGBA (unchanged; no C feedback).

SHADER: gen-fractal-clockwork
IDENTITY: raymarched infinite field of counter-rotating brass gears with escapement tick, sparks, mesh line, oil, jewels, hairspring; mouse orbit.
KEEP VERBATIM: gear SDF, tiling/parity, escapement, all six prior ideas, 4 param roles.
RESCUE: (a) image upside-down (near gears at top of frame) — flip uv.y. (b) floor plane shaded with the same brass as gears → flat brass wash, gears unreadable. (c) A held ACES display and fed back pre-ACES (re-grade loop) — store pre-grade linear in A. (d) dead extraBuffer spring → raw mouse.
ADD:
  1. Dark workbench floor with cast gear shadows — soft shadow march toward the key light; floor is dark oiled wood/slate so gears stand out.
  2. Guilloché engraving — concentric engine-turned rings on gear faces modulate specular.
  3. Brass dust haze — depth fog in warm amber, thickened by bass.
FORBID: springs, new palettes.
A PACKING: pre-ACES linear RGB (clamped 0..4) + alpha.

SHADER: cyber-lattice-bilateral
IDENTITY: cursor-warped neon grid over a bilateral-smoothed, hue-shifted image, with ripple sharpening, node discharge, seam snap and dream feedback.
KEEP VERBATIM: grid warp, bilateral loop, hue shift, ripples/node discharge/seam snap, held colour flip, 4 param roles.
RESCUE: (a) A stored ACES display, fed back via C into the pre-ACES mix and re-graded every frame (compress loop) — store pre-grade in A. (b) dead extraBuffer spring → raw mouse.
ADD:
  1. Data packets — bright dashes travelling along grid lines, per-line hashed speed/direction, rate pushed by treble.
  2. Chromatic line split — grid lines drawn at R/G/B offsets that widen with distortion near the cursor.
  3. Cell occupancy fill — each grid cell gets a faint tint from its centre luma, quantised (lattice "pixels" light up over bright image areas).
FORBID: springs, palettes.
A PACKING: pre-ACES linear RGB + alpha.
