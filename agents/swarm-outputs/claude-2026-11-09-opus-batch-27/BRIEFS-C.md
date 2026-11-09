# BRIEFS — fork C (written before WGSL edits)

SHADER: dimension-slicer (second pass; 2026-10-05 ideas = lit cut edges, slice drag memory, corridor parallax)
IDENTITY: three rotating x/|y| projection bands cut through the image, chromatic split, SDF panel borders, rim lines.
KEEP VERBATIM: 3 band angles/spins/widths, sliceAxis projection + corridor planes, rim + drag memory, 4 param roles.
RESCUE: none found at HEAD (renders cleanly, meanL 0.54, no NaN).
ADD:
  1. Lifted-band drop shadow — outside each band a soft occlusion falloff offset perpendicular to the cut (toward screen-down), so the slabs read as raised above the photo.
  2. Running glint — a bright highlight travels along each band's length (position = fract(time*speed + i/3)), bass speeds it; light racing down the cut.
  3. Torn cut edge — the band half-width is jittered by a 1-D value noise along the band axis, so cuts are ragged rips, not ruler lines (rims follow the tear).
FORBID: springs, palettes, new params.
A PACKING: ACES display RGBA (unchanged).

SHADER: spatio-temporal-3d-conv (second pass; 2026-09-21 ideas = motion-adaptive NR weights, variance-driven NR strength)
IDENTITY: 3×3×T Gaussian convolution over the history ring, three modes (denoise / motion blur / temporal sharpen).
KEEP VERBATIM: kernel, ring indexing, mode thresholds and weights, NR ideas, 4 param roles.
RESCUE: none found (history-ring indexing matches frame.ts head-after-write).
ADD (one per mode):
  1. Grain-preserving NR — denoise mode re-injects a small fraction of the removed luma residual (current − result) so detail/grain survives; no plastic skin.
  2. Highlight persistence (motion blur) — trail takes a per-channel max with age-decayed past highlights above a luma knee, so bright lights leave long-exposure streaks instead of grey smears; bass lengthens.
  3. Arrival/departure split (sharpen) — positive residual (light arriving) tinted warm, negative (light leaving) cool, so transients carry direction.
FORBID: springs, new params.
A PACKING: display RGBA (unchanged).
