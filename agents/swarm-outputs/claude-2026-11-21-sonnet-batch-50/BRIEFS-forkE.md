# BRIEFS — fork E (sonnet/batch-50): gen-radiant-cyber-plasma-astro-griffin, gen-inverse-mandelbrot

Written BEFORE any WGSL edit. HEAD = worktree file after the coordinator's prelude migration (copies in scratch: `griffin_head.wgsl`, `mandel_head.wgsl`).

## What HEAD actually draws (measured, not assumed)

### gen-radiant-cyber-plasma-astro-griffin — NOT a griffin
Render at 320 px (`g_head_t2.png`): an infinite perspective lattice of striped slabs receding to a horizon, a small golden head/beak at the bottom of frame, and a blurry blue rift. Causes found in the code:

1. **Unbounded domain repetition in `wingFeathers`.** `q.x = (fract(q.x*2)-0.5)/2; q.z = (fract(q.z*2)-0.5)/2` repeats the feather cell forever in x AND z; the cell box is `(width*slot, 0.02, spanLen*slot)` with `spanLen*slot ≈ 0.63 > 0.25` (cell half-size), so in z the box fills the whole cell → continuous z-stripes with x-gaps, forever. The "wing" is an infinite floor sheet; `wing_span` only changes stripe width, never a wing length. The "primary-feather slot" idea is only visible as gaps along x.
2. **`uv.y` is not flipped** (`(id.xy - 0.5*res)/res.y`, y = 0 at the top) while the scene is authored y-up (head at +0.45 above the body) → the griffin is drawn upside-down.
3. **Camera is behind the griffin.** `ro=(0,0,3)`, `rd=(uv,-1)`; the head and beak are at −z, so the camera sees the griffin's rear; the shipped "beak shear glint" (`dot(n,(0,-0.15,-1))`, needs the beak normal facing −z) can never be seen: back-facing surfaces are not hit.
4. **Pointer mapping offsets the griffin at rest.** `anomaly_pos = (mouse.x*2, mouse.y*2, 0)` with `p_warp = p - anomaly_pos` for EVERYTHING (the whole creature is translated onto the pointer) — at the default pointer (0.5,0.5) the griffin sits at (1,1,0), off-axis; mouse y also has y-down sense.

Rescues R1–R4 are therefore: bound the wing to a finite fan of primaries; flip uv.y; view the griffin from the front-three-quarter side; centre the pointer-follow (pointer 0.5,0.5 ⇒ centred) in screen space. The default look WILL change loudly (HEAD cannot be recognised as a griffin).

### gen-inverse-mandelbrot — healthy
Reads as a Mandelbrot set in a pastel candy palette (interior pink cardioid with radial pattern, green ridged exterior). No NaN under stress (high iters, deep zoom, bass 3): `dz` overflow in `escapeNormal` is only latent. Not a rescue. One latent: `dwellBand` uses `smoothstep(0.6, 0.4, band)` (reversed edges; implementation-defined/undefined in WGSL, works on Dawn/SwiftShader) → replace by the equal-valued `s*(1-s)` form (Hermite symmetry) — hygiene, no `Upgraded` claim on that. JSON has `params: []`; real slider roles/defaults live in `x-meta.upgrade.params` (0.4 / 0.3 / 0 / 0.3) and all four `zoom_params` are read (grep: maxIter ← x, colorZoom ← y, cmapRot ← z, bailout ← w).

---

## Idea Card — gen-radiant-cyber-plasma-astro-griffin

```
SHADER: gen-radiant-cyber-plasma-astro-griffin
IDENTITY: a faceted chrono-prism griffin (eagle head + golden beak, ellipsoid body, flapping slotted
  wings) raymarched in a violet rift, with cyan/magenta tri-grid seams, plasma rim and wingtip glow.
KEEP VERBATIM: params (warp_intensity → mouse-anomaly twist, wing_span → feather width/length,
  fractal_depth → facet displacement + seam density, plasma_glow → plasma gain); 3-point lighting rig;
  facet-quantised normals; triGridEdge seams; golden head; primary-feather slots (slot = 0.74 at rest);
  beak shear glint; flap ghost (reads exact C); rift background; ACES+gamma display; A = display RGBA;
  semantic alpha; depth out; body/head SDF; smin blends.
RESCUES (HEAD defects, not ideas): R1 bounded feather fan (finite wing, 5 primaries/wing, mild
  length taper); R2 uv.y flipped; R3 front-three-quarter camera (beak toward viewer; beak glint
  reachable); R4 pointer-follow centred at the default pointer (screen-space mapping).
ADD (3 native ideas):
  1. Wing-flap kinematics — flexion wave (tip lags the root: sin(t − 0.45·|x|)) + upstroke slot
     opening (slot 0.74 → 0.56 and each primary supinates about its own long axis on the upstroke).
     Why here: it is what the slotted primaries are FOR; a rigid hinge flap with static slots is not
     how a wing moves. Deepens the existing "primary-feather slots" mechanism, no new motif.
  2. Rachis + barb vane with plasma flow along the shaft — shading in feather-local coordinates:
     bright rachis ridge, chevron barb albedo, plasma pulses travelling root→tip along each shaft
     (rides the existing wingtip plasma tint and `plasma_glow`; bass lifts the pulse).
  3. Step-count AO (§12.2E, owned) — 5 taps of the file's own `map()` along the normal; darkens the
     feather slots, the wing/body seam and the head/neck crease so the slot gaps read as depth.
FORBID: springs/extraBuffer state, ripple fronts, IQ palettes, fracturing the creature into a new
  motif, any new param, any change to the seam/colour constants.
A PACKING: ACES+gamma display RGBA in A (unchanged); C is read as display colour by the flap ghost.
```

### §12.1 mechanism interrogation (griffin)
- **Tactic 1 (deepen the kernel):** the wing SDF is a repeated slab. Next-better approximation of the *same* operator: bounded (limited) repetition with a per-feather rigid transform — exact SDF is preserved (clamped cell index + rotation about the cell centre).
- **Tactic 2 (physics one step further):** a bird wing's tip lags its root (travelling flexion wave) and slotted primaries separate/supinate on the upstroke, close on the downstroke; each feather has a rachis shaft with barbs raking back from it.
- **Tactic 3 (promote an intermediate):** `wingFeathers` already computes feather-local `q` and a per-feather hash (`hit.z`, used only as a tint phase); `map()` itself is the quantity AO needs. Re-deriving `q` at the hit (same transform helpers) promotes it to shading with no new state.
- **Tactic 6 (history the shader owns):** C is read as display colour for the flap ghost. Nothing extra is added; the ghost's shift sign is flipped with the y-flip so it still trails opposite to the wing motion (verbatim behaviour, same visual relation).

### §12.4 formula admission (griffin)
- Step-count AO: in the Generative/SDF table; consumes `map()`; deletion test passes both ways (the griffin without AO is still this griffin; AO without the griffin is nothing). Owned by this file (shared with the serpent only).
- Ideas 1 and 2 are not §12.2 rows (domain-native: avian wing kinematics; feather rachis/barb anatomy) — no ownership needed.
- Deletion test, ideas 1/2: without them the wing is still HEAD's slotted wing; the ideas do not replace the SDF/lighting rig.

---

## Idea Card — gen-inverse-mandelbrot

```
SHADER: gen-inverse-mandelbrot
IDENTITY: the Mandelbrot map iterated on a colour-space vector (z0 = RGB-like noise, c = position):
  an alien, pastel, iridescent fractal field with orbit-trap hue, Julia probe, dwell bands, escape
  normal shading, Pickover stalks and arg(final_z) bands.
KEEP VERBATIM: the 4 params (Iterations / ColorZoom / CmapRotate / BailoutRadius), z0 from noise, c
  from position+pan, smooth escape count, orbit-min hue, Julia probe, dwell bands, escapeNormal
  shading direction (output unchanged), fbm interior, ripple tint, stalks + arg bands, C feedback mix
  0.92, A = raw pre-ACES HDR + ACES on writeTexture only, alpha/depth formulas.
ADD (2 native ideas):
  1. Exterior distance estimate → filament glow. `escapeNormal` already iterates dz = 2·z·dz + 1 and
     throws |dz| away after normalising (tactic 3). Return |dz| as well; DE = ½·|z|·ln|z| / |dz| in c
     units, divided by the pixel footprint (2.5/colorZoom/res.y) → an exp(−DE/px) filament light along
     the set boundary that thin hairlines (which otherwise alias away under the 0.36 temporal mix)
     keep. Tint: hue complement of the file's own hue1.
  2. Interior colour-space Lyapunov rings. The colour orbit's sensitivity to its initial colour,
     mean ln|2z| per iteration (accumulated in the existing loop, reusing the `length(z)` it already
     computes), is the log multiplier of the attracting cycle: its level curves are the nested rings
     around every hyperbolic component centre (Douady–Hubbard coordinates). The flat pink interior
     gets contour rings that make the bulbs readable; breathes with the bass-driven iteration count.
FORBID: springs, ripple overlays beyond what exists, a new palette, replacing the escape-time look,
  any new param, touching the stalk/arg-band constants.
A PACKING: raw HDR pre-ACES col in A (unchanged; C is read back as colour history). ACES on writeTexture.
```

### §12.1 mechanism interrogation (mandelbrot)
- **Tactic 1:** the escape coloring is smooth-count + point trap. Next-better *information* from the same orbit: derivative-based distance estimate (exterior) and multiplier (interior).
- **Tactic 2:** the real object has a boundary at which thin filaments exist at sub-pixel width, and an interior composed of hyperbolic components with attracting cycles; neither is shown (the interior is a flat pink fill; filaments alias).
- **Tactic 3:** `dz` and `length(z)` are computed and thrown away — promote them.
- **Tactic 6:** C is colour history at 0.92: the filament light is added before the mix, so the mix thickens it, not smears it.

### §12.4 formula admission (mandelbrot)
- The owned §12.2 rows are Orbit trap and Smooth iteration count. **HEAD already has both** (orbit_min point trap + Pickover stalk trap; `n + 1 − log2(log2|z|)` is continuous for any bailout), so extending them would duplicate. The two ideas above are domain-native Mandelbrot structure (distance estimator, multiplier contours), not table rows — no ownership needed, no row used.
- Both consume quantities the file already had; deletion test passes both ways; cost: Lyapunov adds one `log2` per main-loop iteration; DE adds nothing to loop cost (rides escapeNormal's existing loop).
