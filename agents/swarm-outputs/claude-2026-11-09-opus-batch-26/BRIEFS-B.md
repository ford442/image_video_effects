# BRIEFS — fork B (written before WGSL edits)

SHADER: scanline-sorting
IDENTITY: a scan band (pointer row/column or auto-scrolling) inside which 16-px tile runs are bitonic-sorted by luma, with chromatic edge shift.
KEEP VERBATIM: workgroup bitonic sort, threshold-gated sort blend, band from pointer/scan_speed, direction toggle, chromatic shift, 4 param roles.
RESCUE: HEAD does not compile (workgroupBarrier after an early return gated on atomicLoad = non-uniform) → effect was dead. Dead extraBuffer[133..138] spring removed. plasmaBuffer[1..255] palette reads are always 0 → band was just dimmed 20%; replaced by idea 3.
ADD:
  1. Threshold run streak — above-threshold pixels in the band drag a directional max-luma streak (8 taps along the sort axis), so sorted runs cross the 16-px tile seams like real pixel-sort spans.
  2. Sort-front tear — the band's leading edge (travel side) shifts whole rows/columns by a hashed offset, the glitch at the head of the sorting pass.
  3. Sorted-rank tint — sorted texels are graded cool→warm by their rank in the 16-lane run (replaces the dead palette).
FORBID: springs, ripples beyond HEAD's, IQ palettes.
A PACKING: ACES display RGBA (C not read).

SHADER: cyber-rain-em (2nd pass; HEAD Ideas: column lead-char bloom; EM wiper skew)
IDENTITY: digital glyph rain streaked by an electric charge at the pointer, with a wiper hole, field streamlines and click-orbit secondary charges.
KEEP VERBATIM: E/B field functions, orbiting ripple charges, blur streak, lead-char bloom, wiper, streamlines, A packing.
RESCUE: extraBuffer spring is zeroed every frame → mouseVel≡0 → moving-charge B field and the HEAD "EM wiper skew" idea were dead. Replace with A-texel (0,0) cursor state (prev mouse + time, sentinel alpha) → real pointer velocity.
ADD:
  1. Lorentz glyph curl — glyph columns bend sideways by v×B (totalB), so rain curls around a moving charge.
  2. Wiper meniscus lens — the wiper rim refracts the picture outward as a thin water ring (sample offset along the radial direction at the rim).
  3. Ionisation glyph density — glyph threshold drops where |E| is strong (+treble), rain gets denser near the charge.
FORBID: new palettes, generic ripples, springs.
A PACKING: ACES display RGBA; texel (0,0) = cursor state [mouse.x, mouse.y, time, 0.777 sentinel].

SHADER: data-slicer-interactive
IDENTITY: horizontal data slices displaced by noise/jitter with RGB split, edge glow, click shocks, a racing fracture packet and a held gravity well, with C trail feedback.
KEEP VERBATIM: slice phase, displacement chain, ripple burst/shock, split + CA, C feedback, A [trail, bass] + B packing, 4 param roles.
RESCUE: per-slice scanline modulation sin(uv.y*res.y*PI) is 0 at every pixel centre (dead) → replaced with a half-pixel offset.
ADD:
  1. Gravity-bent slices — slice phase is pulled toward the pointer (stronger when held), so slice boundaries bow around the well.
  2. Per-slice bit-crush — odd slices quantise colour to hashed 3–6-bit depth (jitter slider), the "data" in data slicer.
  3. Edge-row drag — just below each slice edge the boundary row is smeared down (sampled from the edge row), a torn-buffer drag.
FORBID: springs, palettes, overlays.
A PACKING: [trail RGB, smoothed bass] (unchanged); B [strength, offset, split, bass] (unchanged).
