# Weekly Shader Upgrade Swarm — Batch 1

> **Goal:** Upgrade WGSL shaders to fix undersized generative effects, replace naive RGB-only patterns with RGBA-aware blending, and add meaningful alpha, audio reactivity, and missing params.
> **Constraint:** Do NOT modify `Renderer.ts`, `types.ts`, or bind groups. Do NOT install new npm packages.

---

## Recently Completed (238 shaders)

These shaders have been edited, their JSONs updated where needed, and `generate_shader_lists.js` validated the changes.

### Batch 25 (8 shaders) — 2026-08-02 — SMALLEST-FIRST ALL-CATEGORY EDITION 8

Eighth all-category wave: the next clean single-pass 112–114 liners across
interactive-mouse, hybrid, and post-processing. This cohort closed unusually
deep contract bugs: Hybrid Fractal's four UI controls were all mapped to the
wrong WGSL behaviors; Fiber Optic and Hybrid Fractal assumed a fake 256-entry
audio palette; Signal Tuner hid state in display pixel (0,0); the history-ring
effect advertised mouse interaction but never read it; Paper Cutout treated a
valid top-left pointer as uninitialized and claimed depth while only passing it
through. All eight now have guarded normalized click interaction, meaningful
regional FFT behavior, exact additive parameter mirrors, and persistent state
only in `extraBuffer[133..139]`. Binding-13 history indexing and raw feedback
ownership remain intact. Explicit eight-file gate: 8/8 green (Naga + bindgroup,
zero workgroup warnings or buffer violations); dead-slider/JSON/list audits:
green; lists and 1,306-entry manifest regenerated; duplicates: 1,319/1,319
unique; Jest: 68 suites / 464 pass / 1 skip; `SKIP_WASM_BUILD=1 npm run build`:
green. Direct `tsx` hit the known VM IPC `EPERM`; `node --import tsx` rebuilt the
manifest. Live GPU visual QA remains the hardware handoff. Notes:
`swarm-outputs/codex-2026-08-02-b25/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 231 | `signal-tuner` | 25 | 112→155 (+43) | True spring/envelope safe state; origin feedback fixed; click retuning; regional FFT/depth. |
| 232 | `fiber-optic-weave` | 25 | 113→160 (+47) | Unsafe palette fixed; spring/click fiber plucks; per-fiber FFT; bounded glow/relief. |
| 233 | `hybrid-fractal-feedback` | 25 | 113→175 (+62) | All four mappings fixed; safe palette; real RGB delay; spring/click Julia relief. |
| 234 | `scan-slice` | 25 | 113→163 (+50) | Spring slice bank; click-stamped slices; valid FFT palette; mids/treble wired; displaced depth. |
| 235 | `split-dimension` | 25 | 113→164 (+51) | Spring seam; click fractures; per-band FFT; bounded glitch output; dimension-following depth. |
| 236 | `temporal-decay-multiresolution` | 25 | 113→170 (+57) | Real mouse lens; click history echoes; regional FFT decay; binding-13/history-head contract preserved. |
| 237 | `paper-cutout` | 25 | 114→159 (+45) | Top-left/safe-normal fix; spring light; click emboss; FFT layers; honest relief depth. |
| 238 | `rgb-delay-brush` | 25 | 114→159 (+45) | Scoped model claim; spring/click temporal brush; valid RGB FFT voices; raw A feedback preserved. |

### Batch 24 (8 shaders) — 2026-08-02 — SMALLEST-FIRST ALL-CATEGORY EDITION 7

Seventh wave of the all-category pool: the next eight clean, single-pass 110–112
liners across interactive-mouse, visual-effects, and distortion. The upgrade
adds spring-weighted interaction, normalized guarded click behavior, and
per-region FFT voices while preserving live slider and feedback contracts.
Special correctness wins: `night-vision-scope` now earns its depth-aware claim;
`data-stream` no longer has an elliptical mouse wake and its dead treble signal
now drives character emergence; `knitted-fabric` no longer stores masks in the
host-primary A slot; `blueprint-reveal` keeps its raw temporal mask in A without
display-color contamination. All new persistent state is confined to
`extraBuffer[133..138]`. Explicit eight-file gate: 8/8 green (Naga + bindgroup,
zero workgroup warnings or buffer violations); dead-slider/JSON contract audits:
green; lists and 1,306-entry manifest regenerated; duplicates: 1,319/1,319
unique; Jest: 68 suites / 464 pass / 1 skip; `SKIP_WASM_BUILD=1 npm run build`
and the final no-prebuild asset rebuild: green. The VM's direct `tsx` manifest
command hit its known IPC `EPERM`, so the documented `node --import tsx` path
provided manifest proof. Live GPU visual QA remains the hardware handoff.
Notes: `swarm-outputs/codex-2026-08-02-b24/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 223 | `quantum-tunnel-interactive` | 24 | 110→162 (+52) | Spring tunnel center; click mouths; sector FFT aberration; bounded HDR; relief depth. |
| 224 | `vhs-tracking-mouse` | 24 | 110→157 (+47) | Spring tracking head; localized click tears; row FFT hiss; displaced depth sampling. |
| 225 | `blueprint-reveal` | 24 | 111→160 (+49) | Spring brush; click ink blooms; tile FFT voices; raw A-mask feedback preserved. |
| 226 | `cyber-grid-pulse` | 24 | 111→168 (+57) | Spring magnet; click grid shockwaves; cell FFT voices; clamped UVs and bounded HDR. |
| 227 | `night-vision-scope` | 24 | 111→161 (+50) | Spring scope; click intensifier rings; FFT scanlines; honest lens relief depth. |
| 228 | `data-stream` | 24 | 112→161 (+49) | Aspect-correct spring wake; click eddies; strip FFT; dead treble wired; bounded emission. |
| 229 | `glitch-slice-mirror` | 24 | 112→163 (+51) | Spring seam; localized click fractures; nonnegative intensity; block FFT/treble breakup. |
| 230 | `knitted-fabric` | 24 | 112→165 (+53) | Spring pull; click plucks; stitch FFT/relief; display moved to A and masks to B. |

### Batch 23 (8 shaders) — 2026-08-01 — GENERATIVE + IMAGE UPGRADES

Focused correctness/performance wave with a literal 4-generative/4-image split. The two remaining fireworks-family normalized-mouse bugs were fixed and their flat depth behavior replaced; the zeta landscape now uses a guarded 24–96-term Dirichlet-eta continuation instead of a divergent critical-strip series; bioluminescent reaction-diffusion now clamps its stencil and no longer treats the audio buffer as a 256-entry palette; Cycloid Bloom drops from 1,205 to 360 curve-distance tests per pixel. Image wins include real CRT click damage/treble static, visible Steampunk tooth shading with single-mask compositing, honest Depth Parade shell depth, and bounded/sprung Fractal Dissolve erosion. All ripple loops are guarded, persistent state uses only `extraBuffer[133..138]`, and feedback roles remain unchanged. Explicit 8-file gate: green (Naga + bindgroup, 0 workgroup warnings, 0 extraBuffer violations); focused dead-slider/buffer audits: green; JSON contracts: preserved; lists/manifests regenerated; duplicate check: 1,319/1,319 unique; Jest: 68 suites / 464 pass / 1 skip; `SKIP_WASM_BUILD=1` production build: green. Notes: `swarm-outputs/codex-2026-08-01-b23/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 215 | `gen-fireworks-roman-candle` | 23 | 111→151 (+40) | Normalized pointer fixed; discrete click candles; treble detail loops; luminance depth; A/B packing preserved. |
| 216 | `gen-zeta-function-landscape` | 23 | 127→151 (+24) | Guarded Dirichlet-eta continuation (24–96 terms); ripple refraction; eight FFT color regions; height/A feedback preserved. |
| 217 | `gen-bioluminescent-reaction-diffusion` | 23 | 131→142 (+11) | Boundary-clamped stencil; state-derived palette with FFT bins 1–8; four honest controls; raw A/B state preserved. |
| 218 | `gen-cycloid-bloom` | 23 | 133→171 (+38) | 64+8 nearest-curve search; mouse pull without bass gate; click petal waves; per-layer FFT shimmer. |
| 219 | `crt-scanline-damage` | 23 | 112→151 (+39) | Click damage/degauss bands; dead treble→static scars; temporal phosphor preserved; indexed updatedParams. |
| 220 | `steampunk-gear-lens` | 23 | 112→169 (+57) | Tooth-lit rim; double mask removed; spring [133..138]; click kick/flares; relief depth; indexed updatedParams. |
| 221 | `fireworks-depth-parade` | 23 | 113→163 (+50) | Normalized pointer fixed; ripple depth barrages; source/shell depth; supportsDepth corrected; indexed updatedParams. |
| 222 | `fractal-noise-dissolve` | 23 | 116→177 (+61) | Category fixed; hue-preserving burn knee; spring [133..138]; click dissolve rings; one depth sample; indexed updatedParams. |

### Batch 22 (8 shaders) — 2026-07-31 — SMALLEST-FIRST ALL-CATEGORY EDITION 6

Sixth wave of the all-category pool (680 remaining after Batch 21), 107–110 liners across interactive-mouse / retro-glitch / artistic / image. Brief generator `temp/make_briefs_2026_07_31_b22.py` reuses the b17 all-category scanner. Special wins: `pixel-explode` had **ALL 4 sliders dead** — `u.zoom_params` was never read; grid size/radius/force/search-range all hardcoded behind generic Intensity/Speed/Scale/Detail labels (wired with bit-exact defaults: force mix(0,0.16)→0.08, grid mix(16,64)→40, range mix(2,10)→6; Speed birthed a new wobble motion); `prismatic-3d-compositor` had an **INVERTED mouse-units bug** (`zoom_config.yz / dims` — double-dividing an already-normalized mouse pinned the parallax driver to the corner; the headline parallax feature had never worked — 4th mouse-units sighting, first inverted variant) plus a **'cameraZ' that was secretly mouseDown**; `luma-refraction` had **mask-as-color feedback** (the 'temporal wave memory' mixed the wave STATE h∈[-10,10],v into the display color — spore-galaxy class, 4th sighting; mix line removed, wave-state A/C contract kept verbatim); `directional-blur-wipe` had a **dead 'Split Pos' slider** (read, never used — now offsets the wipe line, default 0.5 bit-identical) plus a dead per-loop `chroma` var (now disperses); `spectral-glitch-sort` had **elliptical mouse influence** (no aspect correction). All 8 gate green (naga + bindgroup, 0 warnings, 0 extraBuffer violations), JSON contracts preserved (updatedParams additive-only), lists/dupes clean (1319 unique definitions), Jest 63 suites/422 pass. Briefs: `swarm-tasks/kimi-briefs-2026-07-31-b22/`; notes: `swarm-outputs/kimi-2026-07-31-b22/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 207 | `quantum-cursor` | 22 | 107→177 (+70) | Spring field [133..138]; click decoherence bursts (local chaos spikes); per-block FFT jitter; shuffle/invert machinery verbatim. |
| 208 | `spectral-glitch-sort` | 22 | 108→178 (+70) | **Aspect-corrected mouse** (was elliptical) + spring [133..136]; click sort tears; per-block FFT voices; branchless sort verbatim. |
| 209 | `mirror-dimension` | 22 | 109→172 (+63) | Spring symmetry center [133..138]; click mirror spins (signed rotation kicks); per-segment FFT shimmer; dead treble→seam glow; fold math verbatim. |
| 210 | `pixel-explode` | 22 | 109→161 (+52) | **ALL 4 dead sliders wired** (bit-exact defaults); dead treble→blast crackle; click detonations; z-buffer particle physics verbatim. |
| 211 | `prismatic-3d-compositor` | 22 | 109→182 (+73) | **Inverted mouse-units fixed** (parallax works for the first time); cameraZ→mouseDown (press deepens); dead treble→glow; click prism flares; pass-2 reads verbatim. |
| 212 | `directional-blur-wipe` | 22 | 110→191 (+81) | **Dead Split Pos wired** (bit-identical default); dead `chroma`→per-sample dispersion; spring wipe [133..137]; click wipe flashes. |
| 213 | `ember-drift-dissolve` | 22 | 110→166 (+56) | Click ignition (fire from ripples); mouse heat plume; per-region FFT crackle; ember state contract verbatim. |
| 214 | `luma-refraction` | 22 | 110→186 (+76) | **Mask-as-color removed** (wave state out of display path); click raindrops; bass-transient audio rain; wave-sim core verbatim. |

### Batch 21 (8 shaders) — 2026-07-31 — SMALLEST-FIRST ALL-CATEGORY EDITION 5

Fifth wave of the all-category pool (687 remaining after Batch 20), 105–107 liners across interactive-mouse / image / artistic. Brief generator `temp/make_briefs_2026_07_31_b21.py` reuses the b17 all-category scanner. Special wins: `spec-histogram-equalize` had **TWO dead sliders** — 'Clip Limit' computed a `clippedCount` that was never used (no actual CLAHE clip; now real clip+redistribute CDF) and 'Tile Blend' was read but never referenced (now seam-softening blend) — plus **masks in dataTextureA** (display→A, debug quad→B); `fireworks-edge-ignite` and `fireworks-patriotic-july4` both had the **family diseases** from b18's fireworks-portrait-burst: the **mouse-coord-units bug** (normalized [0,1] treated as pixels — held-click bursts parked off-screen; 2nd/3rd sightings) and the **flat-0.0 depth clobber** behind a 'depth-aware' feature tag (3rd/4th sightings; both now luma-derived); `fireworks-patriotic-july4` also had a **dead mids read** (now drives the stripe wave); `moire-interference` had a dead `dir` var; `interactive-emboss`/`mouse-gravity` kept their dev thinking-out-loud comments verbatim (file personality) while gaining spring-damped lights/wells, click stamps/gravity pulses, and honest depth-aware relief; `kinetic-dispersion`'s spring velocity now literally drives the advertised 'mouse-velocity dispersion'. All 8 gate green (naga + bindgroup, 0 warnings, 0 extraBuffer violations), JSON contracts preserved (updatedParams additive-only), lists/dupes clean (1319 unique definitions — +1 from #1051's bismuth void-owl since b20), Jest 63 suites/422 pass. Briefs: `swarm-tasks/kimi-briefs-2026-07-31-b21/`; notes: `swarm-outputs/kimi-2026-07-31-b21/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 199 | `moire-interference` | 21 | 105→174 (+69) | Dead `dir` removed; spring emitter [133..137]; click third-emitter bursts; per-emitter FFT gains; depth write normalized. |
| 200 | `mouse-gravity` | 21 | 105→166 (+61) | Heavy spring singularity (ω=6) [133..138]; click secondary wells; photon-ring shimmer (treble bin 7); mouseDown deepens well; dev comments verbatim. |
| 201 | `fireworks-edge-ignite` | 21 | 106→175 (+69) | **Mouse-coord-units bug fixed** (bursts on-cursor); **honest depth** (was flat 0.0 clobber); click shell launches; spark pipeline/feedback verbatim. |
| 202 | `spec-histogram-equalize` | 21 | 106→163 (+57) | **Two dead sliders wired** (real CLAHE clip+redistribute; tile-blend seam softening); **A-slot unpoisoned** (display→A, debug→B); barriers/atomics sacred. |
| 203 | `speed-lines-focus` | 21 | 106→172 (+66) | Spring focus vortex [133..137]; click action bursts; angular FFT sector voices; depth write normalized; 16-tap zoom blur verbatim. |
| 204 | `fireworks-patriotic-july4` | 21 | 107→162 (+55) | **Mouse-coord-units bug fixed**; **honest depth**; **dead mids wired** (stripe wave); click grand-finale shells (R/W/B by click index); patriotColor verbatim. |
| 205 | `interactive-emboss` | 21 | 107→176 (+69) | Spring light [133..137]; click relief dents; **depth-aware relief** (tag earned); hue-preserving soft-knee; dev comments verbatim. |
| 206 | `kinetic-dispersion` | 21 | 107→186 (+79) | Spring influence + **velocity→intensity** (description made literal); click shatter bursts; per-block FFT voices ±30%; curl/shockwave verbatim. |

### Batch 20 (8 shaders) — 2026-07-31 — SMALLEST-FIRST ALL-CATEGORY EDITION 4

Fourth wave of the all-category pool (695 remaining after Batch 19), 103–105 liners across interactive-mouse / retro-glitch / image / visual-effects / post-processing. Brief generator `temp/make_briefs_2026_07_31_b20.py` reuses the b17 all-category scanner. Special wins: `neon-edge-reveal` had **ALL 4 slider labels generic/wrong** ('Intensity' drove reveal radius, 'Speed' drove edge boost, 'Scale' drove glow, 'Detail' only tweaked alpha — rewired honest with default 0.5 reproducing the legacy look bit-for-bit, Sobel window constants corrected in review to hit 0.05/0.30 exactly) plus an **unclamped ~19.8× HDR emission** (hue-preserving soft-knee, asymptote ~2.0 — kaleido-portal class); `long-exposure` had a **fake Glow Radius** (`gOff` computed from the slider but never used — fixed ±1-texel blur; now real ±gStep taps, dead var deleted) plus a **positional click reset** (was global mouseDown fade ignoring where you click — now an aspect-corrected eraser brush + ripple light stamps); `cyber-halftone-scanner` had the **OOB palette read** (`plasmaBuffer[palIdx % 256u]` → bins 1–8, 3rd sighting); `spectral-rain` declared mids/treble and **never used them** (now per-column FFT voices); `lenticular-holographic-shift` stored **masks in dataTextureA** (display→A, mask quad→B — latent chain poison); `sonar-pulse` was a **sonar shader that ignored the ripples uniform** (click pings fired at last). All 8 gate green (naga + bindgroup, 0 warnings, 0 extraBuffer violations), JSON contracts preserved (updatedParams additive-only), lists/dupes clean (1318 unique definitions), Jest 63 suites/422 pass. Briefs: `swarm-tasks/kimi-briefs-2026-07-31-b20/`; notes: `swarm-outputs/kimi-2026-07-31-b20/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 191 | `luma-topography` | 20 | 103→170 (+67) | Spring-damper light [133..138]; click fill-light flashes; depth-aware pixel height; lying struct/category comments fixed; Blinn-Phong verbatim. |
| 192 | `scanline-drift` | 20 | 103→155 (+52) | 1D spring tracking band [133..134]; mouse.x edge-proximity drift; click tracking tears; dead treble read wired (per-strip flicker); depth write normalized. |
| 193 | `sonar-pulse` | 20 | 103→169 (+66) | **Click pings** (ripples were unused — in a sonar shader!); spring origin [133..137]; per-ring FFT shimmer; beat/interference verbatim. |
| 194 | `cyber-halftone-scanner` | 20 | 104→158 (+54) | **OOB palette guarded** (%256→bins 1–8); click scan bursts; pointer dot bloom; FFT-band sweep intensity; dead PHI const removed; CMYK angles verbatim. |
| 195 | `neon-edge-reveal` | 20 | 104→177 (+73) | **All 4 generic labels rewired honest** (defaults bit-consistent, Sobel window 0.05/0.30 exact); **~19.8× HDR soft-knee**; click flares; spring flashlight; 9-tap Sobel verbatim. |
| 196 | `spectral-rain` | 20 | 104→172 (+68) | **Dead mids/treble wired** (per-column FFT voices ±20% trail/brightness); sprung angle/speed [133..137]; click splash bursts; rain grid verbatim. |
| 197 | `lenticular-holographic-shift` | 20 | 105→166 (+61) | **A-slot role fixed** (display→A, masks→B); 1D view spring [133..134]; click holo flash rings; mouse.y strip tilt; moiré/holo palette verbatim. |
| 198 | `long-exposure` | 20 | 105→156 (+51) | **Fake glow radius fixed** (real ±gStep taps, dead gOff deleted); **positional eraser brush** + ripple light stamps; per-band decay drift; raw-HDR A/C contract verbatim. |

### Batch 19 (8 shaders) — 2026-07-31 — SMALLEST-FIRST ALL-CATEGORY EDITION 3

Third wave of the all-category pool (705 remaining after Batch 18), 100–103 liners across interactive-mouse / geometric / post-processing / visual-effects / image. Brief generator `temp/make_briefs_2026_07_31_b19.py` reuses the b17 all-category scanner. Special wins: `holographic-shatter` had a **triple bug** — OOB palette read (`plasmaBuffer[palIdx % 256u]` → bins 1–8, same class as b18 holographic-sticker), a **dead 'Depth Weight' slider** (`depthLayeredAlpha()` defined but never called — now wired into finalAlpha), and an **inverted impact falloff** (`smoothstep(0.0, 0.6, dM)` grew with mouse distance — mouse-down shattered everything EXCEPT the cursor zone; now near-focused with a global baseline); `signal-modulation` had **fake spectral bands** (the 8-band visualizer was driven by `fract(sin())` hash noise, not FFT — now real `plasmaBuffer[band + 1]` bins, hash survives only as ±10% anti-digitization jitter — fake-FFT-proxy class); `ascii-glyph` was **tagged mouse-driven but never read the mouse** (`zoom_config` completely unused — spring-damper lens wired, finer glyphs under the pointer, click scrambles); `temporal-phosphor-burn-motion-adaptive` (history-ring, binding 13) also **never read the mouse** despite the tag (mouse phosphor lens + click burn stamps, ring indexing + extraBuffer[4] verbatim, extraBuffer read-only). All 8 gained guarded click-ripple interactivity; 6 gained spring-damper mouse glide (extraBuffer [133..138] only). All 8 gate green (naga + bindgroup, 0 warnings, 0 extraBuffer violations), JSON contracts preserved (updatedParams additive-only), lists/dupes clean (1318 unique definitions — +1 from #1047's gen-vitreous-quantum-lotus-singularity since b18). Briefs: `swarm-tasks/kimi-briefs-2026-07-31-b19/`; notes: `swarm-outputs/kimi-2026-07-31-b19/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 183 | `reactive-glass-grid` | 19 | 100→163 (+63) | Spring-damper glass bulge [133..137]; click shockwave rings; per-tile FFT voices (hash bin); dispersion/fresnel/ior verbatim. |
| 184 | `ascii-glyph` | 19 | 101→169 (+68) | **Mouse wired** (was tagged but unread — spring lens [133..136], finer glyphs under pointer); click glyph scrambles; stale comments fixed; SDF/beat-swap verbatim. |
| 185 | `temporal-phosphor-burn-motion-adaptive` | 19 | 101→155 (+54) | **Mouse wired** (phosphor charge lens + faint cursor trails); click burn stamps; per-band FFT decay drift; ring indexing + binding 13 + extraBuffer[4] verbatim (read-only). |
| 186 | `codebreaker-reveal` | 19 | 102→170 (+68) | Spring-damper reveal disc [133..136]; click reveal bursts (grow-collapse discs); per-column treble shimmer; rain math verbatim. |
| 187 | `digital-reveal` | 19 | 102→166 (+64) | Spring-damper brush [133..136]; click splash reveals into mask feedback; depth-gated rain brightness; A=mask/C=prev-mask contract verbatim. |
| 188 | `magnetic-ring` | 19 | 102→166 (+64) | Spring-damper ring center [133..138]; click flux shockwaves (4th ring); per-ring FFT voices (bins 1–3); 3-ring loop/spokes/chromatic taps verbatim. |
| 189 | `signal-modulation` | 19 | 102→161 (+59) | **Fake spectral bands fixed** (hash noise → real FFT bins 1–8, ±10% jitter kept); spring-damper wave origin [133..136]; click carrier bursts; huePreserveClamp verbatim. |
| 190 | `holographic-shatter` | 19 | 103→162 (+59) | **Triple bug fixed** (OOB palette %256→bins 1–8; dead Depth Weight slider wired via depthLayeredAlpha; inverted impact falloff → near-focused); click detonations; settling/shard math verbatim. |

### Batch 18 (8 shaders) — 2026-07-30 — SMALLEST-FIRST ALL-CATEGORY EDITION 2

Second wave of the all-category pool (712 remaining after Batch 17), 97–100 liners across interactive-mouse / visual-effects / post-processing / image / artistic. Brief generator `temp/make_briefs_2026_07_30_b18.py` reuses the b17 all-category scanner. Special wins: `prismatic-feedback-loop` had **ALL 4 slider labels wrong** ('Feedback' drove accumulationRate, 'Blur Radius' drove prism strength, 'Glow Intensity' drove rotation, 'Chromatic Spread' default 0.02 drove the feedback mix — rewired honest, blowout guards added, `accumulativeAlpha()` verbatim); `neon-topology` was **tagged mouse-driven but never read the mouse** (y/w also mislabeled — mouse lens wired, Height Scale made real, dead `alpha` var removed); `neural-resonance` had the **mask-as-color feedback bug** (spore-galaxy class — dataTextureA stored masks but C was read as color; display→A, masks→B, |curl|*10 garbage out of the display path); `fireworks-portrait-burst` had a **mouse coord units bug** (normalized [0,1] treated as pixels — bursts detonated off-screen; fixed `(p*res - res*0.5)/min(res)`) plus the flat-0.0 depth clobber (now luminance-derived); `holographic-sticker` had an **OOB palette read** (`plasmaBuffer[palIdx % 256u]` → bins 1–8); `temporal-slit-scan` (the history-ring shader, binding 13) gained a mouse scan pivot + click temporal tears with the engine ring-indexing contract verbatim. All 8 gate green (naga + bindgroup, 0 warnings, 0 extraBuffer violations), JSON contracts preserved, lists/dupes clean (1317 unique definitions), Jest 63 suites/422 pass. Briefs: `swarm-tasks/kimi-briefs-2026-07-30-b18/`; notes: `swarm-outputs/kimi-2026-07-30-b18/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 175 | `neural-nexus` | 18 | 97→167 (+70) | Click synapse bursts; spring-damper cursor [133..136]; per-neuron FFT voices (hash bin); hash/dendrite/sampleUV verbatim. |
| 176 | `prismatic-feedback-loop` | 18 | 97→176 (+79) | **All 4 mislabeled sliders rewired**; blowout clamps; click prism bursts; accumulativeAlpha + A/C symmetry verbatim; stale category header fixed. |
| 177 | `neon-topology` | 18 | 98→150 (+52) | **Mouse wired** (was tagged but unread — depth lens + rim); y/w made honest; dead `alpha` removed; click contour quakes; branchless contours verbatim. |
| 178 | `temporal-slit-scan` | 18 | 98→160 (+62) | Mouse scan pivot (tent map, branchless fallback); click temporal tears (+3 frames); per-column FFT jitter; ring indexing + binding 13 + extraBuffer[4] verbatim. |
| 179 | `spectral-distortion` | 18 | 99→163 (+64) | Spring-damper center [133..136]; click warp burst rings; R/B split from bins 3/7; fully branchless; stale comments fixed. |
| 180 | `fireworks-portrait-burst` | 18 | 100→166 (+66) | **Mouse coord units bug fixed** (off-screen bursts now on-cursor); **honest depth** (was flat 0.0 clobber); click ripple bursts; spark physics/ACES verbatim. |
| 181 | `holographic-sticker` | 18 | 100→170 (+70) | **OOB palette read guarded** (%256 → bins 1–8); spring-damper sticker [133..138]; click foil flash rings; HSV foil + depthLayeredAlpha verbatim. |
| 182 | `neural-resonance` | 18 | 100→162 (+62) | **Mask-as-color feedback fixed** (display→A, masks→B — spore-galaxy class); spring-damper mask [133..137]; click resonance rings; curlField/synapseTint verbatim. |

### Batch 17 (8 shaders) — 2026-07-30 — SMALLEST-FIRST ALL-CATEGORY EDITION

First non-generative swarm after the generative pool closeout (0 remaining excl. gen_capabilities/gen_grid). New all-category pool scanner (`temp/make_briefs_2026_07_30_b17.py`): smallest WGSL first across ALL `shader_definitions/*` categories, excluding tracker-mentioned shaders, non-empty `updatedParams`, and **multipass defs** (own `multipass` key or referenced as `nextShader` — pass I/O contracts are off-limits to generic upgrade swarms; this excluded the 3 smallest in pool, `rd-on-video-pass1/2/3`). Pool: 743 shaders. All 8 picks landed in interactive-mouse (88–97 lines, 4-param `params[]` schema). Special wins: `chronos-brush` had **3 mislabeled sliders** (y 'Freeze Decay' drove hue-shift speed, z 'Time Edge Distort' drove fade, w 'Mode (Paint/Erase)' drove opacity — now honest, default 0.9 bit-identical to legacy decay) plus click-stamp blooms into the sacred C→A history feedback; `cursor-aura` had **2 mislabeled sliders** (z 'Edge Softness' was a hidden mix, w 'Color Hue' was hidden pulse-speed with hardcoded blue — now real feather + IQ hue, default 0.5 = exact legacy blue); `kaleido-portal-interactive` had an **unclamped ~7.0 HDR border glow** (soft-knee + 1.5 cap, bass still pumps); `cyber-magnifier` had additive HUD glow with no clamp (hue-preserving 1.2 clamp pre-border); `pixel-focus` read the depth buffer but ignored it (now depth-aware focus radius); all 8 gained click-ripple interactivity (guarded `min(u32(u.config.y), 50u)`) and 6 gained spring-damper mouse glide (extraBuffer [133..139] only). All 8 gate green — **naga available in the VM this time** (full validation, not just bindgroup/workgroup), 0 warnings, 0 extraBuffer violations. JSON contracts preserved (updatedParams additive-only), lists/dupes clean (1317 unique definitions), Jest 63 suites/422 pass. Briefs: `swarm-tasks/kimi-briefs-2026-07-30-b17/`; notes: `swarm-outputs/kimi-2026-07-30-b17/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 167 | `velvet-vortex` | 17 | 88→141 (+53) | Click swirl shockwaves (twist rings + sheen); spring-damper center [133..136]; per-arm FFT phase; swirl matrix/parallax verbatim; stale category header fixed. |
| 168 | `cyber-magnifier` | 17 | 93→159 (+66) | **HDR clamp** (hue-preserving 1.2 pre-border); spring-damper lens [133..134]; click flare rings + mag pulse; 3-tap aberration verbatim. |
| 169 | `chronos-brush` | 17 | 94→144 (+50) | **3 mislabeled sliders rewired** (decay bit-identical at default; real time-edge UV wobble; honest paint/erase); click-stamp blooms; C→A history contract + HSV math verbatim. |
| 170 | `kimi_spotlight` | 17 | 94→163 (+69) | Spring-damper beam [133..138]; click light rings lift darkness; honest depth bump in spot; per-bin treble rim flicker; beam/hotspot verbatim. |
| 171 | `interactive-glitch-brush` | 17 | 95→161 (+66) | Spring-damper brush [133..136]; click glitch grenades (forced displace+invert zones); per-channel split from treble bins 5/8; fully branchless (select/step only). |
| 172 | `pixel-focus` | 17 | 95→146 (+51) | **Depth-aware focus** (radius *= mix(0.7,1.3,depth)); click clarity rings; per-bin density shimmer; branchless chromatic + alpha-luma verbatim. |
| 173 | `kaleido-portal-interactive` | 17 | 96→166 (+70) | **~7.0 HDR border tamed** (soft-knee + 1.5 cap); spring-damper portal [133..138]; click counter-rotation bursts (integrated spin phase [139]); fold math verbatim. |
| 174 | `cursor-aura` | 17 | 97→168 (+71) | **2 mislabeled sliders rewired** (real feather 0.01–0.20; IQ hue w/ 0.5=legacy blue); click aura rings; directional per-bin edge axes; 4-tap edge kernel verbatim. |

### Batch 16 (8 shaders) — 2026-07-26 — GENERATIVE EDITION 7

8-agent generative swarm, next 8 smallest with empty `updatedParams` (144–200 lines). Theme unchanged. **Uniform-semantics audit:** recon initially flagged `config.y` as delta_time (stale `docs/BINDING_CONTRACT.md`); verified against `src/renderer/UniformBuffer.ts` + `webgpu/frame.ts` — `config = [time, rippleCount, resW, resH]`, so the `min(u32(u.config.y), 50u)` ripples guard used since Batch 12 is CORRECT (docs are stale, engine source is truth). Special wins: `gen-ethereal-cyber-chrono-nebula-phoenix` had **dead audio** (`audio = u.config.y` = ripple count — rewired to real bass/treble) on an `audio-reactive`-tagged shader with only 2 controls (updatedParams mirrors exactly those 2); `liquid_magnetic_ferro` had a **dead Viscosity slider** (wired to real temporal field smoothing via A→C feedback) + center-pixel NaN normalize hardened; `bio_lenia_continuous` had a stuck spawn gate (`config.y > 0` forever after first click — now gated on mouse-down) + gained a second competing species in the free A.g channel; `bioluminescent-bloom` had **double ACES** (second pass removed); `chrono-voronoi-mycelium` had ALL 4 sliders trapped in `applyGenerativePrimaryControls` boilerplate (evicted — sliders now drive ageMix/clock/decay/voronoi-scale, defaults reproduce legacy look); `cosmic-jellyfish` computed temporal trails and **never displayed them** (now displayed at 0.6 mix) + flat-0.0 depth clobber fixed; `spec-quaternion-julia` had unclamped background alpha (~100!) + mislabeled Detail slider (now real DE iteration count); `tornado-vortex` had dead `vRadial`/`vVertical` physics (now advects debris) with its exemplary tonemap stack byte-identical. All 8 gate green (bindgroup + workgroup, 0 warnings; naga unavailable in this VM — deferred to CI), JSON contracts preserved, lists/dupes clean (1312 unique definitions), Jest 50 suites/344 pass. Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-26-b16/`; notes: `swarm-outputs/kimi-generative-2026-07-26-b16/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 159 | `gen-ethereal-cyber-chrono-nebula-phoenix` | 16 | 144→218 (+74) | **Dead audio fixed** (config.y→bass/treble); hue-clamp 2.0 + ACES; spring-damper halo [133..137]; click wing-flare rings; sdPhoenix/Clifford constants verbatim. |
| 160 | `liquid_magnetic_ferro` | 16 | 190→240 (+50) | **Dead Viscosity wired** (temporal field smoothing A→C); honest bass/treble audio; safeNormalize epsilon guards; depth clamp ≥0; Rosensweig + 1/r³ verbatim. |
| 161 | `bio_lenia_continuous` | 16 | 192→266 (+74) | **Spawn gate fixed** (mouse-down); mids audio seasons; second species in A.g with cross-feeding; click seed bombs; bell()/clamp/A.r layout verbatim. |
| 162 | `bioluminescent-bloom` | 16 | 194→259 (+65) | **Double ACES removed** + hue-clamp 1.2; per-tendril FFT bins; spring-damper nutrient [133..137]; GS constants + A packing verbatim. |
| 163 | `chrono-voronoi-mycelium` | 16 | 194→253 (+59) | **Boilerplate evicted** — sliders→ageMix/clock/decay/scale (defaults = legacy); duplicate C read + dead B store removed; per-cell FFT seed jitter; spore rings. |
| 164 | `cosmic-jellyfish` | 16 | 195→267 (+72) | **Dead trails displayed** (0.6 mix, decay 0.96, clamp 1.2); honest hit-distance depth; bass pulse/treble tentacles; IQ palette + ACES; map() SDF verbatim. |
| 165 | `spec-quaternion-julia` | 16 | 195→246 (+51) | **Detail slider real** (DE iters 8–16); bg alpha clamped ≤1; log(r) guarded; bass morph/mids c.w drift; orbit-trap IQ palette; quaternion math verbatim. |
| 166 | `tornado-vortex` | 16 | 200→256 (+56) | **Dead physics activated** (vRadial/vVertical advect debris); click satellite vortices; per-bin treble lightning; Rankine/blackbody/OkLab/tonemap byte-identical. |

### Batch 15 (8 shaders) — 2026-07-26 — GENERATIVE EDITION 6

8-agent generative swarm, next 8 smallest with empty `updatedParams` (131–190 lines). Theme unchanged: formalize `updatedParams` from EXISTING params (preset contract), kill fake/boilerplate mappings, +2–3 tailored techniques, +50–90 lines. Special wins: `gen-crystalline-nebula-weaver-void-spider` had **dead audio** (`u.ripples[0].x` masquerading as a plasmaBuffer proxy — rewired to real bass/treble) plus fake sin/dot fbm → real value-noise fbm and its non-standard `controls[]` JSON schema preserved while gaining `updatedParams`; `gen-holographic-fracture` had the `zoom_config.xy` mouse bug (x = Time!) — swizzle fixed, honest crack-proximity depth replaces flat 0.0 (`supportsDepth: true` now earned); `liquid_crystal_birefringence` had `audioPulse = zoom_config.w` (mouse-down mislabeled as audio) — now bass→Frederiks compression, mids→twist, treble→Schlieren sparkle + 8-bin Newton-ring fringes; `kimi_quantum_field` had a **double tonemap** (Reinhard+pow stacked under ACES — removed, mids restored) and dead `psi()` deleted; `kimi_fractal_dreams` had a latent NaN (`cdiv` near-zero denom — epsilon-guarded); `supernova-core` kept its premultiplied alpha compositor byte-identical while rays became spectrum-driven with Sedov-Taylor click rings; `lava-lamp-blobs` aspect-corrected its mouse and gained per-blob FFT voices with its sim-state dataTextureA packing untouched. All 8 gate green (bindgroup + workgroup, 0 warnings; naga binary unavailable in this VM — deferred to CI), JSON contracts preserved, lists/dupes clean (1312 unique definitions), Jest 50 suites/344 pass. Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-26-b15/`; notes: `swarm-outputs/kimi-generative-2026-07-26-b15/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 151 | `gen-crystalline-nebula-weaver-void-spider` | 15 | 131→221 (+90) | **Dead audio fixed** (ripples[0].x→plasmaBuffer bass/treble); real 4-octave fbm + IQ palette; hue-clamp 2.0 + ACES; controls[] schema preserved. |
| 152 | `gen_psychedelic_spiral` | 15 | 142→199 (+57) | Per-bin FFT drives superformula n2/n3; click petal-burst rings; hsv2rgb→IQ cosine palette + hue-clamp 1.2; historyUV transform chain verbatim. |
| 153 | `liquid_crystal_birefringence` | 15 | 181→269 (+88) | **Fake audio fixed** (mouse-down→real FFT); 8-bin Newton-ring fringes; click voltage fronts; spring-damper defect core [133..134]; wavelength/Mueller math verbatim. |
| 154 | `gen-holographic-fracture` | 15 | 183→267 (+84) | **Mouse bug fixed** (xy→yz); honest crack depth write; click crack fronts; spring-damper origin [133..135]; per-crack FFT iridescence; chunk library verbatim. |
| 155 | `kimi_quantum_field` | 15 | 184→244 (+60) | **Double tonemap removed** (Reinhard out, ACES kept); spectrum interferometer (per-bin source amps); dead psi() deleted; mislabeled sliders made honest (defaults = legacy look). |
| 156 | `kimi_fractal_dreams` | 15 | 186→276 (+90) | **NaN guard** on cdiv denom (1e-4); spring-damper Julia morph [133..136]; click zoom pulses; orbit-trap IQ palette + per-bin treble filaments; Burning-Ship core verbatim. |
| 157 | `supernova-core` | 15 | 187→275 (+88) | Spectrum-driven rays (per-bin plasmaBuffer); click Sedov-Taylor rings (r~t^0.4); spring-damper companion star [133..134]; premultiplied alpha compositor byte-identical. |
| 158 | `lava-lamp-blobs` | 15 | 190→250 (+60) | Aspect-corrected spring-damper mouse [133..136]; per-blob FFT voices + mids shimmer + treble rim sparkle; click heat-injection blobs; sim-state dataTextureA packing verbatim. |

### Batch 14 (8 shaders) — 2026-07-22 — GENERATIVE EDITION 5

Interrupted Kimi swarm recovered and completed. All eight shader/definition pairs were present; seven had agent notes and `spore-galaxy` was the unrecorded cutoff. The recovery pass verified the saved-preset contract, completed the missing note, regenerated shader lists, and closed the tracker. Special wins: `gen-bioelectric-pulse` fixes inverted mouse semantics and adds persistent kick envelopes; `gen_grok4_life` replaces the hardcoded 2048 wrap with resolution-aware toroidal sampling; `spore-galaxy` fixes mask-as-color feedback by moving display color to dataTextureA and masks to dataTextureB; `gravito-phononic-accretion` turns Lensing Strength into real UV deflection. Target gate 8/8 green (naga + bindgroup, 0 warnings), JSON contracts preserved, lists/dupes clean (1310 unique definitions), Jest 49 suites/339 pass. Full-fleet Naga scan is 1314/1315; the sole failure is the unrelated, unmodified `gen-luminescent-aether-plasma-astro-axolotl.wgsl`. Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-22-b14/`; notes: `swarm-outputs/kimi-generative-2026-07-22-b14/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 143 | `gen-bioelectric-pulse` | 14 | 180→245 (+65) | Correct mouse-down/UV semantics; honest dataTextureC reaction trails; kick mega-pulse envelope in safe extraBuffer state. |
| 144 | `gen_grok4_life` | 14 | 176→251 (+75) | Resolution-aware toroidal wrap; FFT ecosystem zones; age-based prey palette; extinction bloom monitor. |
| 145 | `gen_reaction_diffusion` | 14 | 179→234 (+55) | Treble micro-stimulus; click spiral dipoles; disentangled diffusion control; raw signed sim state preserved. |
| 146 | `gravito-phononic-accretion` | 14 | 179→248 (+69) | True gravitational UV lensing; diffusion-controlled persistence; treble relativistic jet envelope. |
| 147 | `neural-mandala` | 14 | 177→235 (+58) | Mouse spring re-centering; click shock rings; per-ring spectrum; complexity-driven sub-symmetry fold. |
| 148 | `phosphorescent-jellyfish` | 14 | 180→263 (+83) | Hue-preserving HDR clamp + ACES; per-jelly spectrum; nearest-jelly click propulsion dart. |
| 149 | `spore-galaxy` | 14 | 179→229 (+50) | Feedback semantics fixed (display→A, masks→B); per-arm FFT voices; ripple-driven spore bursts. |
| 150 | `topological-acoustic-knots` | 14 | 180→247 (+67) | Honest defect-density quench; annihilation cascades/census pulse; mids-driven persistent polarizer. |

### Batch 13 (8 shaders) — 2026-07-22 — GENERATIVE EDITION 4

8-agent generative swarm, next 8 smallest with empty `updatedParams` (171–175 lines). Theme unchanged: formalize `updatedParams` from EXISTING params (preset contract), kill boilerplate mappings, +2–3 tailored techniques, +50–90 lines. Special wins: `retro_phosphor_dream` had a **latent bug** (`audioPulse` bound to MouseDown, plasmaBuffer never read — rewired to bass); `gen_kimi_nebula` + `gen_hyper_warp` had placeholder param1–4 + `applyGenerativePrimaryControls` boilerplate (sliders now drive real constants, defaults reproduce legacy look); `gen_hyper_warp` feedback (×1.1 sharpen @ 0.95 mix) stabilized with hard 1.2 pre-tint clamp; `gen-neural-dust` mouse coords fixed to engine convention (`zoom_config.yz`). Sim-state feedback layouts (coral-growth envelope, crystalline-fracture stress) preserved verbatim. All 8 gate green (naga + bindgroup, 0 warnings), JSON contracts preserved, lists/dupes clean (1310 defs), Jest 49 suites/339 pass. Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-22-b13/`; notes: `swarm-outputs/kimi-generative-2026-07-22-b13/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 135 | `gen-neural-dust` | 13 | 171→224 (+53) | Comet-trail feedback (clamp 1.2), per-cell plasmaBuffer[1..8] band energy, depth parallax; mouse coords fixed to zoom_config.yz. |
| 136 | `gen_kimi_nebula` | 13 | 172→227 (+55) | Boilerplate evicted — sliders→density/time-multiplier/noise-scale/star-cutoff (defaults = legacy); mids/treble layer drift; extra fbm3 warp. |
| 137 | `gen_hyper_warp` | 13 | 173→223 (+50) | stabilizeHistory() hard 1.2 clamp + soft-knee, flow-advected feedback, boilerplate evicted (warp amp/time/palette/feedback-mix). |
| 138 | `supernova-remnant` | 13 | 174→232 (+58) | Blackbody age ramp (A-alpha age accumulator), click detonation rings via ripples[], inertial bass kicks; chromatic feedback untouched. |
| 139 | `coral-growth` | 13 | 175→241 (+66) | Mids-gated 2nd-order twigs, per-branch spectralBandEnergy() tips, clamped residue trail; bass-envelope sim state verbatim. |
| 140 | `crystalline-fracture` | 13 | 175→238 (+63) | Click stress rings (ripples[]), fbm weak grain boundaries, crack memory 0.98 (<1.0) + min(stress,6) clamp; stress/connectivity layout kept. |
| 141 | `retro_phosphor_dream` | 13 | 175→252 (+77) | **Bug fix**: audioPulse MouseDown→bass; treble scanline jitter + hum-bar roll; mouse curvature + degauss wobble (extraBuffer[133]). |
| 142 | `spec-analytic-noise-flow` | 13 | 175→231 (+56) | Iso-contour ridges from free analytic gradient (treble-sharpened), bass advection surge, temporal velocity smoothing; quintic math byte-identical. |

### Batch 12 (8 shaders) — 2026-07-22 — GENERATIVE EDITION 3

8-agent generative swarm, next 8 smallest (160–169 lines). Theme: formalize `updatedParams` from EXISTING params (preset contract) + 2–3 tailored techniques +50–90 lines. Special wins: `generative-turing-veins` had 4 **dead sliders** (WGSL never read zoom_params — wired for real); `bubble-chamber` z-param double-duty split + backwards Speed mapping fixed; `emergent-calligraphic-weave` boilerplate controls evicted. **Cross-batch fix:** during completion, discovered engine writes 128 FFT bins to `extraBuffer[5..132]` every frame audio is active — 9 shaders from Batches 10–12 stored persistent state there (plus `holographic-crystal` writing reserved [0]). All remapped to the safe zone `[133..255]` and re-gated 9/9 green. Index map documented in `agents/WGSL_BUILTINS_GENERATIVE.md`. All 8 gate green, JSON contracts preserved, lists/dupes clean (1309 defs), Jest 332 pass. Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-22-b12/`; notes: `swarm-outputs/kimi-generative-2026-07-22-b12/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 127 | `emergent-calligraphic-weave` | 12 | 160→215 (+55) | Boilerplate evicted — sliders→real brush constants (viscosity/dry-brush/chaos); curl-noise stroke flow; treble edge sizzle. |
| 128 | `bubble-chamber` | 12 | 163→229 (+66) | Bragg-curve ionization falloff, Lorentz point-vortex mouse deflection, z-param double-duty split, backwards Speed fixed, clamp 1.2. |
| 129 | `generative-turing-veins` | 12 | 165→244 (+79) | **Dead sliders wired**: scale→kernel radius, feed→GS regime 0.03–0.07, glow→ridge gain; bass nutrient wave; click colony seeding; state [133..136]. |
| 130 | `molten-gold` | 12 | 165→234 (+69) | True Planckian blackbody ramp (Tanner-Helland, 1337K melt point), fresnel flow-ridge specular, bass heat waves (+420K), clamp 1.2. |
| 131 | `phase-memory-weave` | 12 | 165→233 (+68) | Opalescent phase-gradient iridescence (0.3), memory clamp+decay (anti-latch), click thermal ring [133..136]; optimizations preserved. |
| 132 | `atmos_volumetric_fog` | 12 | 166→233 (+67) | 10-step mouse-anchored god-ray march (fbm-occluded), 2nd fbm density breakup, shaft-revealed treble dust motes, clamp 1.2. |
| 133 | `mycelium-network` | 12 | 166→239 (+73) | Click nutrient pulse packets [133..136], growth tropism toward cursor, bass heartbeat, worley strand thickness; anti-moire LOD intact. |
| 134 | `gen_julia_set` | 12 | 169→254 (+85) | Bass Lissajous c-morph (mouse overrides), interior filament detail, 2-sample hash-jitter AA; smooth-iteration + 3 orbit traps intact. |

### Batch 11 (8 shaders) — 2026-07-22 — GENERATIVE EDITION 2

8-agent generative swarm, next 8 smallest with empty `updatedParams` (gen_capabilities skipped — system-monitor demo). Theme same as Batch 10: formalize `updatedParams` from EXISTING params (preset contract), +2–3 tailored techniques, +50–90 lines. **Bonus: fixed a real feedback bug in `gen_wave_equation`** (solver read height/velocity from dataTextureC but wrote finalColor to dataTextureA → feedback carried color, not state; now state→A, plus NaN-kill for stale color). Also revived dead sliders (plasma-orb `arcChaos`, holo_interference `depthWeight`). All 8 gate green (naga + bindgroup, 0 warnings), JSON contracts preserved, lists/dupes clean (1309 defs). Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-22-b11/`; notes: `swarm-outputs/kimi-generative-2026-07-22-b11/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 119 | `gen_cyclic_automaton` | 11 | 138→200 (+62) | Wavefront leading-edge tracer, treble ignition sparks, directional mouse painting (extraBuffer[5..7]); GH state machine verbatim. |
| 120 | `holographic_interference` | 11 | 144→194 (+50) | Treble speckle grain, thin-film IQ palette tint, mouse-tilt parallax, carrier fringe; dead depthWeight slider wired; ACES deduped. |
| 121 | `holographic-crystal` | 11 | 148→219 (+71) | Phase dither anti-moiré, worley facet normals (cut-glass), treble glints, true chromatic dispersion on slider. |
| 122 | `gen_wave_equation` | 11 | 149→215 (+66) | **Feedback bug fixed** (sim state→dataTextureA, NaN-kill sanitizer), 9-point Laplacian, click droplets + bass rain; KG/SG term preserved. |
| 123 | `plasma-orb` | 11 | 149→223 (+74) | Worley F2−F1 arc branching (dead arcChaos wired), spring-damper orb drift (extraBuffer[5..8]), mids corona shimmer, glow clamp 1.2; ACES deduped. |
| 124 | `plasma-jet-stream` | 11 | 152→214 (+62) | Divergence-free curl perturbation, analytic bass surge wave, chromatic shear fringe at jet boundaries. |
| 125 | `sacred-geometry-torus` | 11 | 155→219 (+64) | Phyllotaxis golden-angle lattice (Phi Layers), per-strand cosine hue cycling (0.35), trail clamp 1.2, crossing bloom. |
| 126 | `acoustic-string-theory` | 11 | 157→239 (+82) | Click-to-pluck ring-down (extraBuffer[5],[10..13]), spring-damper gravity well [6..9], per-string audio spectral weighting, clamp 1.2. |

### Batch 10 (8 shaders) — 2026-07-22 — GENERATIVE EDITION

8-agent generative swarm. Pool scan: 99 generative shaders with empty/missing `updatedParams`; took the 8 smallest never-in-any-batch. Theme: **formalize `updatedParams` using the EXISTING JSON param ids/defaults (saved-preset contract)** — all 8 already read `u.zoom_params.x–w` in WGSL but had no UI sliders wired — plus rewire generic boilerplate mappings (`applyGenerativePrimaryControls` etc.) to shader-specific constants, +2–3 techniques each, +50–90 lines. All 8 pass `wgsl_precommit_gate.py` (naga + bindgroup, 0 warnings), JSONs parse with param contract preserved, lists/dupes clean (1309 defs), Jest 332 pass. Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-22/`; notes: `swarm-outputs/kimi-generative-2026-07-22/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 111 | `fire_smoke_volumetric` | 10 | 117→181 (+64) | Worley ember sparks (temp-gradient tinted), treble edge flicker, smoke feedback clamp 1.2; sliders→heat/density+trail/depth floor/turbulence. |
| 112 | `multi-scale-evolutionary-cellular-gardens` | 10 | 124→174 (+50) | 8-neighbor diffusion (dist-correct weights), colony-border bioluminescence, per-epoch rule drift; boilerplate controls→real sim constants. |
| 113 | `recursive-ancestral-terrains` | 10 | 124→182 (+58) | Ridged-fbm crest octave, IQ palette lineage strata (mix 0.3), radial bass mutation waves from mouse; sliders→real lineage/mutation constants. |
| 114 | `neural-synapse-web` | 10 | 126→205 (+79) | Spring-damper mouse attractor + click pulse ring (extraBuffer[133..141], reserved 0..4 untouched), treble synapse sparkle masked by signal. |
| 115 | `magnetic-flux-garden` | 10 | 128→197 (+69) | Curl-noise flux-line weave, IQ palette bloom (mix 0.3), trail clamp 1.2; sliders→line count/dipole gain/curl amp/bloom gain. |
| 116 | `generative-psy-swirls` | 10 | 129→189 (+60) | fbm domain-warp before polar twist (breathing arms), mids per-layer hue fan, layer-memory clamp 1.2; Frequency also drives warp. |
| 117 | `4d-projection-dream-weavers` | 10 | 132→221 (+89) | Spring-damper 4D slice angles (extraBuffer[5..8]), Worley dream-dust (treble, depth-faded), dimension tint 0.25; fixed unused `detail` bug. |
| 118 | `symbiotic-light-propagation-networks` | 10 | 133→185 (+52) | Frame-stamped seed rings (extraBuffer[5..9]), bass glow→radial wave from seed, accumulation clamp 1.2; sliders→growth/transmission/balance/seed. |

### Batch 9 (8 shaders) — 2026-07-21

8-agent swarm on the next-smallest unclaimed pool shaders. Theme: **wire 4 slider params (`u.zoom_params.x–w`) into shaders whose `updatedParams` was empty** + 2–3 techniques each (fbm/worley, IQ cosine palettes, plasmaBuffer audio bands, spring-dampers, feedback clamps). All 8 pass `wgsl_precommit_gate.py` (naga + bindgroup), JSONs parse, lists/dupes clean, Jest 321 pass. Briefs: `swarm-tasks/kimi-briefs-2026-07-21/`; notes: `swarm-outputs/kimi-upgrade-2026-07-21/`. Manifest now 1308 shaders.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 103 | `bitonic-sort` | 9 | 241→304 (+63) | 4 sliders (Sort Threshold/Warp Amplitude/Edge Glow/Sort Length); bass-lowered luma gate, pre-sort FBM warp, sentinel-key span edge glow. Sort network byte-for-byte untouched. |
| 104 | `temporal-rgb-smear` | 9 | 220→296 (+76) | 4 sliders; spring-damper mouse velocity bends smear, treble sparkle grain, feedback blowup clamp (luma-echo-warp lesson). |
| 105 | `elastic-chromatic` | 9 | 207→297 (+90) | 4 sliders; spring-damper overshoot mouse, click shockwave ring, IQ cosine palette over blackbody grade. |
| 106 | `data-slicer-interactive` | 9 | 189→240 (+51) | 4 sliders; branchless fBM slice jitter, bass/mids band fix, click shockwave honoring per-ripple strength. |
| 107 | `pixel-stretch-cross` | 9 | 223→283 (+60) | 4 sliders; velocity-steered H↔V stretch axis, bass-pulse amplitude, HDR crossing bloom pre-ACES. |
| 108 | `interactive-magnetic-ripple` | 9 | 223→302 (+79) | 4 sliders; Worley F2−F1 field lines, spring-damped oscillator envelope, treble crest sparkle. |
| 109 | `luma-pixel-sort` | 9 | 207→262 (+55) | 4 sliders; param sort angle, bass threshold drop, cosine palette span tint. 25-comparator network + early exits intact. |
| 110 | `pixel-depth-sort` | 9 | 197→252 (+55) | 4 sliders; param sort radius (default = old look), mids gain, span-seam chromatic fringe, feedback clamp, pre-ACES dither. |

### Batch 8b (6 shaders) — 2026-07-19

6-agent swarm on the smallest single-pass shaders after the v6.0 queue emptied. Recorded late (was logged only in `memory/2026-07-19.md`). Gate 6/6 green.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 97 | `ring_slicer` | 8b | — | 2–4 techniques each: fbm/curl/worley, IQ cosine palettes, plasmaBuffer audio, mouse-down wiring. Gate green. |
| 98 | `pixel-sort-explorer` | 8b | — | Same recipe; gate green. |
| 99 | `hex-mosaic` | 8b | — | Same recipe; gate green. |
| 100 | `luma-slice-interactive` | 8b | — | Same recipe; gate green. |
| 101 | `spectral-smear` | 8b | — | Same recipe; gate green. |
| 102 | `luma-echo-warp` | 8b | — | Same recipe + **fixed real feedback blowup** (sparkle into dataTextureA unclamped at 0.99 decay → 15–30× runaway; clamped pre-tint at 1.2). |

### Batch 8 (4 new generative geometry shaders) — 2026-07-12

Colorful polyhedral geometry pass — spectral palettes, neon edges, iridescent surfaces, mouse 3D orbit, audio reactivity. Manifest now 1296 shaders.

| # | Shader | Batch | Lines | Description |
|---|--------|-------|-------|-------------|
| 93 | `gen-rainbow-icosahedron-cascade` | 8 | ~168 | Nested icosahedral wireframe shells with spectral edge glow. |
| 94 | `gen-chromatic-zonohedron` | 8 | ~130 | Rhombic zonohedron facet tiling with rainbow cells and neon edges. |
| 95 | `gen-prismatic-mobius-helix` | 8 | ~132 | Möbius-strip helix with thin-film iridescence. |
| 96 | `gen-neon-stellated-octahedron` | 8 | ~160 | Star tetrahedron with neon rainbow edges and kaleidoscopic symmetry. |

### Batch 7 (5 shaders) — 2026-07-12

Mixed pass: 3 remaining small fireworks upgraded to Batch 6 optimizer standard (hex-bokeh, star field, temporal persistence, semantic alpha); 1 new generative firework created; 1 visual-effect upgrade. All pass `naga` and `wgsl_precommit_gate.py`; manifest now 1292 shaders.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 88 | `gen-fireworks-strobe-shell` | 7 | 123→153 (+30) | Hex-bokeh flash cores, star field, camera blend, improved persistence/alpha. |
| 89 | `gen-fireworks-crossette` | 7 | 116→153 (+37) | Hex-bokeh arm sparks, GRAVITY physics, star field, semantic alpha. |
| 90 | `gen-fireworks-comet-trail` | 7 | 116→141 (+25) | Hex-bokeh head/trail, unified sparkPos gravity, star field, persistence. |
| 91 | `gen-fireworks-dahlia-burst` | 7 | NEW→189 | **New shader.** Flat dahlia-disk petal rows, layered timing, mouse burst, audio reactivity. |
| 92 | `phantom-lag` | 7 | 105→137 (+32) | Spring-damper bass, chromatic echo taps, ACES tone map, vec4 alpha preservation. |

### Batch 6 (16 generative shaders) — 2026-07-12

4-agent Kimi generative swarm: 4 fireworks optimizers, 4 visualists, 4 interactivists, 4 algorithmists. Expanded undersized generative shaders by **+52 to +115 lines** with canonical 13-binding compute pipeline, semantic alpha, audio/depth reactivity, and role-specific techniques (SDF/orbit traps, Fresnel/OkLab, spring-damper mouse, hex-bokeh fireworks). Post-dispatch fixes: `target` reserved keyword → `goal` in spring_damper helpers; `hash22` swizzle typo `p.yzx` → `p3.yzx`; completed `gen-sierpinski-tetrahedron` upgrade Kimi had not started. All 16 pass `naga` and `wgsl_precommit_gate.py`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 72 | `gen-ethereal-cyber-chrono-nebula-phoenix` | 6 | 55→144 (+89) | Clifford attractor orbit trap, phoenix SDF, domain-warped nebula, audio fracture. |
| 73 | `gen-prismatic-cyber-aurora-astral-dragonfly` | 6 | 168→241 (+73) | Dragonfly SDF, Worley layers, strange-attractor crystals, iridescent orbit trap. |
| 74 | `gen-physarum-sacred-geometry` | 6 | 190→242 (+52) | Curl-noise agents, hex sacred mask, Mandelbrot trap, extraBuffer simulation. |
| 75 | `gen-sierpinski-tetrahedron` | 6 | 197→262 (+65) | 2nd-order domain warp, curl advection, Worley accent, Fresnel sheen, spring-damper audio. |
| 76 | `gen-luminescent-aether-plasma-nebula-koi` | 6 | 199→301 (+102) | Fresnel rim, OkLab mixing, chromatic aberration, blackbody temperature. |
| 77 | `gen-luminescent-quantum-glass-phoenix-egg` | 6 | 197→306 (+109) | Glass SDF refraction, thin-film iridescence, quantum orbit trap, split-tone. |
| 78 | `gen-ethereal-chrono-plasma-void-manta` | 6 | 174→289 (+115) | Manta SDF glide, plasma void FBM, temporal feedback, hue-preserve clamp. |
| 79 | `gen-quantum-fluorescent-nebula-anemone` | 6 | 171→260 (+89) | Anemone tentacle SDF, fluorescent palette, domain-warped nebula, vignette. |
| 80 | `gen-cybernetic-mycelium-neural-web` | 6 | 191→249 (+58) | Spring-damper audio, click-seeded mutation, mycelial attraction, temporal feedback. |
| 81 | `gen-neural-bioluminescence-matrix` | 6 | 191→260 (+69) | Neural graph Voronoi, click shockwave, gravity well, spring-damper envelopes. |
| 82 | `gen-showcase-nebula-core` | 6 | 196→250 (+54) | Gravity-well mouse, Balmer-series palette, click bursts, spring-damper audio. |
| 83 | `gen-worley-cellular-noise` | 6 | 171→224 (+53) | Spring-damper reactivity, mouse warp, cellular Worley layers, temporal feedback. |
| 84 | `gen-fireworks-fan-shell` | 6 | 102→169 (+67) | Hex-bokeh fan glow, mouse personal fan, bass energy, temporal persistence. |
| 85 | `gen-fireworks-horse-tail` | 6 | 104→170 (+66) | Hex-bokeh brocade trails, gravity fall, mouse burst, audio tail length. |
| 86 | `gen-fireworks-kamuro-gold` | 6 | 111→173 (+62) | Hex-bokeh gold droplets, mouse cascade, branchless shell timing. |
| 87 | `gen-fireworks-ring-shell` | 6 | 107→170 (+63) | Hex-bokeh ring glow, mouse ring, bass radius, gravity secondary sparks. |

### Batch 4 (10 shaders) — 2026-05-17

Full rewrites of raw Phase A/B shaders: added `plasmaBuffer` audio reactivity, replaced hardcoded `vec4(..., 1.0)` with meaningful alpha, converted `if` blocks to branchless `select()`/`mix()`, added `writeDepthTexture` + `dataTextureA` writes.

| # | Shader | Batch | Changes Made |
|---|--------|-------|--------------|
| 46 | `electric-contours` | 4 | Sobel edge detection with bass-driven glow, mids spark multiplier, meaningful alpha from edge strength + spark + base texture alpha. |
| 47 | `luma-force` | 4 | Branchless attract/repel via `select()`, luma-weighted force, mids-driven swirl distortion, alpha blends toward 1.0 near mouse. |
| 48 | `contour-flow` | 4 | Gradient-perpendicular flow with bass-driven speed, mids highlight tint, alpha from flow intensity + mouse factor + source alpha. |
| 49 | `magnetic-edge` | 4 | Branchless edge pull with `select()` displacement, bass boost on pull strength, mids glow tint, alpha from glow + influence. |
| 50 | `pixel-stretch-interactive` | 4 | Branchless mode selection (Right/Left/Cross), chromatic aberration with mids scaling, jitter gated by `select()`, alpha boosted on stretch. |
| 51 | `magnetic-pixels` | 4 | Branchless repulsion with `select()`, bass force scaling, mids chromatic tint, chaos noise gated by `select()`, alpha from displacement magnitude. |
| 52 | `spirograph-reveal` | 4 | Guilloche pattern reveal with bass-driven rotation speed, mids background boost, alpha blends pattern mask with source texture alpha. |
| 53 | `psychedelic-noise-flow` | 4 | Per-channel noise displacement with bass speed scaling, mids distortion strength, clamped UV sampling, alpha from displacement + mouse influence. |
| 54 | `liquid-lens` | 4 | Spherical lens refraction with chromatic aberration, branchless rim darkening/specular via `select()`, bass strength boost, alpha from lens mask. |
| 55 | `polka-wave` | 4 | Halftone dots with wave ripple from mouse, bass amplitude boost, alpha preserves source texture in dots + transparent background. |

### Batch 5 (16 shaders) — 2026-07-12

4-agent Kimi swarm pass on unclaimed small shaders. First pass compacted code too aggressively; a retry enforced original-functionality preservation and **+30 to +80 line expansion**. Each shader was assigned a primary role (Algorithmist / Visualist / Interactivist / Optimizer), upgraded with canonical 13-binding compute pipeline, semantic alpha, audio/depth reactivity, and ACES + IGN dither where appropriate. All 16 pass `naga` and `wgsl_precommit_gate.py`; `generate_shader_lists.js` and `check_duplicates.js` are clean.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 56 | `hyb-kaleidoscope-pulse` | 5 | 112→167 (+55) | Domain-warped FBM, SDF star, strange-attractor orbit-trap, phase kaleidoscope rings, chromatic split. |
| 57 | `ambient-liquid` | 5 | 141→195 (+54) | Curl-noise advection, reaction-diffusion spots, SDF metaball ink, anisotropic specular, vignette/film grain. |
| 58 | `rain-ripples` | 5 | 126→186 (+60) | Domain-warped FBM micro-ripples, Voronoi raindrops, caustic refraction, wet-area SDF, thin-film rainbow. |
| 59 | `complex-exponent-warp` | 5 | 129→209 (+80) | Dual-layer domain-warped FBM, Julia orbit-trap, Newton fractal coloring, SDF cardioid, stereo chromatic split. |
| 60 | `neon-edge-radar` | 5 | 102→141 (+39) | Fresnel rim, volumetric fog, hue-preserve clamp, blackbody temperature. |
| 61 | `holographic-glitch` | 5 | 95→128 (+33) | Fresnel rim, split-tone, film grain, hue-preserve clamp. |
| 62 | `hyb-iridescent-fbm-glow` | 5 | 85→147 (+62) | Chromatic aberration, Fresnel rim, OkLab mixing. |
| 63 | `thermal-vision` | 5 | 102→143 (+41) | Blackbody temperature, split-tone, hue-preserve clamp, vignette. |
| 64 | `mouse-ink-bleed` | 5 | 129→202 (+73) | Spring-damper mouse follow, gravity well, click shockwave, vortex ink splash, temporal feedback. |
| 65 | `interactive-voronoi-lens` | 5 | 132→209 (+77) | Spring-damper follow, gravity on cell centers, neon shockwave, Voronoi lens distortion. |
| 66 | `cyber-rain` | 5 | 130→205 (+75) | Bass-driven intensity, bending streaks/drops, thunder flash, parallax depth layers, temporal persistence. |
| 67 | `optical-feedback` | 5 | 148→228 (+80) | Lagging feedback center, self-evolving hue phase, gravity well, click burst, emergent feedback loop. |
| 68 | `focal-pixelate` | 5 | 77→152 (+75) | Hex-bokeh sampling, anti-moiré LOD bias, shared-memory tiling hint, branchless focus select, depth compositing. |
| 69 | `neon-edge-diffusion` | 5 | 87→141 (+54) | Anti-moiré LOD, hex-bokeh glow, early-exit ripple gating, branchless select/mix, depth compositing. |
| 70 | `radial-hex-lens` | 5 | 94→163 (+69) | Fractional hex LOD, weighted hex-bokeh sampling, shared-memory tiling hint, depth-aware focal plane. |
| 71 | `temporal-halation-freeze` | 5 | 78→127 (+49) | LOD-biased hex-bokeh bloom, early-exit dark-pixel fallback, shared-memory tiling hint, branchless warm/cool selection. |

### Batch 3 (10 shaders) — 2026-05-17

Completion pass on Phase A/B shaders: added `dataTextureA` temporal feedback writes, `upgraded-rgba` header tags, and fixed `luma-slice-interactive` scalar→vec4 depth write bug.

| # | Shader | Batch | Changes Made |
|---|--------|-------|--------------|
| 36 | `volumetric-god-rays` | 3 | Added `dataTextureA` write with ray-accumulated RGBA. Header now tagged `upgraded-rgba`. |
| 37 | `virtual-lens` | 3 | Added `dataTextureA` write with chromatic-aberration lens RGBA. Header now tagged `upgraded-rgba`. |
| 38 | `cyber-lattice` | 3 | Added `dataTextureA` write with grid-glow RGBA. Header now tagged `upgraded-rgba`. |
| 39 | `luma-slice-interactive` | 3 | Fixed `textureStore(writeDepthTexture, coords, depth)` scalar bug → `vec4<f32>(depth, 0.0, 0.0, 0.0)`. Added `dataTextureA` write. Header now tagged `upgraded-rgba`. |
| 40 | `neon-ripple-split` | 3 | Added `dataTextureA` write with neon-split RGBA. Header now tagged `upgraded-rgba`. |
| 41 | `dynamic-halftone` | 3 | Added `dataTextureA` write with halftone-dot RGBA. Header now tagged `upgraded-rgba`. |
| 42 | `neon-flashlight` | 3 | Added `dataTextureA` write with edge-emission RGBA. Header now tagged `upgraded-rgba`. |
| 43 | `quantum-field-visualizer` | 3 | Added `dataTextureA` write with quantum-chaos RGBA. Header now tagged `upgraded-rgba`. |
| 44 | `holographic-edge-ripple` | 3 | Added `dataTextureA` write with holographic-foil RGBA. Header now tagged `upgraded-rgba`. |
| 45 | `spectrogram-displace-pass2` | 3 | Added `dataTextureA` write with spectrogram-displaced RGBA. Header now tagged `upgraded-rgba`. |

### Batch 2 (10 shaders) — 2026-05-17

| # | Shader | Batch | Changes Made |
|---|--------|-------|--------------|
| 26 | `pixel-sort-radial` | 2 | Upgraded to 94 lines. Branchless `select()`/`mix()` logic, `hash22()` jitter, chromatic aberration (R/G/B offset sampling), audio reactivity (bass scales stretch, mids drive twist, click triggers 2.5x burst), HDR bloom alpha, writes `dataTextureA` for temporal feedback. |
| 27 | `pixel-drag-smear` | 2 | Upgraded to 119 lines. Added curl noise jitter, ACES tone mapping, warm/cool velocity tint, `lumaMix()` helper, alpha boost from influence, `dataTextureA` writeback. |
| 28 | `thermal-touch` | 2 | Upgraded to 88 lines. Branchless thermal palette via `smoothstep`+`mix()`, `hash21()` shimmer scaled by mids, bass-driven pulse, meaningful alpha (cold=0.5, hot=1.0), colorMode preserves original texture alpha. |
| 29 | `luma-magnetism` | 2 | Upgraded to 87 lines. Anisotropic RGB stretch, chromatic aberration, `curl()` noise jitter, bass boosts strength 2x, mids drive swirl, click shockwave (`0.15/dist`), glow halo, safe normalize guard via `select()`. |
| 30 | `pixel-scattering` | 2 | Upgraded to 84 lines. Branchless `smoothstep` radius, time-breathing radius, depth-based scatter boost, directional glow, bass/mids reactivity, click burst 3x, `size` param controls concentration alpha. |
| 31 | `circular-pixelate` | 2 | Upgraded to 106 lines. Depth-based dot sizing, audio pulse on radius, per-cell `hash12()` tint, transparent gaps via `mix(vec4(0.0), dot_color, mask)`, ripple click boost, inner edge highlight. |
| 32 | `mirror-drag` | 2 | Upgraded to 83 lines. Branchless `select()` mirror logic, kaleidoscope mode, neon seam glow, bass-driven axis oscillation, mids-driven sector rotation, click flip pulse, edge feathering via `smoothstep`. |
| 33 | `hypnotic-spiral` | 2 | Upgraded to 86 lines. Branchless `hsv2rgb` via `mix()`+`fract()`, secondary counter-rotating spiral, `hash12` sparkle, bass drives rotation, mids drive color cycling, click reverses direction, ripple distortion. |
| 34 | `pixelate-blast` | 2 | Upgraded to 83 lines. Ripple boost on pixel size, audio radius expansion, chromatic aberration at block edges, scanline + vignette, color crunch quantization, click shockwave. |
| 35 | `temporal-distortion-field` | 2 | Upgraded to 105 lines. Temporal feedback via `dataTextureC` read + `dataTextureA` write, FBM warp twist, bass-driven warp strength, mids-driven ghosting, treble shimmer, depth-scaled field radius, warm/cool temperature shift, click freeze. |

### Batch 1 (25 shaders)

| # | Shader | Batch | Changes Made |
|---|--------|-------|--------------|
| 1 | `rgb-glitch-trail` | B | Fixed workgroup size `(8,8,1)`. `dataTextureA` now stores full RGBA trail color instead of `vec4(intensity,0,0,1)`. Replaced naive `.r`/`.b` channel sampling with `vec4` blending using `glitch_weight = intensity * color.a`. |
| 2 | `chroma-shift-grid` | B | Fixed workgroup size. Replaced separate `R/G/B` sampling with full `vec4` blending where `blend = strength * c0.a`. Alpha now mixes toward the shifted samples' max alpha. |
| 3 | `selective-color` | B | Fixed workgroup size. Added `feather_exp = mix(0.5,3.0,zoom_params.w)`. Output alpha is now preserved: `final_alpha = mix(color.a * (1.0 - desat*0.3), color.a, mask)`. Renamed JSON param4 to **Mask Feather**. |
| 4 | `echo-trace` | B | Fixed workgroup size. History decay now preserves alpha: `new_history_a = history.a * decay_rate`. Brush mixing also blends alpha. `vec4(new_history_rgb, new_history_a)` written to both textures. |
| 5 | `temporal-slit-paint` | B | Fixed workgroup size. Removed `finalColor.a = 1.0` so input/video alpha is preserved through brush strokes and history decay. |
| 6 | `signal-noise` | B | Fixed workgroup size. Refactored RGB split to sample full `vec4` at each offset and blend channels using `shift_weight = clamp(...) * c0.a`. Static noise intensity is also modulated by `c0.a`. |
| 7 | `sonic-distortion` | B | Fixed workgroup size. Replaced `.r`/`.g`/`.b` sampling with full `vec4` blending controlled by `aberration_weight = mask * c0.a`. Alpha fades with distortion strength. |
| 8 | `galaxy-compute` | B | Fixed workgroup size. Generated pattern now computes `pattern_alpha = 0.4 + pattern_mask * 0.6`. Mixes overlay using `pattern_opacity = 0.3 + zoom_params.w * 0.7`. Updated JSON param4 name to **Pattern Opacity**. |
| 9 | `radial-rgb` | B | Fixed workgroup size. Replaced radial channel split with full `vec4` sampling and `blend_weight = effect * c0.a`. Original alpha is preserved in undistorted regions. |
| 10 | `luma-echo-warp` | B | Fixed workgroup size. Removed `outputColor.a = 1.0` so alpha is preserved through echo decay and warped mixing. |
| 11 | `gen-astro-kinetic-chrono-orrery` | A | Fixed workgroup size. Added param-driven hue with `plasmaBuffer` bass reactivity. Alpha fades with ray depth: `alpha = 1.0 - (t/MAX_DIST)*0.5`. |
| 12 | `gen-raptor-mini` | A | Fixed workgroup size. Added `plasmaBuffer` bass to rage mode. Body/trail now write meaningful alpha (`body=0.9+`, `trail=0.2–0.8`). Added glow halo derived from rage. |
| 13 | `gen-cosmic-web-filament` | A | Fixed workgroup size. Alpha now scales with `filDensity` so dark voids are transparent. Added `plasmaBuffer` bass reactivity to `warpStrength`. |
| 14 | `gen_psychedelic_spiral` | A | Fixed workgroup size. Replaced RGB-only patterns with smooth HSV hue rotation. Added alpha falloff at spiral edges. Center follows mouse. Added plasmaBuffer bass reactivity. |
| 15 | `cymatic-sand` | A | Fixed workgroup size. Alpha proportional to sand presence/contrast. Added writeDepthTexture height-field output. Added plasmaBuffer mids reactivity to shake frequency. |
| 16 | `gen-vitreous-chrono-chandelier` | A | Fixed workgroup size. Alpha transmission based on ray depth and transmission param. Switched audio to plasmaBuffer bass. Added writeDepthTexture pass-through. |
| 17 | `gen-xeno-botanical-synth-flora` | A | Fixed workgroup size. Added petal-edge feathering to transparent alpha. Added plasmaBuffer mids reactivity to growth/bloom. Added glowSpread param4. |
| 18 | `gen-crystal-caverns` | A | Fixed workgroup size. Added ray-depth alpha fade with fogDensity param. Mouse light modulates alpha. Added plasmaBuffer bass reactivity. |

---

## Active Queue — 0 Shaders Remaining (all completed ✅)

### Batch A — Small Generative (0 remaining — all completed ✅)

| # | Shader ID | Size | Status | Primary Upgrades |
|---|-----------|------|--------|------------------|
| A6 | `interactive-fisheye` | 2,838 | ✅ completed | Fixed workgroup size. Preserves original alpha with vignette falloff at distortion edge. Added bulge curve and edge vignette params. Added plasmaBuffer bass reactivity. |

### Batch B — Small RGB-Limited / Alpha-Oblivious Effects (0 remaining — all completed ✅)

| # | Shader ID | Size | Status | Primary Upgrades |
|---|-----------|------|--------|------------------|
| B1 | `radial-blur` | 2,781 | ✅ completed | Fixed workgroup size. Added depth pass-through. Added sample exponent, decay, and glow params. Added plasmaBuffer bass reactivity. |
| B2 | `swirling-void` | 2,944 | ✅ completed | Fixed workgroup size. Converted to full vec4 sampling with alpha preservation through black-hole darkness. Added audio reactivity param. |
| B3 | `static-reveal` | 2,865 | ✅ completed | Fixed workgroup size. dataTextureA now stores mask in alpha. Noise alpha derived from mask for smoother transition. Added noise scale param and depth pass-through. |
| B4 | `entropy-grid` | 2,941 | ✅ completed | Fixed workgroup size. Changed non-standard texture_depth_2d to texture_2d<f32>. Fixed depth pass-through. Added plasmaBuffer bass reactivity. |
| B5 | `digital-mold` | 2,981 | ✅ completed | Fixed workgroup size. Removed forced alpha=1.0. Mold blend uses mask * decayRate * color.a. Preserves original alpha outside mask. Added depth pass-through and audio reactivity. |
| B6 | `pixel-sorter` | 2,987 | ✅ completed | Fixed workgroup size. Moved threshold to zoom_params.w and intensity to zoom_params.z. Added plasmaBuffer bass reactivity. Depth pass-through already present. |
| B7 | `magnetic-field` | 3,188 | ✅ completed | Fixed workgroup size. Added plasmaBuffer bass reactivity pulsing strength. Depth pass-through already present. Updated JSON params and features. |
| B8 | `kaleidoscope` | 3,204 | ✅ completed | Fixed workgroup size. Out-of-bounds pixels now transparent with smoothstep edge softness. Preserves sampled alpha inside bounds. Added edge softness param. |
| B9 | `synthwave-grid-warp` | 2,969 | ✅ completed | Fixed workgroup size. Alpha derived from grid line intensity so lines are translucent. Added plasmaBuffer bass reactivity. Depth pass-through already present. |
| B10 | `sonar-reveal` | 3,047 | ✅ completed | Fixed workgroup size. Preserves baseColor.a through reveal/ring mix. Added depth pass-through. Added plasmaBuffer bass pulse to ring intensity. |
| B11 | `concentric-spin` | 2,983 | ✅ completed | Fixed workgroup size. Added ring gap opacity param with smoothstep alpha fade at boundaries. Added plasmaBuffer bass pulse to rotation speed. Depth pass-through already present. |
| B12 | `interactive-fresnel` | 3,069 | ✅ completed | Fixed workgroup size. Replaced naive RGB split with full vec4 sampling blended by aberration * cG.a. Added depth influence param and depth pass-through. Added plasmaBuffer bass pulse to displacement. |
| B13 | `time-slit-scan` | 2,835 | ✅ completed | Fixed workgroup size. Standardized all variable names to renderer conventions. Added plasmaBuffer bass reactivity to drift speed. Fixed ripples array size to 50. |
| B14 | `double-exposure-zoom` | 2,925 | ✅ completed | Fixed workgroup size. Replaced RGB-only screen blend with RGBA-aware blend preserving per-layer alpha. Added edge fade and audio reactivity params. Added depth pass-through and plasmaBuffer bass modulation. |
| B15 | `velocity-field-paint` | 2,906 | ✅ completed | Fixed workgroup size. Added depth pass-through. Replaced unused param4 with Audio Reactivity. Added plasmaBuffer bass reactivity to force calculation. |
| B16 | `pixel-repel` | 2,993 | ✅ completed | Fixed workgroup size. Replaced naive RGB split with full vec4 sampling and blend using aberration * c0.a. Preserves source alpha. Added plasmaBuffer bass reactivity to repel displacement. |
| B17 | `lighthouse-reveal` | 3,016 | ✅ completed | Fixed workgroup size. Reforced alpha preservation through beam reveal using texColor.a * visibility. Added depth pass-through. Added plasmaBuffer bass reactivity to beam rotation speed. |

### Batch C — Larger High-Impact Shaders (0 remaining — all completed ✅)

| # | Shader ID | Size | Status | Primary Upgrades |
|---|-----------|------|--------|------------------|
| C1 | `gen-quantum-mycelium` | 6,564 | ✅ completed | Fixed workgroup size. Added alpha falloff with edgeSoftness param. Added plasmaBuffer treble reactivity to node flicker. Added writeDepthTexture pass-through. |
| C2 | `gen-stellar-web-loom` | 6,535 | ✅ completed | Fixed workgroup size. Thread intensity drives alpha via opacity exponent param. Added plasmaBuffer bass reactivity to thread pulse. Added writeDepthTexture pass-through. |
| C3 | `gen-supernova-remnant` | 7,424 | ✅ completed | Fixed workgroup size. Replaced hard alpha=1.0 with density-based alpha via gasOpacity param. Added plasmaBuffer bass pulse to expansion/brightness. |
| C4 | `gen-cyber-terminal` | 9,107 | ✅ completed | Fixed workgroup size. Added glyph edge alpha anti-aliasing via SDF smoothstep. Added scanline bloom param. Used plasmaBuffer for cursor jitter and decode speed. Added writeDepthTexture pass-through. |
| C5 | `gen-bioluminescent-abyss` | 11,949 | ✅ completed | Fixed workgroup size. Added depth-based alpha fog via water clarity param. Bioluminescence glow affects alpha. Added plasmaBuffer bass reactivity. |
| C6 | `gen-chronos-labyrinth` | 14,095 | ✅ completed | Fixed workgroup size. Added distance-field alpha fade via atmospheric perspective param. writeDepthTexture matches ray depth. Added plasmaBuffer bass reactivity. |
| C7 | `gen-quantum-superposition` | 17,672 | ✅ completed | Fixed workgroup size. Probability-cloud alpha proportional to |ψ|² density via wavefunction opacity param. Added plasmaBuffer reactivity to quantum jitter. |

---



---

## Wolfram Alpha Reference Data (Batch 1)

> Computational constants and kernels gathered via Wolfram Alpha MCP for this week's shader upgrades.

### 1. Fresnel Reflectance (Schlick's R₀)

Normal-incidence reflectance for common materials:

| Material | n | R₀ |
|---|---|---|
| Water | 1.333 | 0.0201 |
| Glass | 1.500 | 0.0400 |
| Diamond | 2.420 | 0.1724 |

WGSL helper:
```wgsl
const FRESNEL_R0_WATER: f32 = 0.0200593122;
const FRESNEL_R0_GLASS: f32 = 0.04;
const FRESNEL_R0_DIAMOND: f32 = 0.1723949249;

fn schlickFresnel(cosTheta: f32, R0: f32) -> f32 {
    return R0 + (1.0 - R0) * pow(1.0 - cosTheta, 5.0);
}
```

### 2. Blackbody Color Temperatures

Approximate RGB values for shader use:

| Temperature (K) | RGB (normalized) |
|---|---|
| 2000 | `vec3<f32>(1.000, 0.526, 0.153)` |
| 4500 | `vec3<f32>(1.000, 0.828, 0.701)` |
| 6500 | `vec3<f32>(1.000, 0.976, 0.932)` |
| 9500 | `vec3<f32>(0.839, 0.912, 1.000)` |

### 3. Physical Constants

| Constant | Value | WGSL Symbol |
|---|---|---|
| Planck constant (h) | 6.626×10⁻³⁴ J·s | `PLANCK_H` |
| Reduced Planck constant (ℏ) | 1.055×10⁻³⁴ J·s | `PLANCK_HBAR` |
| Capillary wave speed* | 0.2477 m/s | `CAPILLARY_SPEED` |
| Sedov-Taylor radius exponent | 2/5 = 0.4 | `SEDOV_EXPONENT` |
| Rayleigh cross section (air, 550nm) | 1.188×10⁻³⁰ m² | `RAYLEIGH_SIGMA` |

*For λ=0.01m, γ=0.0728 N/m, ρ=1000 kg/m³, g=9.81 m/s²

### 4. Bessel J₀ Zeros (Airy Disk / Diffraction)

First 5 zeros for radial wave patterns:
```wgsl
const BESSEL_J0_ZEROS: array<f32, 5> = array<f32, 5>(
    2.4048255577,
    5.5200781103,
    8.6537279129,
    11.7915344390,
    14.9309177085
);
```

### 5. Golden Angle & Fibonacci

```wgsl
const GOLDEN_ANGLE: f32 = 2.3999632297; // radians, (3 - sqrt(5)) * π
const FIBONACCI: array<f32, 12> = array<f32, 12>(
    1.0, 1.0, 2.0, 3.0, 5.0, 8.0,
    13.0, 21.0, 34.0, 55.0, 89.0, 144.0
);

// Phyllotaxis spiral
fn phyllotaxis(i: f32) -> vec2<f32> {
    let r = sqrt(i) * 0.01;
    let theta = i * GOLDEN_ANGLE;
    return vec2<f32>(r * cos(theta), r * sin(theta));
}
```

### 6. Image Convolution Kernels

#### 3×3 Gaussian Blur (σ=1, normalized)
Sum = (2+√e)²/e ≈ 4.89764
```wgsl
const GAUSSIAN_3X3: array<f32, 9> = array<f32, 9>(
    0.0204, 0.1238, 0.0204,
    0.1238, 0.2042, 0.1238,
    0.0204, 0.1238, 0.0204
);
```

#### 3×3 Laplacian (edge detection)
```wgsl
const LAPLACIAN_3X3: array<f32, 9> = array<f32, 9>(
    0.0,  1.0, 0.0,
    1.0, -4.0, 1.0,
    0.0,  1.0, 0.0
);
```

#### Sobel Operators
```wgsl
const SOBEL_GX: array<f32, 9> = array<f32, 9>(
    -1.0, 0.0, 1.0,
    -2.0, 0.0, 2.0,
    -1.0, 0.0, 1.0
);
const SOBEL_GY: array<f32, 9> = array<f32, 9>(
    -1.0, -2.0, -1.0,
     0.0,  0.0,  0.0,
     1.0,  2.0,  1.0
);
```

### 7. Color Science & Fog Formulas

```wgsl
// Linear ↔ sRGB conversion
fn linearToSRGB(c: f32) -> f32 {
    return select(1.055 * pow(c, 1.0/2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

fn sRGBToLinear(c: f32) -> f32 {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

// Exponential fog
fn expFog(color: vec3<f32>, fogColor: vec3<f32>, depth: f32, density: f32) -> vec3<f32> {
    let fogFactor = exp(-depth * density);
    return mix(fogColor, color, fogFactor);
}

// Premultiplied alpha blend (over operator)
fn blendPremultiplied(dst: vec4<f32>, src: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(dst.rgb + src.rgb * (1.0 - dst.a), dst.a + src.a * (1.0 - dst.a));
}
```

### 8. Signed Distance Functions (SDF)

```wgsl
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Polynomial smooth minimum for SDF blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
```

### 9. Seawater Attenuation Coefficients

| Wavelength | Coefficient (m⁻¹) |
|---|---|
| 450 nm (blue) | 0.03 |
| 550 nm (green) | 0.08 |
| 650 nm (red) | 0.35 |

```wgsl
const WATER_ATTENUATION: vec3<f32> = vec3<f32>(0.35, 0.08, 0.03); // R, G, B
```
## Detailed Code Suggestions

### A1 — `gen_psychedelic_spiral`
- Fix `@workgroup_size(16, 16, 1)` → `(8, 8, 1)`.
- If the shader computes color as `vec3<f32>(...)`, append alpha based on distance from spiral center:
  ```wgsl
  let alpha = 1.0 - smoothstep(0.3, 0.8, dist_from_center);
  textureStore(writeTexture, coords, vec4<f32>(col, alpha));
  ```
- Add mouse-driven focal point by offsetting the spiral center with `u.zoom_config.yz`.

### A2 — `cymatic-sand`
- Fix workgroup size.
- Where particles are written, set alpha proportional to speed:
  ```wgsl
  let speed_alpha = clamp(length(velocity), 0.0, 1.0);
  textureStore(writeTexture, coords, vec4<f32>(col, speed_alpha));
  ```
- Write depth based on particle height/pseudo-Z:
  ```wgsl
  textureStore(writeDepthTexture, coords, vec4<f32>(speed_alpha, 0.0, 0.0, 0.0));
  ```
- Add `plasmaBuffer[0].x` (bass) to the vibration frequency.

### A3 — `gen-vitreous-chrono-chandelier`
- Fix workgroup size.
- For glass surfaces, compute a Fresnel-like term and use it to lower alpha:
  ```wgsl
  let fresnel = pow(1.0 - abs(dot(normal, rd)), 2.0);
  let transmission = u.zoom_params.w;
  let alpha = mix(1.0, 0.4, fresnel * transmission);
  textureStore(writeTexture, coords, vec4<f32>(col, alpha));
  ```
- Add param4 in JSON as "Transmission" (0.0–1.0).

### A4 — `gen-xeno-botanical-synth-flora`
- Fix workgroup size.
- At petal edges (where `dist_to_edge` is small), feather alpha:
  ```wgsl
  let edge_alpha = smoothstep(0.0, 0.05, dist_to_edge);
  textureStore(writeTexture, coords, vec4<f32>(col, edge_alpha));
  ```
- Add `plasmaBuffer[0].y` (mids) to the growth/bloom pulse multiplier.

### A5 — `gen-crystal-caverns`
- Fix workgroup size.
- After raymarching, fade alpha with depth:
  ```wgsl
  let fog = u.zoom_params.w; // fog density
  let alpha = exp(-t * 0.05 * fog);
  textureStore(writeTexture, coords, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Fog Density".

### A6 — `interactive-fisheye`
- Fix workgroup size.
- The shader already samples full `vec4`, but can be enhanced with a vignette alpha at the radius edge:
  ```wgsl
  let edge_fade = smoothstep(radius, radius * 0.8, dist);
  color.a = color.a * edge_fade;
  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
  ```

### B1 — `radial-blur`
- Fix workgroup size.
- The accumulator already averages full `vec4` samples, so alpha is preserved correctly. Add depth pass-through:
  ```wgsl
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  ```
- Add `zoom_params.w` as "Sample Curve" to control `t` exponent:
  ```wgsl
  let curve = 0.5 + u.zoom_params.w * 2.0;
  let t = pow(f32(i) / f32(samples - 1), curve);
  ```

### B2 — `swirling-void`
- Fix workgroup size.
- Replace `.rgb` sampling and forced alpha:
  ```wgsl
  var color = textureSampleLevel(readTexture, u_sampler, new_uv, 0.0);
  // Apply darkness to rgb only
  if (dist < hole_size) {
      color.rgb = vec3<f32>(0.0);
  } else if (dist < hole_size * 2.0) {
      color.rgb *= smoothstep(hole_size, hole_size * 2.0, dist);
  }
  textureStore(writeTexture, coord, color);
  ```

### B3 — `static-reveal`
- Fix workgroup size.
- Store full mask in alpha:
  ```wgsl
  textureStore(dataTextureA, global_id.xy, vec4<f32>(mask, 0.0, 0.0, mask));
  ```
- Let noise alpha follow the inverse of the mask for smoother transitions:
  ```wgsl
  let noiseColor = vec4<f32>(vec3<f32>(noiseVal), 1.0 - mask);
  let finalColor = mix(noiseColor, videoColor, mask);
  ```

### B4 — `entropy-grid`
- Fix workgroup size.
- Change `readDepthTexture` binding type from `texture_depth_2d` to `texture_2d<f32>` (match standard bindings) and update depth read:
  ```wgsl
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  ```

### B5 — `digital-mold`
- Fix workgroup size.
- Preserve original alpha and blend mold with it:
  ```wgsl
  let moldAlpha = mask * decayRate * color.a;
  let decayed = mix(pixelColor, moldColor.rgb, colorShift);
  color = mix(color, vec4<f32>(decayed, 1.0), moldAlpha);
  ```

### B6 — `pixel-sorter`
- Fix workgroup size.
- Already preserves alpha. Add depth pass-through:
  ```wgsl
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
  ```
- Add `zoom_params.w` as "Sort Threshold" to replace mouse-Y dependency:
  ```wgsl
  let threshold = u.zoom_params.w;
  ```

### B7 — `magnetic-field`
- Fix workgroup size.
- Add depth pass-through and audio reactivity:
  ```wgsl
  let bass = plasmaBuffer[0].x;
  let strength = u.zoom_params.x * (1.0 + bass * 0.5);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  ```

### B8 — `kaleidoscope`
- Fix workgroup size.
- Make out-of-bounds transparent:
  ```wgsl
  var color = vec4<f32>(0.0, 0.0, 0.0, 0.0);
  if (final_uv.x >= 0.0 && final_uv.x <= 1.0 && final_uv.y >= 0.0 && final_uv.y <= 1.0) {
      color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0);
  }
  ```
- Add `zoom_params.w` as "Edge Softness" if a new param slot is desired (currently `w` is unused).

### B9 — `synthwave-grid-warp`
- Fix workgroup size.
- Derive alpha from grid line brightness so video shows through dark grid cells:
  ```wgsl
  let alpha = 0.2 + gridLine * 0.8;
  var finalColor = mix(videoColor * 0.5, gridColor, gridLine);
  finalColor += vec3(0.0, 1.0, 1.0) * warp * 2.0;
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  ```
- Add depth pass-through.

### B10 — `sonar-reveal`
- Fix workgroup size.
- Preserve input alpha through the reveal:
  ```wgsl
  var finalColor = mix(dimColor, baseColor.rgb, reveal);
  finalColor = finalColor + ringColorVec * ring * intensity;
  let final_alpha = mix(baseColor.a * 0.5, baseColor.a, reveal);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, final_alpha));
  ```

### B11 — `concentric-spin`
- Fix workgroup size.
- Add ring-gap opacity using `zoom_params.w`:
  ```wgsl
  let gap_opacity = u.zoom_params.w;
  let ring_frac = fract(ringVal);
  let in_gap = smoothstep(0.45, 0.55, ring_frac);
  color.a = mix(color.a, color.a * gap_opacity, in_gap);
  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
  ```
- Add depth pass-through.

### B12 — `interactive-fresnel`
- Fix workgroup size.
- Replace naive RGB split with full `vec4` blending:
  ```wgsl
  let c0 = textureSampleLevel(readTexture, u_sampler, baseUV, 0.0);
  let c_r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
  let c_b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);
  let ab_weight = aberration * c0.a;
  var finalColor = c0;
  finalColor.r = mix(c0.r, c_r.r, ab_weight);
  finalColor.b = mix(c0.b, c_b.b, ab_weight);
  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  ```
- Add depth pass-through.

### B13 — `time-slit-scan`
- Fix workgroup size.
- Rename texture variables for consistency (optional but recommended):
  ```wgsl
  // Change: input_texture -> readTexture, output_texture -> writeTexture,
  // data_texture_a -> dataTextureA, data_texture_c -> dataTextureC,
  // depth_texture_read -> readDepthTexture, depth_texture_write -> writeDepthTexture
  ```
- Add audio reactivity to drift:
  ```wgsl
  let bass = plasma_buffer[0].x;
  let drift = vec2<f32>(drift_speed * 0.1 * (1.0 + bass), 0.0);
  ```

### B14 — `double-exposure-zoom`
- Fix workgroup size.
- Replace hard alpha with screen-blended alpha:
  ```wgsl
  let blended_rgb = 1.0 - (1.0 - col1.rgb) * (1.0 - col2.rgb);
  let blended_alpha = 1.0 - (1.0 - col1.a) * (1.0 - col2.a);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(blended_rgb, blended_alpha));
  ```
- Add depth pass-through.

### B15 — `velocity-field-paint`
- Fix workgroup size.
- Add `plasmaBuffer` bass to force:
  ```wgsl
  let bass = plasmaBuffer[0].x;
  let force = u.zoom_params.z * 0.5 * (1.0 + bass);
  ```
- Add depth pass-through:
  ```wgsl
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  ```

### B16 — `pixel-repel`
- Fix workgroup size.
- Replace naive RGB split with full `vec4` blending:
  ```wgsl
  let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let c_r = textureSampleLevel(readTexture, u_sampler, clamp(uv - displacement * (1.0 + aberration), vec2(0.0), vec2(1.0)), 0.0);
  let c_g = textureSampleLevel(readTexture, u_sampler, clamp(uv - displacement, vec2(0.0), vec2(1.0)), 0.0);
  let c_b = textureSampleLevel(readTexture, u_sampler, clamp(uv - displacement * (1.0 - aberration), vec2(0.0), vec2(1.0)), 0.0);
  let ab_weight = aberration * c0.a;
  var color = c0;
  color.r = mix(c0.r, c_r.r, ab_weight);
  color.g = mix(c0.g, c_g.g, ab_weight);
  color.b = mix(c0.b, c_b.b, ab_weight);
  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
  ```

### B17 — `lighthouse-reveal`
- Fix workgroup size.
- Preserve input alpha:
  ```wgsl
  let finalColor = mix(texColor.rgb * ambient, texColor.rgb, mask);
  let finalAlpha = mix(texColor.a * ambient, texColor.a, mask);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
  ```

### C1 — `gen-quantum-mycelium`
- Add alpha falloff at thread edges:
  ```wgsl
  let edge_dist = abs(d - thread_radius);
  let alpha = 1.0 - smoothstep(0.0, 0.02, edge_dist);
  ```
- Add `plasmaBuffer[0].z` (treble) to node brightness/flicker.

### C2 — `gen-stellar-web-loom`
- Let thread intensity drive alpha:
  ```wgsl
  let opacity_exp = u.zoom_params.w * 3.0 + 0.5;
  let alpha = pow(intensity, opacity_exp);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Thread Opacity Exponent" and `plasmaBuffer` bass reactivity.

### C3 — `gen-supernova-remnant`
- Replace hard `alpha = 1.0` with density-based alpha:
  ```wgsl
  let density = smoothstep(0.0, 1.0, nebula_val);
  let alpha = density * 0.7 + 0.3;
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add `plasmaBuffer[0].x` to expansion radius.

### C4 — `gen-cyber-terminal`
- Add glyph edge AA using smoothstep against glyph SDF:
  ```wgsl
  let glyph_sdf = ...; // existing distance
  let glyph_alpha = smoothstep(0.05, 0.0, glyph_sdf);
  textureStore(writeTexture, id.xy, vec4<f32>(col, glyph_alpha));
  ```
- Add param4 "Scanline Bloom" mapped to `zoom_params.w`.
- Drive cursor jitter with `plasmaBuffer[0].x`.

### C5 — `gen-bioluminescent-abyss`
- Add depth-based fog alpha:
  ```wgsl
  let clarity = u.zoom_params.w * 5.0 + 0.1;
  let alpha = exp(-t * 0.05 * clarity);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Water Clarity".

### C6 — `gen-chronos-labyrinth`
- Add distance-field alpha fade:
  ```wgsl
  let atmo = u.zoom_params.w; // atmospheric perspective
  let alpha = exp(-t * 0.02 * atmo);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Atmospheric Perspective".

### C7 — `gen-quantum-superposition`
- Probability-cloud alpha:
  ```wgsl
  let psi_density = length(quantum_val);
  let opacity = u.zoom_params.w * 2.0 + 0.2;
  let alpha = clamp(psi_density * opacity, 0.0, 1.0);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Wavefunction Opacity".

---

## Execution Checklist (for swarm agents)

For each shader in the Active Queue:
- [ ] Read WGSL and JSON.
- [ ] Apply the specific upgrades above.
- [ ] Update JSON if new params/features are added.
- [ ] Run `node scripts/generate_shader_lists.js` and fix any errors.
- [ ] Mark the shader as **DONE** in this file and move it to the "Recently Completed" table.
- [ ] If the active queue drops below 25, add new candidates from the smallest-shaders list to replenish.

## Candidate Pool for Replenishment

Next smallest shaders not yet in any batch:
- `pixel-sand` (3,208)
- `crt-magnet` (3,230)
- `scan-distort-gpt52` (3,236)
- `digital-lens` (3,238)
- `chromatic-mosaic-projector` (3,242)
- `chrono-slit-scan` (3,242)
- `mosaic-reveal` (3,247)
- `quad-mirror` (3,256)
- `spiral-lens` (3,266)
- `tile-twist` (3,267)
- `page-curl-interactive` (3,284)
- `tesseract-fold` (3,286)
- `polar-warp-interactive` (3,287)
- `echo-ripple` (3,307)
- `scanline-wave` (3,315)
- `quantum-ripples` (3,331)
- `oscilloscope-overlay` (3,340)
- `spectral-brush` (3,353)
- `magnetic-interference` (3,355)
- `voxel-grid` (3,357)
- `polka-dot-reveal` (3,362)
- `scanline-sorting` (3,363)
- `neon-cursor-trace` (3,373)
- `directional-glitch` (3,382)
- `stereoscopic-3d` (3,386)
- `cyber-ripples` (3,390)
- `quantized-ripples` (3,400)
- `data-scanner` (3,405)
- `vertical-slice-wave` (3,411)
- `phantom-lag` (3,412)
- `xerox-degrade` (3,425)
