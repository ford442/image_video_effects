# NOTES — fork C (sonnet/batch-21): parallax_depth_layers, parallax-glow-compositor

Cards + mechanism interrogation: `BRIEFS-forkC.md` (written before any WGSL edit).
Renders: `forkC/` (3-panel PNG = raw rgb | over-white with alpha | alpha). Tool: `agents/minirender_img.mjs`
with SRC=img (synthetic image + synthetic depth: disc (0.7,0.3) depth≈0.8, disc (0.25,0.7) depth≈0.1–0.15, ramp);
`forkC/mr_flat.mjs` = same with NODEPTH=1 (depth texture all 0 = the app's "no depth model ran" state);
`forkC/r.sh` wrapper. Baselines (HEAD): `baseline/<id>_before.png`.

Both files are first passes (no `Ideas:` at HEAD). Both were the same copy-pasted body; the compositor is the
declared pass 2 of `volumetric-depth-zoom` (`Next Pass:` in that header) so it stays a pass stage.

## RESCUE (not ideas) — what was broken at HEAD

| Defect | parallax_depth_layers | parallax-glow-compositor |
|---|---|---|
| `baseColor` (5-slice composite) never reaches the output → source passthrough | **fixed** (composite is the output) | n/a — loop was dead; **removed** (re-adding it would make pass 2 a second zoom) |
| `chroma = extraBuffer[0]` (bass 0..1 used as a raw uv offset: 0 at silence, full-frame smear at loud bass) | plasmaBuffer[0].x, 0.004 + 0.012·bass | `aberration` slider (default 0.02 = HEAD's fallback), ×(1 + 0.5·bass) |
| edge glow `exp(-k·grad)·depth·2` is brightest on FLAT depth (a warm veil, not an edge) | polarity fixed: `1 - exp(-k·grad)`, scaled to ≤ 0.5; gradient measured on the slice's zoomed sample | polarity fixed, same scale |
| Dead / misrouted sliders | z (Depth of Field) was `* 0.0` → now aperture (Idea 3) | x,y were layer speeds of the discarded loop, w fog density, z never read (it is in `reports/dead_sliders_audit.json`) → now glowRadius / glowIntensity / aberration / bloomThreshold as the JSON names them; fog density fixed at 0.3 (= HEAD at the saved default of the slider that fed it) |
| `clickIntensity = extraBuffer[10]` (FFT bin 5) | kept as the vortex drive, plus held pointer (`zoom_config.w`·0.6) | loop removed |
| No bounds guard | had one | **added** |
| `calculateVolumetricAlpha(0.5, …)` constant depth | fed baseDepth + real coverage | fed baseDepth + incoming pass' alpha |

Default-look consequence: HEAD's flat-depth edge-glow bug added ≈ +2·depth of warm light over the whole frame, so HEAD
looked washed-out/warm. After the rescue the saved-default look is the honest picture + (existing) navy depth haze, i.e.
**darker and more contrasted than HEAD at the same sliders** (synthetic stats: compositor meanL 0.72 → 0.29, depth_layers
0.41 → 0.36 incl. a 3× zoom). That is a rescue, not an idea; flag for real-GPU eyeballing. Synthetic depth "near disc"
has a high value (≈0.8), which HEAD's fog treats as far → heavily hazed; depth direction in the real app is unverified.

## parallax_depth_layers

KEPT VERBATIM: 5 slices, layerDepth=i/4, layerSpeed = mix(x,y,z) (x Parallax = near speed, y Layer Density = far speed — roles untouched), zoom = 1+fract(zoom_time·speed)·4 about zoom_center (pointer; idle 0.5,0.5), vortex spin ∝ click/(dist+0.1)·z(1−z), noise flow jitter 0.015·z, ping-pong uv, density exp(−1.5z)·(1+0.5·sampleDepth), baseDepth, warm (1,.8,.6) edge glow, navy fog colour with the fog slider as density, volumetric alpha + reconstruct_normal, writeDepth = baseDepth.
A PACKING: display RGBA (A = writeTexture colour + alpha; C is not read). No B. No tone-map (photo in, photo out — pass 1 / source are display-referred).

| # | Idea | Where | Formula |
|---|---|---|---|
| 1 | Slab occlusion + disocclusion fill: per-slice cover = density·(1+0.5d)·mix(0.35,1,slab), front-to-back `transmittance` | `// ── Idea 1` (≈ l.245) | native (header's long-claimed "alpha-occlusion"), no §12.2 row |
| 2 | Seamless dolly crossfade: two zoom phases half a period apart, weights sin²(πf)/cos² (sum exactly 1) | `// ── Idea 2` (≈ l.197) | native |
| 3 | Rack-focus slice defocus: DoF slider = aperture, focal plane = depth under the cursor, per-slice CoC·3 rotated taps | `// ── Idea 3` (≈ l.210) + `sliceColor()` | native (the file's `dof` feature/slider) |
| 4 | Beer–Lambert aerial perspective: σ = fog·3·(1.25, 1.0, 0.75); green = HEAD's scalar exactly | `// ── Idea 4` (≈ l.269) | §12.2F Beer–Lambert |

Verified (SwiftShader, 192 px unless noted; no NaN in any run, no validation errors):
- before (HEAD, with depth): meanL 0.448 stdL 0.216 meanA 0.436 — picture = passthrough + warm veil.
- after default: meanL 0.363–0.375 stdL 0.09–0.10 meanA 0.485 (3× zoom magnification of a 192 px source ⇒ soft; dof=0 equally soft).
- x=.2,y=.8 (parallax split): several offset silhouette rings at different scales = real layer separation; mouse (.2,.8) / (.8,.2): zoom centre follows the pointer; mouse-down vs up: mean pixel diff 1.0/255 (subtle, HEAD's 0.3 vortex scale); audio 0 vs 0.9: mean diff 0.36/255 (controlled chroma pulse); dof=1 fog=1: very dark navy (expected: HEAD fog law).
- FLAT depth (all 0): clean, sharp near slice dominates, no NaN/blank (meanL 0.48, stdL 0.15).
- 576 px: meanL 0.364 stdL 0.101 (same as 192 ⇒ no resolution-dependent mosaic).
- Known limitation: edge glow samples the depth texture with the non-filtering sampler, so on a hard-edged synthetic depth at 3–5× zoom the glow line is stair-stepped; smooth estimator depth maps should not show it. Cost: ≤ ~55 texture reads/px (phases with weight < 0.02 are skipped, uniform branch).

## parallax-glow-compositor (pass 2)

KEPT VERBATIM: stage role (reads readTexture + readDepthTexture, writes writeTexture + writeDepth only, A/B untouched as at HEAD), depth-scaled chromatic split about the zoom centre, warm depth-edge glow, navy haze exp(−depth·0.3·3), calculateVolumetricAlpha + reconstruct_normal, writeDepth = depth.
A PACKING: display RGBA on writeTexture only (pass stage; matches pass 1's `A packing`). No ACES: pass 1 already ends in `acesToneMap`; a second tone-map would double-compress.

| # | Idea | Where | Formula |
|---|---|---|---|
| 1 | Energy-conserving bloom: soft-knee hue-preserving extract above Bloom Threshold, 8 golden-angle taps over Glow Radius (px = 2 + 3·x), fraction `moved` taken from the core and added around; overdrive past gain 1.8; far pixels scatter more; per-pixel rotation jitter (IGN) so a large radius is grain not stamped discs | `// ── Idea 1` (≈ l.106) | §12.2F energy-conserving bloom |
| 2 | Cauchy dispersion: radial per-channel scale from n=1+B/λ², B = 2.5·aberration, about zoom_center, ×(0.5+depth) | `// ── Idea 2` (≈ l.84) + `cauchyScale()` | §12.2F Cauchy dispersion |
| 3 | Depth-guarded fringe: R/B taps landing on a different depth plane (|Δd| 0.08–0.16) fall back to the centre tap | `// ── Idea 3` (≈ l.97) | native depth-aware filter rule |

Verified: before (HEAD, depth): meanL 0.724 stdL 0.173 meanA 0.478 → after default meanL 0.286 stdL 0.097 meanA 0.535; sliders live (r0 g0 ab0 = no fringe/glow; r6 g3 ab.12 thr.6 strong fringe; r10 g4 ab.2 thr0 + audio .9 = soft bright glow, no discs, no NaN); mouse (.2,.8)/(.8,.2) move the fringe axis; audio 0 vs 0.9: mean pixel diff 0.82/255, max 77 at fringes (bass ×0.5 on aberration, ×0.3 on glow; measured before the IGN-jitter edit); FLAT depth: sharp, bright, fringe + bloom visible (meanL 0.41); 576 px: meanL 0.277 stdL 0.097.

## Files touched
`public/shaders/parallax_depth_layers.wgsl`, `public/shaders/parallax-glow-compositor.wgsl`,
`shader_definitions/artistic/parallax_depth_layers.json` (features += audio-reactive, mouse-driven; params byte-exact),
`shader_definitions/interactive-mouse/parallax-glow-compositor.json` (same two tags; params byte-exact).
Not touched: bindings (prelude include kept), generated lists, ledger, tests, reports. Nothing committed.

## For the coordinator to double-check
- `reports/dead_sliders_audit.json` / baseline still lists compositor `aberration` as dead — it is live now; baseline needs a regenerate (closeout).
- Neither JSON gets `upgraded-rgba` (no ACES by design — see A packing). If the closeout wants the tag, ACES would have to be added; I judged it wrong for these two display-referred stages.
- Default-look darkening vs HEAD (above) and the unverified depth direction (HEAD fog law: larger = farther) need a real-GPU look. Real-GPU QA is external — nothing here is claimed visually correct beyond the SwiftShader renders.
- `ripples[]` unused by both (HEAD's `extraBuffer[10]`-FFT vortex in depth_layers is kept, now plus held pointer).
