# BRIEFS — fork D (sonnet/batch-21): 4d-projection-dream-weavers, tesseract-fold

Written BEFORE any WGSL edit. Source = HEAD of sonnet/batch-21 (prelude already migrated, 06f35ebe).

---------------------------------------------------------------------
## 1. 4d-projection-dream-weavers   (2nd/3rd pass; no Ideas: line yet)

### Diagnosis of HEAD (baseline render: meanL 0.79, stdL 0.012 = flat near-white)
RESCUE list (all verified by reading the file):
1. **Wash / exposure.** Three noise terms are summed unnormalised (`n + 0.5·detail·n2 + 0.25·detail·n3`, detail ≈ 1.1–1.5 so the sum has mean ≈ 1.0, range 0–1.9). `temporal*0.6+0.4` then lies ≥ 1 almost everywhere, `mix(navy, cream, t)` EXTRAPOLATES past cream, then ×1.1 into ACES → the picture sits on the ACES shoulder (0.8 ± 0.01). Fix = normalise by the total octave amplitude so the field is 0..1 again and the navy→cream gradient is actually traversed.
2. **"4D" noise ignores w.** `hash13(i.xyz)` — the 4th lattice coordinate never enters the hash, `u.w` is unused, so the mouse-x ("w") slice does nothing and the field is a 3-D noise. Fix = real 4-D lattice (two 3-D lattices at floor(w), floor(w)+1, blended by smoothstep(fract(w))).
3. **Dead spring navigation.** `dt = u.config.y` is the CLICK COUNT (not dt), and the state lives in `extraBuffer[133..136]`, which the engine re-zeroes every frame (and thread (0,0) races the readers) → z,w ≈ 0 forever, mouse does nothing. Fix = A-texel state scheme (texel (0,0) = spring pos/vel, texel (1,0) = `(fract(lastTime),0,0,0.7371)` sentinel), every thread integrates the same step, dt from `fract(time)` differences (A is rgba16float on balanced/battery tiers).
4. **Filtering sampler on rgba32float history** (`textureSampleLevel(dataTextureC, u_sampler …)`) → exact `textureLoad` with manual bilinear.
5. **Colour/field mix-up in the trail.** `mix(fractal_col /*noise*/, prev /*finished colour*/ …)`. Trail now operates in colour space (A = HDR pre-ACES colour, which is how C is read).

### Idea Card
```
SHADER: 4d-projection-dream-weavers
IDENTITY: a dreamy slice of 4-D value noise (navy→cream, per-channel chromatic offsets in 4-space), worley dream-dust, soft persistence trails; mouse steers two extra dimensions (z,w).
KEEP VERBATIM: 4 params + roles (scale / speed / detail-amplitude of octaves 2,3 / mouseSensitivity → z,w range + spring stiffness); 3 chromatic 4D offsets (bass on R, treble on B); navy→cream mix; cosine-palette dimension tint at 0.25; worley dust (F1^24, depth-fade, treble gain); ACES(×1.1) on display; depth out = depthField.
ADD:
  1. Hyper-rotation of the sampling slice — the 4-D point (c·scale, z, w) is rotated in the XW and YW planes (angles ride time·speed) before the existing noise taps and the dust, so the slice tilts through the 4th dimension and patterns MORPH instead of sliding diagonally. Dust shares the rotated coordinates (it was an unrelated overlay before).
  2. Perspective divide 1/(D − w′) of the rotated point (the "projection" in the name): regions swung toward the viewer in w swell, away shrink; w′ also fogs the far side toward the navy end (w-depth as colour/fog).
  3. Rotation-velocity trail advection — the apparent 2-D velocity of a pattern under the XW/YW rotation is (ωa·w1, ωb·w2); the trail reads C at uv − v·len (exact manual bilinear) so dream ghosts follow the field's own motion instead of smearing in place.
FORBID: springs-as-overlay, click ripples, IQ palette swap, scanlines, new params, changing the navy/cream endpoints, raymarching.
A PACKING: HDR linear colour (pre-ACES) as before; texels (0,0)/(1,0) are spring-state/sentinel (documented; trail loads skip them).
```

### §12.1 interrogation
- Tactic 1 (deepen kernel): noise4D is a lattice that ignores w → make it a true 4-D lattice; the next-better approximation of "slice of 4-D noise" is a *rotated* slice, not a translated one.
- Tactic 2 (physics one step further): a real 4-D object seen in 3-/2-space is *rotated in planes that include w* and *perspective-divided* by (D−w); both produce the signature "inside-out breathing".
- Tactic 3 (promote an intermediate): `w′` (rotated w) is the new intermediate; it feeds both the perspective factor and the fog. `depthField` already thrown to the depth texture stays.
- Tactic 6 (history): C is read as colour; the one extra piece of continuity it affords without repacking is *advected* reading (semi-Lagrangian), using the velocity implied by the rotation.

### Formula admission (§12.4)
- Hyper-rotation (XW/YW Givens) — native to "4D", consumes `p4`; no new state. **Not a §12.2 row** (4D-specific).
- 4-D perspective divide `s = D/(D−w′)` — native to "projection"; consumes `w′`. Not a §12.2 row.
- Trail advection — the §12.2C "semi-Lagrangian smudge" expression `C(uv − v·dt)` with v from the rotation (not the pointer); consumes history the file already reads. Deletion test: remove → same dream noise, trails smear in place (additive). Keep-only-idea → not recognisable. Uses 1 of the 2 allowed batch slots for that row.

---------------------------------------------------------------------
## 2. tesseract-fold   (first pass; image/geometric; reads the photo)

### Diagnosis of HEAD
Baseline is healthy (mandala of glass facets). Observations:
- "4D-style rotation" is `rot2(a2)*rot2(a1)` — two 2-D rotations about the same axis = one 2-D rotation. No fourth dimension; `4D Rotation Speed` just spins the picture.
- The 3-pass `abs / translate / rotate` fold is a KIFS; nothing keeps what it computed (fold count, closest approach to the crease) — it only feeds `sampleUv`.
- A not written (no history read, so harmless); depth passthrough OK; ACES on display OK; early-exit branch OK.

### Idea Card
```
SHADER: tesseract-fold
IDENTITY: the photo seen through a neon stained-glass kaleidoscope — mouse-centred polar fold + 3-step KIFS fold, radial chroma split, iridescent grade, lead cames, edge glow, vignette.
KEEP VERBATIM: 4 params + roles (4D Rotation Speed → spin/segments/fold count; Projection Scale → scale + cell density; Edge Glow Width → fold offset/vignette/glow; Face Opacity → glass tint + alpha); `R = rot2(a2)*rot2(a1)` spin; held shear + click shells; kaleido segs; abs/translate/rotate loop; sampleUv from the folded p; chroma split; iridescent `grade`; square-grid lead + innerWave; vignette; neonGlow; ACES + gamma; depth passthrough; early-exit.
ADD:
  1. True 4-D double rotation + perspective divide — lift p to (p.x, p.y, zc, wc), rotate in XW and YW (rate = the existing 4D Rotation Speed), project by D/(D−w′). The mandala now tilts into the fourth dimension: cells nearest in w swell, far cells shrink, the way a hypercube's cell-in-cell structure breathes. Applies to `p` right after `R`, before the kaleido fold.
  2. Crease-trap lead came (orbit trap to the fold axis, §12.2E) — inside the existing 3-iteration fold loop keep `trap = min(trap, min(|p.x|,|p.y|))` (distance to the mirror crease at each fold); darken/glint the lead where the glass was actually folded, so the cames follow the mirror seams of the kaleidoscope instead of only a fixed square grid.
  3. Fold-count as glass material (§12.2E) — count the reflections per pixel (p.x<0, p.y<0 each fold); odd/even parity and depth drive pane thickness: Beer–Lambert-style absorption `exp(-folds·k)` toward the pane's own glass colour. Deeper-folded panes read as thicker, more saturated glass.
FORBID: springs, extra click systems, ripple shockwaves beyond the existing `clickShell`, IQ palette as the look, raymarching, changing the params, scanlines.
A PACKING: display RGBA (post-ACES, gamma) — A now also written with the final display colour (no history is read, so no packing conflict).
```

### §12.1 interrogation
- Tactic 1: the 2-plane rotation is the *degenerate* 4-D rotation (both planes share an axis) → the next-better operator is XW+YW (double rotation), which is non-degenerate and has a w component to project.
- Tactic 2: a hypercube projected from 4-space is perspective-divided by (D−w); that is the physical first-order effect that makes the tesseract look like a tesseract.
- Tactic 3: the fold loop already computes `p` at every crease and throws away how many reflections happened and how close the point came to the crease → promote both.
- Tactic 6: shader owns no history (reads none) → not used; A written as plain display colour only.

### Formula admission
- 4-D double rotation + perspective — native to the file's name/param ("4D Rotation Speed"); consumes `p`; no state. Not a §12.2 row.
- Orbit trap (§12.2E row "Orbit trap") — family match: the abs/translate/rotate loop IS a KIFS; consumes `p` in the loop; deletion test passes both ways.
- Fold count as material (§12.2E row) — same loop; consumes the same branch masks.
- Batch note for the coordinator: this is the only file in my pair that uses either E row; 4d uses neither.
