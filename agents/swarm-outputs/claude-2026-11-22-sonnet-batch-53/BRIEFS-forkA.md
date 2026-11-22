# BRIEFS — fork A (parallax_depth_layers, volumetric-depth-zoom) — written BEFORE any WGSL edit

HEAD = worktree file at start (copies in scratch `a/*_head.wgsl`). Both are 2nd+ passes: every item on the existing `Ideas:` line is KEEP VERBATIM. No §12.2 formula rows are used on either file (all four ideas are domain-native mechanisms, so no row ownership is touched).

## Verified HEAD defects (evidence in NOTES-forkA.md)

**volumetric-depth-zoom** (all three verified by rendering HEAD / rescue-only copies):
- R1 — the eight engine-slot reads. Header says `extraBuffer[0..7]` = light/ambient/normal/dof/cameraZ/fov/near/far. Engine map: `[0..2]` = bass/mid/treble, `[3]` reserved 0, `[4]` = historyHead (u32 bits as f32 ≈ 0), `[5..]` FFT. So with silence ambient = 0 and light = 0 → lit colour = 0 → **the picture is gone** (HEAD meanL 0.084: fog colour + the clock-ring overlay only), `fog_falloff = 0` → `pow(d,0)=1` → flat 55 % fog, `dof_amount = 0`, `cameraZ ≈ 0`, normal_strength = treble. The author's own fallbacks (used when the buffer is short) are the intended values: normal 1.0, falloff 1.0, dof 1.0, light 1.0, ambient 0.2 → named constants. Rescue-only render (`vdz_r1`) restores the photo (meanL 0.65).
- R2 — edge-specular gradient measured against the wrong depth. `depth_grad = |D(uv+px) − final_depth|` where `final_depth` is the *zoomed, focus-weighted slice blend* and the other tap is the *unzoomed* map: the "edge" term is true wherever the two differ by > 0.1, i.e. whole discs/regions, not edges (`vdz_dbg_spec.png`: solid white blobs, not lines). Fix: central differences of the unzoomed map taken from `reconstruct_normal`'s own four taps (two taps fewer than HEAD).
- R3 — `mousePos = zoom_config.yz / resolution` — `yz` is already a 0..1 uv, so mousePos ≈ 0 and with `cameraZ ≈ 0` the saved **Parallax** slider was dead. Fix: use `zoom_center` directly and a literal reach constant (HEAD's effective cameraZ was 0, so perspective stays 1 — framing unchanged).
- R4 — `focal_depth = fract(zoom_time * fg_speed)` snaps from 1 to 0 once per period (1 s at the saved default 1.0): DOF weights and the focal sheet pop at every wrap. Fix: `ping_pong(zoom_time * fg_speed)` — same sweep speed, no snap (period doubles). Hoisted out of the loop (HEAD recomputed it per slice).
- Also: `let bass` declared and never used while the JSON claims `audio-reactive` (the only "audio" was bass accidentally arriving as `extraBuffer[0]` = light strength). Now light strength = 1 + 0.6·`plasmaBuffer[0].x` on purpose.
- NOT touched (flagged for the user): the `clockRings` + `clickFront` spectral overlay (generic stamp: concentric rings on every pixel and click rings). It is old (not on the `Ideas:` line), it is what dominated HEAD's dark frame, and removing it is a look decision.

**parallax_depth_layers** (checked, nothing broken in plumbing): no ACES on output that the additive edge glow pushes past 1 (floor item); `extraBuffer[10]` read is a documented FFT-bin spin drive (kept); A write is display RGBA that nothing reads back (C not read) — stays, stated; params saved roles unchanged; no extraBuffer writes. HEAD pointer behaviour: the pointer is only the dolly vanishing point + focus-pick; slices are not depth-sheared by it (the zoom phases are per-slice phase, not depth-ordered). That is the gap Idea 1 fills.

---

SHADER: parallax_depth_layers
IDENTITY (one sentence): five depth slices dollying through a photo with slab occlusion/disocclusion fill, rack-focus defocus under the cursor, Beer-Lambert navy haze.
KEEP VERBATIM: slider roles (x Parallax = near slice speed, y Layer Density = far slice speed, z Depth of Field = aperture, w Fog = density), 5-slice front-to-back `transmittance`/`cover` composite, two-phase sin²/cos² dolly crossfade, `sliceColor` 3-tap rotated gather (taps, rotation per slice, k blend), focus depth read at the pointer, Beer-Lambert per-channel sigma, `calculateVolumetricAlpha`, extraBuffer[10] FFT spin + 0.6·mouseDown, bass chroma, vortex + noise flow jitter, depth write, A = display RGBA.
ADD:
  1. **Multiplane head-parallax shear** — the pointer is the viewer's head: each slice's sample position shifts by `-(ptr-0.5)·K·(layerDepth − focusDepth)` (screen-space-constant: added to `flowUV`, before the zoom divide). Near slices slide against the cursor, far slices with it, and the slice at the focus plane stays registered — a real multiplane rig, and it feeds the existing slab-occlusion/disocclusion fill (the gaps the shear opens are filled by farther slices). This file is *called* parallax layers; at HEAD the pointer did not shear the stack.
  2. **Head-lamp contact shadow** — (REVISED after a render test, see note) the cursor is also the lamp: a pixel whose sampled depth is farther than the map one step *toward the cursor* sits in the shadow of that nearer slab, so each slab shades the farther slice radially away from the cursor (`smoothstep(0.05,0.22, gC − gO)`, ×0.55 on the slice colour). A multiplane stack of cut-outs casts shadows on the planes behind it; the slice depths and the pointer are already in the file. One extra depth tap per slice, offset divided by the slice zoom.
  (Original idea 2 was a highlight-weighted bokeh gather. Dropped: with the `DOTS=1` bright-point source the 3-tap gather turns each highlight into three discrete bright ghost dots instead of a disc, i.e. weighting amplifies HEAD's undersampling. Not shipped.)
  (Floor, not ideas: display ACES on the colour that edge glow pushes past 1; clamp before ACES.)
FORBID on this file: springs/ripples (none native), a CoC/bokeh rewrite of the 3-tap gather, a second chromatic scheme (HEAD's R/B split already exists), more fog math (Beer-Lambert is shipped), any extra zoom/dolly layer.
A PACKING: display RGBA (A = writeTexture colour + volumetric alpha; C is not read) — unchanged; A now holds the post-ACES colour so it stays identical to the presented picture.

§12.1 interrogation:
 1. Kernel: slice sampler = 3 equal taps; next-better approximation of a defocus disc = energy weighting by scene radiance (idea 2).
 2. Physics: the multiplane camera's first-order side effect is relative shift of planes under viewpoint motion (idea 1) and shadows cast between planes (idea 2).
 3. Promoted intermediates: `focusDepth` (already sampled at the pointer) doubles as the shear pivot; `gC` (the slice's own depth sample, fetched for the edge gradient) is the receiver depth for the contact shadow.
 6. History: C not read, A unread — no continuity idea is native here (a hysteresis on a still photo is not parallax).
§12.4 admission: neither idea is a §12.2 row. Operates-on-what-exists: yes (pointer, focusDepth, slice depth taps). Deletion test: delete idea → still the same parallax stack; delete the original dolly/occlusion and keep only the idea → shear of a photo, not this effect.

---

SHADER: volumetric-depth-zoom
IDENTITY: five depth slices of a photo zoomed 1×–5× about the pointer, focus-weighted into a volume with fog, an orbiting light's relief shading and edge specular; foreground/background slices drift at their saved speeds and a pale sheet marks the swept focal plane.
KEEP VERBATIM: slider roles (fg_speed, bg_speed, parallax_str, fog_density), 5-slice loop with `sample_layer` zoom `1+depth*4`, ping-pong wrap, `dof_factor`/`density` weights, Idea 1 slice drift (`mix(fg,bg,depth)` speeds), Idea 2 focal sheet (`exp(-|slice-focal|*36)`·0.12 tint), `reconstruct_normal` cross-product relief, orbiting light, `calculate_fog` + `calculateAdvancedAlpha`, ACES, depth write (blended depth), the `clockRings` / `clickFront` overlay (kept, flagged).
ADD:
  1. **Light-facing rim glint** — the edge specular is isotropic (depth-gradient magnitude only), but a real rim highlight lights only the silhouette that *faces the light*. Gate the existing edge term by `dot(normal.xŷ, light.xŷ)` (floor 0.1) so the glint travels around each silhouette as the light orbits. Uses the gradient/normal the file already computes.
  2. **Focal-plane iso-depth contour** — the pale sheet is a flat per-slice tint; where the swept focal plane actually *cuts the scene* (|sampled depth − focal| ≈ 0) the sheet should become a thin lit contour. Promotes the `|depth − focal_depth|` that `dof_factor` already computes: `exp(-(|d−f|·20)²)` added per slice (weighted by that slice's weight) in the sheet's tint — a laser-scan line tracing the scene at the focal depth.
  (Rescues R1–R4 above are the floor.)
FORBID: HG / Beer-Lambert (shipped elsewhere in the batch), circle-of-confusion blur (that is parallax_depth_layers' idea), more overlay rings, new springs, a camera dolly (cameraZ stays effectively 0 so the framing is HEAD's real-engine framing).
A PACKING: display RGBA on writeTexture only (unchanged); depth = blended slice depth.

§12.1: 1. kernel — relief shading `dot(n,l)` is already a shading model; add the missing directionality on the specular. 2. physics — rim light faces the source. 3. promoted intermediates — `depth_grad`/normal xy (direction was thrown away), `|depth−focal_depth|` (computed per slice, only used as a weight). 6. no history owned.
§12.4: neither idea is a §12.2 row; both consume quantities the file already computes; deletion test passes in both directions.
