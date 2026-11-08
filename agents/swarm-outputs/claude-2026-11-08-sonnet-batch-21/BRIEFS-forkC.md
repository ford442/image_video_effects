# BRIEFS — fork C (sonnet/batch-21): parallax_depth_layers, parallax-glow-compositor

Written BEFORE any WGSL edit. Both are FIRST passes (no `Ideas:` line). Both are the same
copy-pasted body at HEAD (parallax-glow-compositor is parallax_depth_layers minus the bounds
guard and the `dof` read).

## Facts found at HEAD (verified by reading + baseline render)

* `baseColor` (the 5-layer accumulated colour) is **never used** — output = readTexture at `uv`
  (chroma split) + edge glow + fog. Both shaders render as a source-image passthrough with a
  warm tint. The layer stack that is the whole identity of the effect never reaches the picture.
* `chroma = extraBuffer[0]` — that slot is **bass 0..1**, used as a raw uv offset × depth:
  0 at silence (no aberration), up to a full-frame smear at loud bass. Audio belongs in
  `plasmaBuffer[0].x`; offset needs a sane scale.
* `edgeGlow = exp(-depthGrad*30) * baseDepth * 2` peaks where the gradient is **zero** (flat
  areas) — inverted polarity, it is a flat-depth tint not an edge glow.
* `clickIntensity = extraBuffer[10]` — that is FFT bin 5, not a click.
* parallax_depth_layers: `dof = zoom_params.z` is "consumed" as `* 0.0` — dead slider.
* parallax-glow-compositor JSON names the sliders `glowRadius / glowIntensity / aberration /
  bloomThreshold` but the shader reads x,y as layer speeds, w as fog density and never reads z
  (`aberration` is in `reports/dead_sliders_audit.json`). It is declared "Pass 2" of
  `volumetric-depth-zoom` (that file's header says `Next Pass: parallax-glow-compositor.wgsl`).
  So it is a genuine **pass stage**: it reads the previous pass' image + depth. Therefore:
  do NOT start writing A/B on it (single-writer display on writeTexture, same as pass 1's
  `A packing: display RGBA on writeTexture only`).
* No bounds guard in the compositor (OOB stores at non-multiple-of-16 sizes).
* App depth: `depthRead` is a fresh `r32float` (zeros) filled only by per-image depth estimation,
  so flat depth (all 0) is a real, common state. Every idea must degrade to a clean picture there.
* Depth direction (inferred from HEAD): fog = exp(-depth·fog·3) → larger = farther; layer 0 =
  near (speed = Parallax slider), layer 4 = far (speed = Layer Density slider). I keep it and
  make the new ideas symmetric in depth wherever possible.

---

## Card 1 — parallax_depth_layers

```
SHADER: parallax_depth_layers
IDENTITY (one sentence): the source photo as a five-slice depth stack that dollies toward the
  cursor at depth-dependent speed, with flow shimmer, a depth-edge glow, atmospheric fog and a
  volumetric alpha.
KEEP VERBATIM: 5 slices, layerDepth = i/4; layerSpeed = mix(x,y,layerDepth) (x Parallax = near
  speed, y Layer Density = far speed — roles unchanged); layerZoom = 1 + fract(zoom_time·speed)·4
  about zoom_center (= pointer, idle 0.5,0.5); per-slice vortex spin ∝ clickIntensity/(dist+0.1)·
  z(1−z); noise flow jitter 0.015·z; ping_pong uv; density exp(−1.5z)·(1+0.5·sampleDepth);
  baseDepth average; depth-scaled chromatic split; warm (1,.8,.6) depth-edge glow; navy fog
  (0.02,0.05,0.1) with fog slider as density; calculateVolumetricAlpha; reconstruct_normal;
  writeDepth = baseDepth.
RESCUE (not ideas): (a) layered composite now reaches the output (HEAD: passthrough);
  (b) chroma from plasmaBuffer[0].x at a small scale instead of extraBuffer[0] as a uv offset;
  (c) edge glow polarity (1−exp(−k·|∇d|)); (d) clickIntensity keeps the FFT-bin-5 drive and also
  honours the held pointer (zoom_config.w) — the name always meant click.
MECHANISM INTERROGATION (§12.1):
  t1 deepen kernel — weighted average of slices → front-to-back "over" with per-slice coverage:
    the next-better approximation of the same "alpha-occlusion" operator the features list claims.
  t2 physics one step further — a dolly zoom loop has a seam: fract() resets each slice to 1×
    (visible pop per slice per period). Real infinite-zoom rigs cross-fade two phases half a
    period apart. A layered scene viewed through a lens also defocuses slices away from the
    focal plane. Atmosphere absorbs red first (blue-green water/haze).
  t3 promote an intermediate — `layerDepth_1` is already a plane depth; `sampleDepth` is already
    read per slice and only used to nudge a weight. Use |sampleDepth − layerDepth| as slab
    membership. `baseDepth` already exists for fog.
  t6 history — none owned (C is not read); no history idea. A written as display RGBA (floor).
ADD (4 native ideas):
  1. Slab occlusion / disocclusion fill (front-to-back over): each slice covers a pixel with
     alpha = density·mix(0.35,1,slab(|sampleDepth−z|)); nearer slices occlude farther ones and
     farther slices show through where the near slice's sample belongs to another depth.
     Delivers the "alpha-occlusion" the header has always claimed.
  2. Seamless dolly crossfade: two zoom phases half a period apart, weights sin²(π·phase) /
     cos² (sum to 1 exactly) — removes the per-slice pop at the fract() wrap. Same zoom range.
  3. Rack-focus slice defocus: the dead Depth-of-Field slider becomes aperture; focal plane =
     depth under the cursor (zoom_center); per-slice CoC ∝ dof·|z−focusDepth| gathered with 3
     rotated taps. Pointer already owns zoom_center, so the focus pull is native.
  4. Beer–Lambert aerial perspective (§12.2F): per-channel extinction (1.25,1.0,0.75)·fog·3·depth
     (green channel = HEAD's scalar exactly) so distance eats red first into the existing navy
     fog; volumetric alpha now sees the real depth instead of a constant 0.5.
FORMULA ADMISSION: #4 is §12.2F Beer–Lambert — consumes baseDepth + fog slider the file has;
  deleting it leaves the scalar fog (same effect). #1–#3 are native mechanisms of a depth-slice
  compositor, no §12.2 row claimed. Same-noun test: slice, depth, focus, haze — all this shader's.
FORBID: springs, ripple fronts, IQ palettes, neon, new params, lateral-parallax rewrite.
A PACKING: display RGBA (A = writeTexture colour+alpha; C is not read, so nothing depends on it).
```

## Card 2 — parallax-glow-compositor (pass-2 stage)

```
SHADER: parallax-glow-compositor
IDENTITY (one sentence): the pass-2 compositor that finishes a volumetric depth zoom — depth-scaled
  chromatic aberration, a volumetric glow, and depth-aware haze over the previous pass' image.
KEEP VERBATIM: stage role (reads readTexture + readDepthTexture, writes writeTexture + depth
  passthrough, A/B untouched — single display output), depth-scaled chromatic split about the
  pointer/zoom centre, warm (1,.8,.6) depth-edge glow, navy fog exp(−depth·0.3·3) (0.3 is HEAD's
  value at the saved default of the slider that used to feed it), calculateVolumetricAlpha,
  reconstruct_normal, hash/noise helpers not needed → removed with the dead loop only if unused.
RESCUE (not ideas): (a) slider roles = the JSON names (glowRadius x, glowIntensity y,
  aberration z, bloomThreshold w): at HEAD x,y were *layer speeds* of a loop whose colour is
  discarded, z was dead, w was fog density; the dead layer loop is dropped, depth is read at the
  pixel; (b) bounds guard added; (c) chroma no longer bass-as-uv-offset (aberration slider
  default 0.02 = HEAD's fallback); (d) edge glow polarity; (e) fog density fixed at 0.3.
MECHANISM INTERROGATION (§12.1):
  t1 deepen kernel — a 2-tap horizontal ±chroma·depth split → radial multi-term dispersion
    (Cauchy) about the optical axis the file already uses (zoom_center).
  t2 physics one step further — a lens that disperses also blooms; a glow takes energy from the
    highlights it spreads (energy conserving). Colour fringes must not smear across a depth edge.
  t3 promote an intermediate — `baseDepth`, `depthX/depthY` are already read; the glow gather
    and the fringe guard reuse the depth taps.
  t6 history — stage owns none; no history idea.
ADD (3 native ideas):
  1. Energy-conserving bloom (§12.2F): soft-knee extract above bloomThreshold, 8-tap golden-angle
     gather at glowRadius, `src −= spread·k; out = src + spread·glowIntensity` — the "volumetric
     glow" of the JSON description; far pixels scatter slightly more (haze).
  2. Cauchy dispersion (§12.2F): R/G/B radial scales from n(λ)=A+B/λ² (B ∝ aberration slider)
     about zoom_center; blue deviates ~1.75× red, not a symmetric ±δ.
  3. Depth-guarded fringe: R/B taps whose depth differs from the centre pixel by > 0.12 fall back
     to the centre tap, so foreground colour does not leak onto the far plane.
FORMULA ADMISSION: #1 and #2 are §12.2F rows, both consume quantities the file already has
  (readTexture taps, depth, zoom_center, saved sliders); neither is used on parallax_depth_layers
  (that file uses Beer–Lambert) so the pair shares no formula. #3 is a depth-aware filter rule.
FORBID: layer loop as output (it would turn the compositor into a second zoom pass), springs,
  ripples, IQ palette, new params, A/B writes.
A PACKING: display RGBA on writeTexture only (A/B not written — it is a pass stage; unchanged).
```
