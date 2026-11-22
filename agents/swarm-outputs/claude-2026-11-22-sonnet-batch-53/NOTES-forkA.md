# NOTES — fork A (parallax_depth_layers, volumetric-depth-zoom)

Renders: 256 px, 40 frames, tEnd 4 s, saved JSON defaults, mouse 0.5,0.5, audio 0.3,0.2,0.1, `SRC=img` (synthetic photo + depth: two discs + ramp). Scratch: `/tmp/claude-0/-root-image-video-effects/0808efa3-e4d2-4c02-b58e-093c2450d257/scratchpad/a/` (`sheet_vdz1/2.png`, `sheet_vdz_abl.png`, `sheet_vdz_rim2.png`, `sheet_vdz_i4.png`, `sheet_pdl_*.png`, `sheet_final_a.png`). No visual QA on a real GPU claimed.

## volumetric-depth-zoom

**Idea Card ADD (both in the diff, `// Idea 3` / `// Idea 4` comments + `Ideas:` line):**
- Idea 3 — light-facing rim glint: edge specular gated by `smoothstep(0.2,0.85, dot(normal.xy, light.xy)/(|n||l|))`, floor 0.04. Debug render (`vdz_rim_*.png`, spec only, 4 light angles) shows a crescent that travels round each disc as the light orbits.
- Idea 4 — focal-plane iso-depth contour: per slice `exp(-(26·|depth − focal|)²)·0.22` in the focal-sheet tint. Ablation diffs (`sheet_vdz_i4.png`) show the lit band following the depth level currently in focus (a disc at depth ≈ focal lights whole; a ramp lights a band).
KEEP VERBATIM held: slider roles, 5-slice loop and zoom `1+depth*4`, slice drift (Idea 1), focal sheet (Idea 2, same 0.12 tint), `reconstruct_normal` cross-product relief, orbiting light, fog + advanced alpha, ACES, `clockRings`/`clickFront` overlay, depth write.
A PACKING: display RGBA on writeTexture only; no A/B write; C not read.

**Rescues (all verified on HEAD / rescue-only copies, they change the default picture):**
1. **Engine slots read as parameters.** HEAD read `extraBuffer[0..4]` as light/ambient/normal/dof/cameraZ; engine map is bass/mid/treble/reserved/historyHead. Harness leaves [0..132] = 0 (= silent engine): ambient 0 + light 0 → lit colour 0 → HEAD is a black frame with only fog + rings (meanL 0.084, stdL 0.024). Replaced by the author's own fallback constants (normal 1, falloff 1, DOF 1, light 1, ambient 0.2); rescue-only copy (`vdz_r1.png`) returns the photo (meanL 0.65). Light strength now `1 + 0.6·plasmaBuffer[0].x` on purpose (`bass` was declared and unused; `audio-reactive` was only true by accident).
2. **Edge specular was a region fill, not an edge.** `|D_unzoomed(uv+px) − final_depth|` compares the unzoomed map with the zoomed blend: `vdz_dbg_spec.png` shows solid white discs and half the frame. Now central differences from `reconstruct_normal`'s own four taps (two taps fewer), clamped ≤1.5 → thin lines.
3. **Parallax slider dead.** `mousePos = zoom_config.yz / resolution` (already a uv → ≈0) times `cameraZ` (historyHead bits ≈ 0). Now `(zoom_center − 0.5)·parallax_str·0.2`; `CAMERA_Z` stays 0 so framing/perspective is HEAD's real-engine value.
4. **Focal sweep snap.** `fract(zoom_time·fg_speed)` jumped 1→0 every 1/fg_speed s (DOF weights + sheet pop). `ping_pong(zoom_time·fg_speed)`: same sweep speed, no snap (period doubles).
5. `pow(depth, …)` base guarded with `max(depth,0)`.
**NOT changed (open call):** the `clockRings` + `clickFront` spectral overlay (IQ-cosine rings on every pixel, treble/mids-driven). It is the generic stamp the contract forbids, it is old (not on any `Ideas:` line) and it is the only visible thing in HEAD's black frame; with the photo restored it reads as concentric tinted rings over the picture. Removing it is a look call for the user.

Diff vs HEAD at defaults: 100 % of pixels >4/255, 97.8 % >16/255 (HEAD was black). meanL 0.084 → 0.536, stdL 0.024 → 0.132, meanA 0.502 → 0.406. NaN 0 over a 4-config extreme matrix + no-source.
Timing (`mr_ab` 256 px, 8 cycles, box load 16–27 from other forks): paired median **1.08×** (min ratio 0.69; fewer taps than HEAD).
Gates: precommit 2/2 (extraBuffer violations 0, pasted headers 0), naga-wasm 2/2, dead-sliders 0 new (2 defs scanned; all four sliders read by hand), audit_extrabuffer pass. `extraBuffer` references left in WGSL: comments only.

## parallax_depth_layers

**Idea Card ADD (`// Idea 5` / `// Idea 6` comments + `Ideas:` line):**
- Idea 5 — multiplane head-parallax shear: `flowUV += −(zoom_center−0.5)·0.12·(layerDepth − focusDepth)` before the zoom divide (screen-space-constant). Near slices slide against the cursor, far with it, focus-plane slice registered; the gaps feed the existing disocclusion fill. Ablation (`sheet_pdl_new.png`): with the pointer off-centre the outlines move by several px per slice; pointer at 0.5,0.5 = no shear.
- Idea 6 — head-lamp contact shadow: `smoothstep(0.05,0.22, gC − gO)` where `gO` is the slice's depth map one step (0.018/zoom uv) toward the cursor; ×0.55 on the slice colour. One extra depth tap per slice. Ablation (`sheet_pdl_shadow.png`): a thin darkened band on the far side of each silhouette, on the side away from the cursor, ~4.6 px at 256 (≈18 px at the 1024 working size). Subtle at 256 on this soft synthetic image.
- (Dropped after a render test: highlight-weighted bokeh gather — with the bright-point source the 3-tap gather turned highlights into three bright ghost dots; see BRIEFS.)
KEEP VERBATIM held: slider roles, 5-slice transmittance/cover composite, two-phase dolly crossfade, `sliceColor` taps/rotation/k blend, focus depth at pointer, Beer-Lambert sigma, `calculateVolumetricAlpha`, extraBuffer[10] FFT spin + mouseDown, bass chroma, vortex + noise jitter, depth write.
A PACKING: display RGBA; A mirrors the presented (now ACES-mapped) colour; C not read, so A is a mirror only (stated, kept).

**Floor / rescue:** display ACES added (clamp ≥0 first); the additive edge glow could exceed 1 and nothing tone-mapped it. `upgraded-rgba` added to JSON features (ACES present + ideas implemented). **This changes the default picture on every pixel**: meanL 0.365 → 0.491, stdL 0.102 → 0.111, 99.2 % of px >4/255 (the catalog ACES fit lifts shadows/midtones of an LDR photo). Open call: if the user wants the photo tonality kept, replace it by a highlight-only shoulder. No other HEAD defects found: `extraBuffer[10]` is a read of FFT bin 5 (legal, documented, kept); no writes to [0..132]; sliders all live; A write is a dead mirror (C unread) but harmless.
Diff vs HEAD at defaults is ACES-dominated; ideas are small at rest (pointer 0.5,0.5 → no shear). Timing: paired median **0.71–0.93×** (noise; no added tap cost beyond one depth tap/slice). NaN 0 over the 4-config matrix + no-source. Gates: precommit 2/2, naga-wasm 2/2, dead-sliders 0 new, extraBuffer pass.

## JSON
- `volumetric-depth-zoom.json`: description appended (contour, rim glint, bass pumps the light). Params/features untouched (`audio-reactive` is now true on purpose).
- `parallax_depth_layers.json`: description appended; `upgraded-rgba` added to features. Params and `x-meta.upgrade.params` byte-exact.
