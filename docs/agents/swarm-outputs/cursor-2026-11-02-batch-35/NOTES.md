# Notes — cursor/batch-35 neon edge and contour (2026-11-02)

Second pass. Each file already named ideas; two more were added inside that path. Saved `params` stay byte-exact. No new spring. Three pasted headers (`neon-contour-drag`, `edge-glow-mouse`, `edge-glow-mouse-em`) were migrated with `migrate_to_prelude.py` before the idea edit; that swap is not the upgrade.

| Shader | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| neon-contour-drag | dual-scale Sobel, radial warp, tangent streaks, runners, hue conveyor, click fronts, bass core, emissive alpha | ACES display RGBA. C unread. A matches the display | drag shear; glass wall |
| neon-contour-interactive | threshold, glow, cycle, pulse; 3×3 Sobel; six-tube palette; radial pulse; starter flicker; diagnostic A | diagnostic (isEdge, glowStrength, proximity, alpha). ACES on writeTexture | electrode caps; mercury bead |
| neon-edge-diffusion | tile Sobel, dilation, luma² hex, tangent stretch, ripple loop, four slider roles | ACES display RGBA (unchanged; C unread) | filament core; energy-conserving bloom (§12.2F) |
| neon-edge-reveal | intensity, speed, scale, detail; gas orientation; hot core; 3 px halo; photo reveal; C burn-in; no spring | soft-knee display RGBA. C is that burn, exact load | flashlight hotspot; gas afterimage |
| neon-edges | five scales, Mach bands, inverse-square spotlight, Kelvin isotherms, current along the tangent | ACES display RGBA (unchanged) | scale agreement; Mach trough |
| neon-topology | density, height, mouse force, glow; fract lines; majors; hachures; hypo fill; lens; quakes | ACES display RGBA (unchanged) | index gap; slope shade |
| neon-poly-grid | hex grid, scale, width, glow, decay; existing spring; trail in A.r; vertex glow; cell fill | trail in A.r (unchanged). ACES on writeTexture | shared wall; dying-tail flicker |
| neon-quantum-lattice | inflation, glow, parallax, brightness; three Penrose layers; defect highlight; electron hop; conveyor history | ACES display RGBA (unchanged; exact C) | phason kink; Ammann beat |
| electric-contours | threshold, glow, field density, spark; two charges plus the cursor; equipotentials; field lines; corona; diagnostic A | field diagnostics, un-tonemapped (unchanged). ACES on writeTexture | electrode discs; dielectric polarization |
| edge-glow-mouse | threshold, radius, intensity, color cycle; tangent bloom; oil-slick; packets; click rings; diagnostic A | (glowMask, mouseAura, packetEnergy, alpha). The trail now reads C.r and C.z | mask trail; normal-side halo |
| edge-glow-mouse-em | threshold, radius, intensity, color cycle; Laplacian corona; E and B; advection from C; previous-mouse in extraBuffer[133..134] | ACES display RGBA (unchanged; exact C) | soft inverse-square core (§12.2F); leading-edge glow |
| posterize-neon-edges | levels, threshold, glow, hue; band-hold flats; Sobel ridge | ACES display RGBA (unchanged) | cel filament; tangent ink waver |

Formula use: energy-conserving bloom (§12.2F) on `neon-edge-diffusion` only. Soft inverse-square (§12.2F) on `edge-glow-mouse-em` only. No shared row.

Floor: `#include "_prelude.wgsl"` on all twelve. 16×16. Exact C where history is read. Saved params exact. `x-meta.upgrade.params` added for `neon-contour-interactive` and `neon-edge-diffusion`. `edge-glow-mouse-em` gained `upgraded-rgba` because ACES and the ideas are both in the WGSL. `neon-contour-drag` now writes `dataTextureA` (it had the tag and no A store).

Gates: Naga 12/12, precommit 12/12, extraBuffer 0 new, dead sliders 0 new on these twelve, catalogs regenerated. Vitest 180 files / 1531 passed, 1 skipped, 1 failed (`RendererManager` device-loss: `second.fatal is not a function`). That file passed 45/45 on re-run. It does not touch these shaders. `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA is external.
