# Coordinator review — trace-grade ten (2026-11-15)

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea has a `// ── Idea` comment.

| Shader | Verdict | Why |
|---|---|---|
| hex-circuit | pass | Trace alignment uses the gradient the file already computed. Heat uses C.a persist. Grid, vias, and the pulse color remain. |
| rgb-iso-lines | pass | Index lines and downslope ticks sit on the same iso test. Runners, slick, and parallax remain. Packing lie fixed and named. |
| mirror-drag | pass | Crease is the straight-vs-mirrored sample. Facet shade uses the existing shard angle. Mirror mix unchanged. |
| chroma-depth-tunnel | pass | Cauchy only rescales the existing path split. Fresnel uses bore radius and the existing fog. |
| gen-islamic-geometric-tiling | pass | Grout is the cell edge. Bevel is the star stroke’s two sides. Star equation and raw HDR packing unchanged. |
| green-tracer | pass | Strike tint is display-only. Bloom reads the trail in C. Stored trail is still untinted. |
| ascii-shockwave | pass | Bar is another step of the existing ramp. Cell luma is the same glyph chooser with more taps. Slider roles not rewired. |
| analog-film-degrade | pass | Matches the §12.6 second pass. Sepia constants and print-through unchanged. |
| color-blindness | pass | Matrices and the Unused slider unchanged. Hatch direction follows the type mix that was already computed. |
| glitch-ripple-drag | pass | Row tear replaces the drag only while the ripple is up. Dropout sits on that ring. Spring and A.a left alone. |

Checklist:

- [x] Idea Cards exist and were written before the diff
- [x] Each numbered idea is pointable in the WGSL
- [x] KEEP VERBATIM still holds (modes, kernel family, param roles)
- [x] Diff is not mostly header / ACES / spring boilerplate
- [x] No shared spring, ripple stamp, or new IQ palette
- [x] A packing matches how C is read
- [x] Saved params unchanged
- [x] Springs and ripples only where the file already had them (`glitch-ripple-drag` spring; existing click loops left as they were)
- [x] No §12.2 row on more than one file
- [x] Naga 10/10. extraBuffer clean. Dead sliders 0

Real-GPU visual QA is external. This review is structural.
