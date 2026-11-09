# NOTES — fork D (sonnet/batch-21): 4d-projection-dream-weavers, tesseract-fold

Files touched: public/shaders/4d-projection-dream-weavers.wgsl, public/shaders/tesseract-fold.wgsl,
shader_definitions/generative/4d-projection-dream-weavers.json (description only),
shader_definitions/image/tesseract-fold.json (description only). Not committed. Renders in ./forkD/.
Params / ids / defaults / x-meta byte-exact in both JSONs. Gate: naga OK 2/2, extraBuffer 0 violations,
dead sliders 0 new, audit_extrabuffer PASS (neither file touches extraBuffer any more).

## 4d-projection-dream-weavers   (Ideas: hyper-rotation; perspective divide + w-fog; w-dispersion)
KEPT VERBATIM: 4 params + roles; 3 per-channel 4D offsets (bass→R x, treble→B x); navy(0.1,0.15,0.25)→cream(0.9,0.85,0.7) gradient;
cosine dimension tint at 0.25; extraColor from z,w; worley dust (F1^24, depth-fade, treble gain); ACES(x1.1) on display; depth = depthField.
A PACKING: HDR linear colour (pre-ACES) as HEAD; texels (0,0)=(z,vz,w,vw) and (1,0)=(fract(t),0,0,0.7371) are spring state/sentinel; trail loads skip them (trailTexel).
RESCUES (HEAD bugs, all documented in-file):
 1. flat white frame — octave sum unnormalised (mean ~1.0 → mix() extrapolated past cream → ACES shoulder) → divide by (1+0.75*detail), smoothstep stretch. Also fixes dust being invisible (depthField ~0.9 made depthFade≈0) and alpha pinned at 1.
 2. noise4D ignored w (hash on i.xyz only) → two 3D lattices at floor(w), floor(w)+1, smoothstep blend. Mouse-x (w) now does something.
 3. spring dead: dt was u.config.y (= click count), state in extraBuffer[133..136] (zeroed every frame, thread-(0,0) race) → A-texel scheme + dt from fract(time) diff, critically-damped (~0.9) integrator.
 4. diamond-lattice hash artifact (vec4 hash with w lane = 0) → standard sine-free hash13. The 45° lattice was visible in every HEAD frame.
 5. time*(speed+bass*0.8): phase jump of time*dBass per beat (unbounded as session grows) → bass is a bounded phase kick (+0.6*bass); speed slider alone sets the rate.
 6. filtering sampler on rgba32float C → exact textureLoad; trail mixed noise-values with finished colour → trail now in colour space; finalCol clamped >=0 before ACES (z+w extraColor could go negative).
IDEAS (look for `// ── Idea n`):
 1. Hyper-rotation: XW and YW Givens rotations of (c*scale, z, w) before every noise tap; worley dust uses the same rotated/projected coords (was independent overlay).
 2. 4D→3D perspective divide persp=1/max(1-0.22*wRel,0.4) on xyz (wRel = tilt-induced w, mouse w offset subtracted so the cursor navigates rather than zooms), plus far-side fog toward navy.
 3. Dispersion along w: R at w-0.14*persp, B at w+0.14*persp (+ the old audio x offsets) so the chromatic dimension split exists at silence (HEAD was monochrome at normal audio: offsets ~0.01).
FORMULAE: hyper-rotation and perspective divide are 4D-native (no §12.2 row); no E/C row used. (Trail-advection idea from the card was dropped: at 0.12 trail weight the displacement was sub-pixel; replaced by idea 3, card updated here.)
Stats @192px, t=2..5, audio .4/.3/.2, JSON defaults: BEFORE meanL 0.794 stdL 0.012 meanA 0.999  →  AFTER meanL 0.564 stdL 0.090 meanA 0.669. 0 NaN. silent 0.603/0.075, loud 0.566/0.093, held mouse(0.3,0.6,1) 0.691/0.074. 576px and T0=300 clean (smooth, no block mosaic).
CHECKS: spring state survives frames (debug render: z,w == targets 2/24/60 frames, sentinel valid). NOT checkable here: rgba16float A tiers (minirender is rgba32float) — f16 resolution on z,w ~0.002, fract(time) dt noise ≤3%; real-GPU QA external.

## tesseract-fold   (Ideas: 4D double rotation + perspective; crease-trap lead came §12.2E; fold-count glass thickness §12.2E)
KEPT VERBATIM: 4 params + roles; R=rot2(a2)*rot2(a1) spin; held shear; clickShell; kaleido segs; abs/translate/rotate loop; sampleUv; chroma split; iridescent grade; square-grid lead + innerWave; vignette; neonGlow; ACES+gamma; depth passthrough; early-exit.
A PACKING: display RGBA (post-ACES, gamma). A was never written at HEAD; now written (both paths). No history is read, so no conflict.
IDEAS:
 1. After R/shear/click: lift p to 4D, bounded XW/YW rocking (amplitude = 4D Rotation Speed, so p1=0 => no tilt, identical to HEAD geometry), perspective factor clamp(1-0.9w',0.45,1.8) applied as sampling coordinate.
 2. Orbit trap creaseTrap = min over the 3 fold iterations of min(|p.x|,|p.y|) → lead came width 0.006+0.010*p3 (Edge Glow Width role) + bevel glint.
 3. foldCount (+= p.x<0, p.y<0 per iteration) → Beer-Lambert absorption toward the pane's glass colour, density darkening, alpha*(0.8+0.4*thickness).
FORMULAE: §12.2E Orbit trap; §12.2E Fold count as material (family sentence: the abs/translate/rotate loop is a KIFS). Idea 1 is not a table row.
Stats: BEFORE meanL 0.326 stdL 0.168 meanA 0.249 (def) → AFTER 0.308 / 0.157 / 0.293. Compared p1=0 (matches HEAD geometry), p1=1 (visible tilt), held mouse, loud/silent audio, T0=20, p3/p4 at 0 and 1, 576px: all sane, no NaN. First cames version was too thick (blobs) → narrowed.
