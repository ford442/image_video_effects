# Coordinator review — cursor/batch-35 neon edge and contour (2026-11-02)

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea is marked in the shader with a `// ── Idea` comment.

| Shader | Verdict | Why |
|---|---|---|
| neon-contour-drag | pass | Drag shear averages two Sobel taps along the pull tangent, inside the existing warp disc. Glass wall uses the gradient the tangent streak already has. Dual-scale Sobel, runners, and the bass core stay. |
| neon-contour-interactive | pass | Electrode caps fire where the tangent step drops. The mercury bead is the crest of the existing radial pulse. Six-tube palette, starter flicker, and diagnostic A stay. |
| neon-edge-diffusion | pass | Filament is the undilated `edgeC` on top of the bloom. Energy-conserving bloom (§12.2F) subtracts a fraction of the hex spread from the core before the 50/50 mix. Tile, dilation, and luma² taps stay. |
| neon-edge-reveal | pass | Hotspot and penumbra share the existing Scale radius. Gas afterimage multiplies the existing C burn per channel. Photo reveal, hot core, and the removed spring stay removed. |
| neon-edges | pass | Scale agreement weights the neon by min(scale 1, scale 3). The Mach trough notches the current the dark band already computes. Five scales, isotherms, and the spotlight stay. |
| neon-topology | pass | Index gap opens only on major contours, along the slope tangent the hachures use. Slope shade multiplies the existing hypsometric fill by `gLen`. Lens and quakes stay. |
| neon-poly-grid | pass | Shared wall reads neighbour trail from C.r. Flicker hits only the decaying tail; A.r stays the clean decay. Hex grid and the existing spring stay. |
| neon-quantum-lattice | pass | Phason kink nudges layer 1 where the existing defect mask is high. Ammann beat lights the gap between d1 and d2. Three layers, hop, and history advection stay. |
| electric-contours | pass | Electrode discs cap the two fixed charges and the cursor and cut the zebra inside them. Polarization is the Sobel normal dotted with E, tinted with the existing dielectric colour. Diagnostic A stays un-tonemapped. |
| edge-glow-mouse | pass | Mask trail adds glow from C.r and C.z instead of mixing those channels as RGB. Normal halo is two taps along the edge normal the film phase already uses. Oil-slick and diagnostic A stay. |
| edge-glow-mouse-em | pass | Soft inverse-square (§12.2F) replaces the singular coulomb core; Glow Radius sets the core. Leading glow uses the velocity already stored for B. Corona and the C streak stay. |
| posterize-neon-edges | pass | Cel filament lights `fract(luma × levels)`. Tangent ink waver slides the existing FBM along the Sobel tangent, and band-hold still kills it inside the flat. |

Formula check: no §12.2 row appears on more than one file. The two §12.2F rows are different formulae. No new spring. No shared ripple stamp. No shared palette.

- [x] Idea Cards and mechanism notes exist in `BRIEFS.md`
- [x] Each idea is pointable in the WGSL
- [x] KEEP VERBATIM still holds
- [x] Diffs are the ideas plus the floor (prelude migrate on three files, ACES and `dataTextureA` on `neon-contour-drag`)
- [x] A packing matches how C is read
- [x] Saved params unchanged
- [x] Naga 12/12, extraBuffer, dead sliders
