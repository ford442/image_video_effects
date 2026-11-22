# NOTES — fork A (liquid family)  2026-11-22

Files: public/shaders/{liquid-pass1,liquid-pass2,liquid-optimized-pass1,liquid-optimized-pass2}.wgsl. JSON untouched (coordinator). Idea Cards: BRIEFS-forkA.md.

## RESCUES (HEAD defects, not ideas)
1. **Wave-equation signs reversed in both pass-1 solvers.** `-gravityScale*lapH*0.1` (anti-restoring) and `+sigma*biLap*0.001` (anti-stiffening). Isolated test (no ambient/fringe/click, seed 0.01, mrchain.mjs): HEAD checkerboard mode 0.0100 -> 0.0151 (f60) -> 0.5000 clamp (f300); low-k mode saturates by f900. Gravity flip alone -> stable; capillary flip alone -> still grows. Fixed both. Constants: c2 = gravity*150, tension = sigma*40 (omega*dt <= ~1.2 at max sliders, symplectic Euler stable < 2). Wave speed at defaults ~14 cells/s (HEAD effective speed with a correct sign would have been ~0.4 cells/s, i.e. frozen).
2. **Pass-2 gains assumed saturated +-0.5 noise.** With a stable solver |h| ~ 0.02-0.1, so HEAD normals/caustics/streaks would render ~nothing. Slope and curvature are now per-UV (resolution independent); gains: liquid-pass2 slopeGain = 2.25*sigma*(0.65+turb), refraction 0.045*sigma, curvature/1500; opt-pass2 slope gain x9.5 (viscous solver is ~13x quieter), streak x30 (was x6), Snell offset gets a 0.06 base depth.
3. **C reads were `textureSampleLevel(non_filtering_sampler, uv)` at uv = gid/res** (texel boundary, no +0.5). All four now `textureLoad(dataTextureC, clamp(ivec))`; uv is pixel-centre. Pass-1 stencils are one 13-tap set (HEAD re-sampled 25+ taps).
4. Ripple loop guarded `min(u32(u.config.y), 50u)`.

## IDEAS (2 new per shader; all marked `// ── Idea N`)
- liquid-pass1: (1) Faraday parametric forcing: g_eff = g(1 + 0.6*bass*cos(2*w_k*t)), w_k from the file's own dispersion at 0.045*res.y wavelength; (2) dispersive precursor: second click packet at 2.4x wavenumber with a travelling Gaussian-shell envelope at its own group front.
- liquid-pass2: (1) sun glitter: Blinn facet specular pow 320, treble sets density; (2) Cauchy dispersion: R/G/B refraction offsets scaled 1-0.18a / 1 / 1+0.26a (a = 0.5 + Ripple Strength), exaggerated.
- liquid-optimized-pass1: (1) bass-forced basin slosh (first seiche mode cos(pi x) * sin(1.9 t)); (2) scale-selective viscous damping nu*lap(v), nu = (0.3+2.4*Damping)*(1+1.5*Turbidity).
- liquid-optimized-pass2: (1) Henyey-Greenstein in-scatter veil scaled by Turbidity (default 0 -> clear-water default unchanged); (2) TIR roll-off past the critical angle (smoothstep on normal.z 0.80..0.62) to a darkened mirror tap.

## Kept verbatim
Analytic click packet, depth gate, meniscus, ambient swell, crest lean + Color Shift fringe (pass1), seiche beat + shore set-down + branchless masks (opt-pass1), caustics + wetting rim + Fresnel/Beer alpha (pass2), Snell offset + velocity streak + tangent sheen (opt-pass2), ACES only in the two render passes, saved params (all four zoom_params still read in every file).

## A packing
Unchanged raw (h_prev, h_curr, velocity, age) written by both pass-1 files (h_prev slot still holds last h_curr; age still accumulates, nothing reads it). Pass 2 files do not write A or B. ACES only on writeTexture.

## Measurements (agents/mrchain.mjs, SwiftShader, DEPTH=const:0, 1 click)
- Stability 3000 frames (50 s): liquid-pass1 mean|h| 0.014-0.04 at defaults, bass=1 max|h| 0.29 (velocity clamp is hit at bass=1, so Faraday depth was reduced 0.9 -> 0.6), corner sliders (1,1,1,1) 0.23; opt-pass1 max|h| <= 0.16 at every corner tried. NaN 0, h saturation 0.0000 everywhere. A16=1 (rgba16float data textures) 1500 frames: NaN 0, meanL 0.486.
- Timing (min of drained frames, 384px, 2 clicks, interleaved, load from sibling sessions): liquid pair NEW/HEAD = 0.91, 0.99, 0.93, 0.87; optimized pair 0.92, 1.09, 1.12, 0.95 (medians ~0.92 and ~1.02). Within the 1.3x cap.
- Gates: wgsl_precommit_gate 4/4 (naga OK, no pasted headers, no extraBuffer use).

## Open calls for the coordinator
1. **Default look changed on purpose**: HEAD at defaults was ±0.5 saturated chop; the rescue shows calm water with a click ring. Real-GPU visual QA is external.
2. JSON `features`: liquid-pass1, liquid-pass2, liquid-optimized-pass1 now read plasmaBuffer[0] -> add `audio-reactive`. liquid-optimized-pass2 has NO audio by design (render only). liquid-pass1/opt-pass1 JSON still have `mouse-driven` but no zoom_config read — pointer is only via ripples (u.ripples), same as HEAD; left as is.
3. Pass 1's crest lean (0.12 * slope * velocity) is second-order and now ~1e-4 per frame: kept verbatim, effectively quiet on a stable solver.
4. Faraday needs sustained bass; at bass=1 the whole frame fills with standing capillary waves (strong). Slosh is a subtle tip of the surface.
5. ACES still tone-maps the whole frame in both pass 2 files (HEAD behaviour), including un-watered photo areas.
6. Ambient swell and Color Shift fringe are still added to the stored height each frame (HEAD mechanism); with a restoring solver they stay bounded (see measurements).
7. Pass 2 reads pass 1 one frame late (linear chain, no copy between passes) — by design.
8. Debug copies and HEAD copies live in the session scratchpad only (dbg/, head/).
