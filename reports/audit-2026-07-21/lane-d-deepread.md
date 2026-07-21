# Lane D — Deep-Read WGSL Audit (2026-07-21)

**Scope:** 24 stratified WGSL shaders from `public/shaders/`, none touched by the 2026-07-21 batch-9 gating pass.
**Method:** full manual read of each file, cross-checked against the live renderer (`src/renderer/webgpu/frame.ts`, `src/renderer/UniformBuffer.ts`, `src/renderer/ShaderCompilation.ts`, `src/renderer/ShaderTemplates.ts`) and `docs/BINDING_CONTRACT.md`. Slider semantics verified against `shader_definitions/*/<id>.json` where findable.

## Renderer ground truths established (used for verdicts)

1. **`zoom_config = [time, mouseX, mouseY, mouseDown]`** (`UniformBuffer.ts:50`, `frame.ts:654`). Mouse + ripples are normalized 0–1 (`wasm_bridge.js:696`). `zoom_config.x` is **time**, not "audio" or "zoom".
2. **`zoom_params` components are always normalized 0–1 sliders** (all sampled JSON defs: min 0, max 1).
3. **Only the `main` entry point is ever dispatched** (`ShaderCompilation.ts:190`). Second entry points (e.g. `update_boids`) are dead code.
4. **Feedback semantics of `dataTextureC`** (`frame.ts:542-557`): after each *chained* slot, if any shader reads C: `dataTexA → dataTexC` is copied, then **`dataTexB → dataTexC` is copied, clobbering A**. A shader that writes *both* A and B and reads C for feedback therefore reads back **B's contents, not A's**. Parallel slots never update C at all (feedback frozen).
5. **`extraBuffer` (binding 10) is the 256-float audio/FFT buffer** (`webgpuConstants.ts:10`, BINDING_CONTRACT.md): [0]=bass, [1]=mid, [2]=treble, [4]=historyHead, [5..132]=FFT. It is **not** a general-purpose particle-state buffer.
6. **Final blit ignores alpha** (`ShaderTemplates.ts:104-110`): `vec4f(pow(clamp(c.rgb)...), 1.0)`. Shaders that premultiply rgb by alpha before `textureStore(writeTexture, ...)` darken themselves.
7. WGSL `smoothstep(e0, e1, x)` with `e0 > e1` is **indeterminate per spec** (works de-facto on most implementations; pervasive in this codebase — noted once here, not per-file).

---

## Per-file verdicts

### Generative (3)

**1. `gen-acid-lissajous.wgsl` — BUG (feedback clobbered)**
- L222-227, 249-250: reads `dataTextureC` for temporal trails and writes *both* `dataTextureA` (color) and `dataTextureB` `(drift, depth, alpha)`. Per truth #4, C next frame holds B's content → trails mix `(drift.x, drift.y, depth)` as RGB (near-black). Trail feature is effectively dead in chained mode.
  *Fix:* drop the `dataTextureB` store, or move trail color into B and read C expecting B.
- L146: `gravStr = u.zoom_params.z` — slider z already used for `glowWidth` (L145); one slider drives two unrelated knobs. Minor.
- L171: `sf / max(f32(STRANDS)-1.0)` — when audio/click adds strands (`activeStrands` up to 9), `sf/4` exceeds 1 → frequencies up to ~2.25× `complexity` → heavy aliasing at 96 samples. Minor.
- Bounds guard (L129), mouse aspect math (L150-155), first-frame C (black → mix) all OK.

**2. `gen-belousov-zhabotinsky.wgsl` — BUG (feedback clobbered) + no bounds guard**
- L70-92 reads sim state `(a, b)` from `dataTextureC.rg`, but writes state to `dataTextureA` (L142) *and* a detail channel to `dataTextureB` (L144). Per truth #4, C next frame = previous B = `(lapA, lapB, oxidized, waveFront²)` — the reaction reads its own Laplacian as concentrations. The BZ simulation cannot evolve correctly.
  *Fix:* remove the `dataTextureB` store (or gate it behind a build where C copies A last).
- L53-58: **no bounds guard** on `global_id` before any stores; relies on WebGPU robustness to drop OOB writes. Bad practice (edge pixels also compute garbage that is still written in-bounds... only OOB lanes affected).
- First-frame seeding via `if (a + b < 0.01)` (L74) works, but note it *re-triggers* anywhere the (wrong) feedback reads near-zero, randomly re-seeding spirals mid-simulation.

**3. `gen-buddhabrot-aura.wgsl` — MINOR BUG**
- L68: `let depth = smoothstep(0.0, 1.0, u.config.w / resolution.y);` — `u.config.w` **is** `resolution.y`, so `depth` is the constant `1.0`. All downstream depth modulation (L134, L139) is a no-op. *Fix:* sample `readDepthTexture` instead.
- Feedback pattern correct (writes A only, reads C, L143-148). Guard OK (L52). All 4 sliders used.
- L67: `mouseC` is scaled by `mouseZoom` (slider z) — at slider 0 the mouse pan is disabled; acceptable design, noted.

### Liquid (3)

**4. `liquid-oil.wgsl` — MINOR (dead sliders + no guard)**
- **All four `zoom_params` sliders are never read**, yet `liquid-effects/liquid-oil.json` declares `viscosity/turbulence/ripple_strength/...` mapped to `zoom_params.x/y/z/w` → every UI slider is dead. *Fix:* wire params into `flowPattern` amplitude / ripple `stir_speed` / F0.
- L123-124: no bounds guard before stores (L193, L197).
- Ripple loop (L139-155) and normalized-coordinate usage correct; depth passthrough OK.

**5. `liquid-time-warp.wgsl` — CLEAN**
- Guard (L105), all 4 sliders (L117-120, match `interactive-mouse/liquid-time-warp.json`), aspect-corrected mouse (L131), writes A only / reads C (L152, L180) → feedback contract satisfied. Declares `dataTextureB` but never writes it (good — avoids the #4 clobber).
- Caveat (systemic, truth #4): in *parallel* slot mode C is never refreshed, so trails freeze. Not a shader bug.

**6. `liquid-touch.wgsl` — BUG (feedback clobbered)**
- L81-89 reads state `(phi, velocity, temperature, mergeSignal)` from `dataTextureC`; writes state to `dataTextureA` (L161) *and* a debug/detail pack to `dataTextureB` (L162). Per truth #4, C returns next frame = B's contents → `phi ≈ curvature*0.01+0.5`, `velocity ≈ interfaceDelta…` — the capillary sim runs on garbage state. The pretty refraction still renders (it keys off the misread state), so this "compiles and renders plausible-but-wrong".
  *Fix:* delete the `dataTextureB` store (or have the renderer copy A→C *after* B→C; see renderer-level recommendation below).
- Otherwise exemplary: guard, clamped UVs, safe normalizes, all 4 sliders, aspect-corrected mouse and ripples.

### Image/effect classics (3)

**7. `vortex.wgsl` — CLEAN**
- Guard (L127), all 4 sliders with sane `mix()` ranges, writes A only, no C read, depth passthrough modulated (L225, can exceed 1.0 — r32float tolerates it). No issues found.

**8. `kaleidoscope.wgsl` — BUG (time bomb via `zoom_config.x`)**
- L89: `let audio = u.zoom_config.x;` — per truth #1 this is **time in seconds**, so `audioReact = 1.0 + time*0.3 + bass*0.2` (L92) **grows without bound**. `roseA` (L116), Lissajous displacement (L106), Gabor tint (L148) and `edgeGlow` (L170) all scale with `audioReact` → the image progressively over-warps and washes out the longer the shader runs.
  *Fix:* replace `u.zoom_config.x` with `plasmaBuffer[0].x` (bass) or a constant 1.0.
- Guard (L85) and all 4 sliders (match `distortion/kaleidoscope.json`) OK.
- L138-143: `finalUV` can roam far outside [0,1] (dispRadius/zoom, zoom ≥ 0.1 → up to ~7); the `edgeFade` black-out assumes clamp addressing — if the sampler ever wraps, valid wrapped content gets blacked. Minor, sampler-dependent.

**9. `tornado-vortex.wgsl` — BUG (premultiplied output into alpha-ignoring blit)**
- L194-197: `a = clamp(bloomWeight, 0, 1)` where `bloomWeight ≈ 0` for all pixels with luma < 0.45, then `textureStore(writeTexture, …, vec4(color * a, a))`. Per truth #6 the blit uses rgb as-is and forces alpha 1 → **everything except the bright funnel/lightning is multiplied toward black**. Likely renders far darker than intended.
  *Fix:* store `vec4(color, a)` (straight) and let downstream consumers use alpha.
- L115: `vVertical` computed, never used (dead). Reversed-argument `smoothstep` (L113-114, L127, L147, L155) — indeterminate per spec (systemic note #7).
- Guard, sliders, mouse-aspect all OK; depth write semantic (condensation/debris, L199) reasonable.

### Sort / feedback (3)

**10. `glitch-pixel-sort.wgsl` — BUG (dead slider modes) + no guard**
- L145: `sortMode = u.zoom_params.y` (a 0–1 slider per truth #2) is compared against `0.5` / `1.5` (L162-174) → **"angular" mode (≥1.5) is unreachable**; only horizontal/vertical ever run.
- L147: `iterations = max(1.0, min(8.0, u.zoom_params.w))` with w∈[0,1] → **always 1 iteration**; the entire multi-iteration accumulator (L187-205) is dead weight. *Fix:* `floor(u.zoom_params.y * 2.99)` for mode, `1u + u32(u.zoom_params.w * 7.0)` for iterations.
- JSON def (`visual-effects/glitch-pixel-sort.json`) is generic `Intensity/Speed/Scale/Detail` — names don't match shader semantics (Threshold/Mode/Glitch/Iterations); user-facing labels lie.
- L137-141: no bounds guard before stores (L244, L248).
- Mouse fallback (L151) treats `(0,0)` as "no mouse", but the app signals mouse-leave with `(-1,-1)` — harmless since only `sign()` is used.

**11. `magnetic-luma-sort.wgsl` — MINOR (dead code)**
- L90-94: `finalColor` is computed twice (`mix(...)` then overwritten by `max(...)`) and then **never used** — output is `mixed` (L104-110). ~15 lines of dead experimentation. Harmless but confusing.
- Correct feedback pattern (writes A L111 / reads C L78), guard (L31), all 4 sliders incl. `trailDecay` whose JSON range 0.5–0.99 is honored if the app maps slider range → params (it passes raw values; decay then = raw 0–1, still stable). Clean otherwise.

**12. `pixel-sort-radial.wgsl` — BUG (twist term sends UVs off-screen) + no guard**
- L72-75: `tangent` has magnitude ≈ |dir| ≈ 1.0 (dir normalized + jitter) and is added **unscaled** whenever `influence > 0.001`: `finalUV = uv - dir*stretchFactor*0.2 + tangent*1.0`. A full-unit UV offset samples ~a screen-width away (or the clamp edge) — the "twist" overwhelms the subtle stretch and turns the effect into chaotic smear. `tangent` should be scaled by e.g. `stretchFactor * 0.1` or `twistAngle`.
- L39-43: no bounds guard before stores (L89-93).
- Sliders all used, aspect handling consistent (L55), rotation math on L72 is actually correct (verified as R(θ)·(−y,x)).

### Simulation-ish (3)

**13. `boids.wgsl` — BUG (severe: dead sim kernel + audio buffer abuse)**
- L56-106 `update_boids` is a second entry point; per truth #3 the renderer only dispatches `main` → **the flocking update never runs**.
- Both entry points use `extraBuffer[idx*4 …]` for 8192 boids = 32768 floats; per truth #5 the buffer is **256 floats of audio/FFT data**. `main` (L126-131) therefore reads boid "positions" that are really bass/mid/treble/historyHead/FFT bins (first 64 boids) and 0.0 (robustness OOB) for the remaining ~1984 → all boids pile at pixel (0,0). Renders a corner blob + audio-jitter specks; no flocking possible.
  *Fix:* particle state must live in `dataTextureA/B` (or a dedicated buffer added to the contract), and the update must run inside `main` (e.g. one boid per workgroup-Z or a staggered subrange), not a second entry point.
- Even if dispatched: L99 `normalize(vec2(vx,vy))` on zero velocity → NaN, sticky through `fract()`; and `BOID_SPEED = 2.0` in normalized space = teleport 2 screens/frame (L99-101). L67: `pos / tex_size` double-normalizes an already-normalized position → brightness always samples texel ~(0,0).
- `main`: no bounds guard (L194, L196).

**14. `cymatic-sand.wgsl` — CLEAN**
- Textbook feedback: writes `dataTextureA` only (L144), reads C (L125), never touches B → no clobber. Guard (L71), all 4 sliders, click-ripples clear state (L129-137), first-frame density 0 converges. Depth write semantic (L173-175).
- L95-96: `mouse.x >= 0.0` means the mouse (default ≥ 0) always overrides the `freqMode` slider — arguably intended ("mouse selects sub-mode"), noted.

**15. `quantum-foam.wgsl` — BUG (`zoom_config` read as extra sliders; quadratic time spin)**
- L191-194: `rotationSpeed = u.zoom_config.x * 2.0` — that's **time** (truth #1), so the rotation angle at L241 becomes `time * (time*2) + …` = **2t²**, an accelerating spin that strobes within seconds. `depthParallax = u.zoom_config.y * 0.2` and `emissionThreshold = u.zoom_config.z * 0.5 + 0.3` silently bind effect params to **mouse X/Y**, and `chromaticSpread = u.zoom_config.w * 2.0 + 0.5` jumps 0.5→2.5 while the mouse is held. These were clearly meant to be `zoom_params` (but all 4 of those are already consumed at L187-190 — the shader wants 8 params).
  *Fix:* L191 → `u.config.x * 2.0` is still odd; better: constant or `zoom_params`-free constant; move parallax/threshold/spread to constants or derive from existing params.
- Feedback pattern OK (A only, L272; reads C L259). Guard (L175).
- L47-70 `noise4d` never interpolates the 4th dimension (`u.w` computed, unused) → temporal popping in `hyperNoise`. Minor.

### Unusual workgroup sizes (3)

**16. `deep-workgroup-multi-effect-blend.wgsl` — CLEAN (minor blend double-count)**
- 16×16×4 workgroup, barrier in uniform control flow (L172), OOB lanes correctly participate in the barrier and skip only the final store (L88, L175). Shared-memory indexing consistent. This is the reference-correct pattern.
- Minor: each lane already applies `blendMix` internally (L123, 139, 147, 165) *and* the final composite applies it again (L186) → at mid slider values effects are doubly attenuated.
- Requires `maxComputeInvocationsPerWorkgroup ≥ 1024` — gating claimed in header; renderer contract default is 256 (BINDING_CONTRACT.md L78), so this shader depends on catalog gating (`requiresDeepWorkgroup`) being honored.

**17. `kimi_flock_symphony.wgsl` — BUG (same severe family as boids)**
- L95-183 `update_boids` never dispatched (truth #3). `extraBuffer` needs 16384×6 = 98304 floats vs. 256 available (truth #5): `main` (L204-211) reads audio/FFT floats as boid state for the first ~42 boids and 0.0 for the rest → static corner pile + audio-value specks; the "symphony" never flocks.
- L262: writes **constant 0.0 depth** for every pixel — downstream depth-aware shaders in a chain see a flat black depth map. Minor bug.
- `main`: no bounds guard (L261-262); uses `textureDimensions(readTexture)` instead of `u.config.zw` for output coords — inconsistent with the dispatch grid (which is based on config.zw); if read/write textures ever differ in size, writes land wrong.
- `applyGenerativePrimaryControls` (L27-35) at least uses all 4 sliders correctly.

**18. `datamosh-brush.wgsl` — MINOR (dead code)**
- L87-88, L116: `blockUV` and `pixUV` computed but never used (only `blockID` is). Dead vars.
- L82-83: alpha decays geometrically every frame (`*(1-decay*0.5)`) — equilibrium screen alpha ≈ 0.66 with default decay; probably intended "ghosting", noted since blit ignores alpha anyway.
- Feedback correct: writes A only (L129), reads C with first-frame fallback (L61-70). Guard (L42), all 4 sliders, aspect-corrected mouse (L91). Workgroup (8,8,1) unremarkable.

### .backup files (3)

**19. `gen-art-deco-sky.wgsl.backup` — CLEAN (minor)**
- Guard (L224), all 4 sliders, normalized mouse used correctly for camera orbit (L240-241), raymarch depth written (L374, `t/200` can slightly exceed 1.0 — tolerable).
- L104/L135: `%` (remainder) on possibly-negative `cp.y` → negative fluting/motif terms; visually benign. L300 window-cell hash mixes scales; cosmetic.

**20. `gen-magnetic-ferrofluid.wgsl.backup` — BUG (mouse in wrong space)**
- L104-105: `mouseX = (u.zoom_config.y / dims.x) * 2.0 - 1.0` — mouse is already normalized 0–1 (truth #1); dividing by `dims.x` (~1920) collapses `mouseX/Y` to ≈ −1 always → **camera orbit is pegged; mouse interaction dead**.
  *Fix:* `u.zoom_config.y * 2.0 - 1.0`.
- L60: `var dir = normalize(pos)` unused. Never writes `writeDepthTexture` — leaves stale depth in a chain. Guard OK, sliders OK.

**21. `gen_mandelbulb_3d.wgsl.backup` — MINOR**
- L158: `audioPulse = u.zoom_config.w` — that's **mouseDown**, not audio: fractal power jumps +2 only while the mouse is held. Mislabeled "audio" feature. *Fix:* use `plasmaBuffer[0].x`.
- L53: `z.z / r` with `r = 0` (exact-origin start) → NaN DE → NaN propagates into `t` and out to depth (L243). Practically rare (camera ≥ 0.5 away), but one unlucky ray poisons a pixel. Guard w/ `max(r, 1e-6)`.
- Guard (L144), all 4 sliders, depth write semantic.

### Random others (3)

**22. `ascii-glyph.wgsl` — CLEAN**
- Guard (L44), all 4 sliders, depth-weighted luma and passthrough depth, writes A (harmless, no C read). Bass-driven glyph swap and cell math consistent. No findings.

**23. `anaglyph-3d.wgsl` — BUG (NaN from pow of negative) + premultiply issue**
- L88-90 `colorGrade`: `c = c + lift*(1-c)` with `lift.b = -0.01` (L184) makes `c.b < 0` for dark pixels, then `pow(c, gamma)` → **NaN** in the blue channel for shadow regions (WGSL `pow` of negative = indeterminate). NaN survives to the store. *Fix:* `c = pow(max(c, vec3(0.0)), gamma)`.
- L209-210: premultiplies `color * finalAlpha` before storing; per truth #6 the blit ignores alpha → output darkened wherever `finalAlpha < 1` (here `finalAlpha` is usually ≈1, so low-impact — unlike tornado-vortex). Store straight rgb instead.
- Feedback: writes A (L210) / reads C (L201) — correct. Guard, sliders, mouse-depth sampling all fine.

**24. `velvet-vortex.wgsl` — CLEAN (minor)**
- Guard (L39), all 4 sliders, consistent aspect-corrected mouse/vortex math (L57-59), clamped final UV, depth passthrough with small additive pile (L82).
- L50/L58: depth parallax is applied as `(parallax, parallax)` — diagonal-only shift; and the parallax term isn't un-corrected when converting back to UV space at L76 (x scaled by 1/aspect). Cosmetically minor.

---

## Summary table

| # | File | Verdict |
|---|------|---------|
| 1 | gen-acid-lissajous | **bug** (C-feedback clobbered by B write) |
| 2 | gen-belousov-zhabotinsky | **bug** (sim state clobbered; no guard) |
| 3 | gen-buddhabrot-aura | minor (constant `depth`; L68) |
| 4 | liquid-oil | minor (4 dead sliders; no guard) |
| 5 | liquid-time-warp | clean |
| 6 | liquid-touch | **bug** (state feedback clobbered by B write) |
| 7 | vortex | clean |
| 8 | kaleidoscope | **bug** (`zoom_config.x` time-bomb) |
| 9 | tornado-vortex | **bug** (premultiplied store → near-black) |
| 10 | glitch-pixel-sort | **bug** (unreachable modes; no guard) |
| 11 | magnetic-luma-sort | minor (dead code) |
| 12 | pixel-sort-radial | **bug** (unscaled tangent; no guard) |
| 13 | boids | **bug — severe** (dead kernel + audio-buffer abuse) |
| 14 | cymatic-sand | clean |
| 15 | quantum-foam | **bug** (`zoom_config` as params; t² spin) |
| 16 | deep-workgroup-multi-effect-blend | clean (minor double blendMix) |
| 17 | kimi_flock_symphony | **bug — severe** (dead kernel + audio-buffer abuse; flat depth) |
| 18 | datamosh-brush | minor (dead vars) |
| 19 | gen-art-deco-sky.wgsl.backup | clean (minor) |
| 20 | gen-magnetic-ferrofluid.wgsl.backup | **bug** (mouse ÷ resolution) |
| 21 | gen_mandelbulb_3d.wgsl.backup | minor (mouseDown as "audio"; NaN edge) |
| 22 | ascii-glyph | clean |
| 23 | anaglyph-3d | **bug** (pow(negative) NaN; premultiply) |
| 24 | velvet-vortex | clean (minor) |

**Tally: 12 bug, 6 minor, 6 clean.**

## Most severe 5 findings

1. **`boids.wgsl` / `kimi_flock_symphony.wgsl` — particle sims are structurally dead.** Their `update_boids` entry points are never dispatched (renderer only runs `main`), and they store boid state in `extraBuffer`, which is the 256-float audio/FFT buffer — they need 32K/98K floats. Both render a static corner pile + audio-value specks instead of flocking. Needs contract-level fix (state in dataTextures, single entry point).
2. **`dataTextureB` writes clobber the `dataTextureC` feedback channel** (renderer copies A→C *then* B→C in `frame.ts:543-556`). All three sampled shaders that write both A and B and read C for feedback — `liquid-touch`, `gen-belousov-zhabotinsky`, `gen-acid-lissajous` — read back B's detail channels as their state/color, silently breaking their simulations/trails. Renderer fix (copy B→C first, A→C last) or shader fix (don't write B) needed; likely affects more shaders fleet-wide — recommend a grep for files storing to both binding 7 and 8 while sampling binding 9.
3. **`kaleidoscope.wgsl:89` — `audio = u.zoom_config.x` reads time as an audio level**; `audioReact` grows ~0.3/second forever, progressively destroying the image the longer it runs.
4. **`quantum-foam.wgsl:191-194` — all of `zoom_config` consumed as if it were four more sliders**: rotation angle becomes 2t² (accelerating strobe), and parallax/threshold/chroma are silently bound to mouse X/Y/click.
5. **`tornado-vortex.wgsl:197` — premultiplies rgb by a bloom-weight alpha that's ≈0 for most pixels**, but the final blit ignores alpha → the scene renders near-black outside the funnel. (Same pattern, low-impact, in `anaglyph-3d:209`; `anaglyph-3d` also has a real NaN via `pow(negative, gamma)` in `colorGrade` for dark blue channels.)

## Cross-cutting notes for the swarm

- **Missing bounds guards** (rely on WebGPU robustness dropping OOB stores): gen-belousov-zhabotinsky, liquid-oil, glitch-pixel-sort, pixel-sort-radial, boids, kimi_flock_symphony. Harmless on spec-compliant WebGPU, bad practice.
- **Reversed-argument `smoothstep`** (indeterminate per WGSL spec) is pervasive (tornado-vortex, gen-acid-lissajous, pixel-sort-radial, kaleidoscope…). Works on mainstream implementations; worth a lint rule.
- **Parallel slot mode never refreshes `dataTextureC`** — every C-feedback shader (liquid-time-warp, magnetic-luma-sort, cymatic-sand, datamosh-brush, anaglyph-3d, …) silently loses its temporal feedback if placed in a parallel slot.
- JSON `updatedParams` labels vs. shader semantics mismatch: glitch-pixel-sort (generic labels, dead modes), liquid-oil (declared but unread params).
