# COORDINATOR_REVIEW — sonnet/batch-27 (optical lenses, 10 shaders)

Evidence is structural plus SwiftShader renders (see each `NOTES-*.md`). **No real-GPU visual QA is claimed.** Cards: `BRIEFS.md` (written before any WGSL; deviations are recorded below and in the per-fork notes, not silently).

## Process note — PR #1654 merged mid-batch
PR #1654 was merged by the repo owner at 08:02:52 UTC while fork B was still editing. `main` therefore received an unreviewed, **compile-valid WIP snapshot** of cyber-magnifier, multi-fractal-compositor-lens and interactive-fisheye (labelled `wip(...)` in history), plus the finished versions of the other 7 shaders. The reviewed final versions of those three, the regenerated lists / search index, the upgrade-ledger entries and this review land in the follow-up PR. Lesson: a labelled WIP push into an already ready-for-review PR can be merged as-is; hold unfinished files back until they are reviewed.

## Verdict per file (§9 checklist + §12.7 additions)

| Shader | Card before diff | Each idea pointable | KEEP VERBATIM holds | Not ≥70 % boilerplate | No shared overlay | A packing matches C read | `params` byte-exact | Springs / ripples only if native | Naga + extraBuffer + dead sliders | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| anamorphic-flare | ✓ | ✓ L61 / L75 / L114 | ✓ | ✓ | ✓ | ✓ ACES display RGBA (no state) | ✓ | ✓ none added | ✓ | **pass** |
| ascii-lens | ✓ | ✓ L137–L209 | ✓ | ✓ | ✓ | ✓ display RGBA + A(0,0) glide | ✓ | ✓ lens already owned the pointer | ✓ | **pass** |
| cross-mouse-spec-dispersion-lens | ✓ | ✓ L156–L198 | ✓ (see PRISM_GAIN) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **pass, with a flagged rescue (R3)** |
| quantum-flux | ✓ | ✓ L131–L177 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **pass; look is bold, QA the plateau constant** |
| double-exposure | ✓ | ✓ L165–L205 | ✓ | ✓ | ✓ | ✓ ACES display RGBA + A(0,0) | ✓ | ✓ pivot already pointer-led | ✓ | **pass** |
| heat-haze-mirage | ✓ | ✓ L48 / L164–L240 | ✓ | ✓ | ✓ | ✓ pre-ACES HDR haze + A(0,0) | ✓ | ✓ | ✓ | **pass; HEAD geometry bug left open** |
| interactive-zoom-blur | ✓ | ✓ L139–L166 | ✓ | ✓ | ✓ | ✓ display RGBA + A(0,0) | ✓ | ✓ | ✓ | **pass** |
| cyber-magnifier | ✓ | ✓ L91–L153 | ✓ (A masks + glide untouched) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **pass** |
| multi-fractal-compositor-lens | ✓ | ✓ L120–L224 | ✓ (CA taps still bypass the lens by design) | ✓ | ✓ | ✓ ACES display RGBA + A(0,0) | ✓ | ✓ | ✓ | **pass; card numbers corrected** |
| interactive-fisheye | ✓ | ✓ L49–L101 / L156–L186 / L234–L250 | ✓ (A raw [h,v,nx,ny]) | ✓ | ✓ | ✓ raw sim + A(0,0) tracker masked in `simLoad()` | ✓ | ✓ | ✓ | **pass; waves are subtle by design** |

Gate totals: Naga (naga-wasm) 10/10 valid · `wgsl_precommit_gate.py` 10/10 (pasted headers 0, extraBuffer violations 0) · `audit_extrabuffer.py` PASS · `audit_dead_sliders.py` PASS (0 new) · saved `params` and `x-meta` of all 10 definitions identical to HEAD (checked programmatically) · `npm run verify:generated-sync` clean · `npm run test:ci` (see closeout block).

## Formula names per file (§12.2 rows) and de-duplication
| Shader | §12.2 rows used |
|---|---|
| anamorphic-flare | Soft inverse-square (F) |
| ascii-lens | Edge orientation / structure-tensor family (A) |
| cross-mouse-spec-dispersion-lens | Cauchy dispersion (F) — deepened, was already the file's own mechanism |
| heat-haze-mirage | Cauchy dispersion (F) — vertical, relative to green |
| cyber-magnifier | Brown–Conrady radial (B) |
| double-exposure | cos⁴ vignetting (A) |
| interactive-fisheye | Damped wave (D), isotropic 9-point Laplacian (D), Snell vector refraction (F) |
| multi-fractal-compositor-lens, quantum-flux, interactive-zoom-blur | none (tactic-derived: point-lens μ / μt, ψ² shells + energy-level hue, whip-pan + linear light) |

No §12.2 row appears on more than two files (Cauchy is on exactly two); no two files share both formulae; the batch theme is "lens optics", not one mechanism, so the "≥3 files share both formulae" failure does not apply.

## Rescues common to the batch (reported separately from ideas)
- **R1 cursor glide.** `extraBuffer[133..255]` is re-uploaded zeroed every frame (`writeExtraBuffer`, 256-float scratch), so every spring/envelope in these files was dead and the cursor was the raw pointer. Rebuilt as a first-order glide in A texel (0,0) = `(glide.xy, 7, fract(time))` in 7 shaders (lag-only in interactive-fisheye). Check `st.w <= 1.0` (f16 rounds `fract(time)` above 0.9997 to exactly 1.0 — found by fork A) in every copy. Every place that reads C as colour/field masks texel (0,0).
- **R2 dead audio.** `plasmaBuffer[1..]` is never uploaded (only `[0]`). Per-bin voices now read the engine FFT bins `extraBuffer[5 + bin]` (bins {0,1,2,4,7,11,19,32} or bands) in ascii-lens, cross-mouse, quantum-flux, double-exposure, heat-haze, zoom-blur; ascii-lens `bass` now `plasmaBuffer[0].x`. Idle (zero audio) looks unchanged.
- **`pow(negative, n)`** (undefined → NaN on strict GPUs) removed in anamorphic-flare (rays) and cross-mouse (ring/rim).

## Deviations from the cards (and corrections to the cards)
- **anamorphic-flare**: card said "ghost geometry stays HEAD's". Renders showed HEAD's two ghost apertures were centred differently, so the visible ghost was a clipped sliver. Fixed (R2); card amended in `NOTES-coordinator.md`.
- **cross-mouse-spec-dispersion-lens**: HEAD's dispersion was invisible (R/B offset ~4e-5 uv, <¼ px at 576 px with every slider at max). The card's "keep HEAD's maximum fringe extent" was therefore moot; fork A added `PRISM_GAIN = 80` (R3). Default now has a ~1.6 px extreme-tap fringe at 576 px. **Needs a human eye on the gain.**
- **ascii-lens**: stroke angle snapped to the four ASCII angles (`- | / \`) rather than free-angle; edge gate is `|g| > 0.08` (a per-cell tensor is rank 1, so there is no coherence term).
- **quantum-flux**: added a fade of the shell weight to 1 below Wave Freq 0.08 (no strobing at the slider's low end). Default look is bold (stdL 0.2117 → 0.2238; stepped concentric hue rings).
- **cyber-magnifier**: loupe distortion is also faded with `pixAmt` (left on, the digital texel grid became moiré).
- **multi-fractal-compositor-lens**: critical-curve brightening attenuated by Ring Glow (peak ×2 at default, not the card's ×3 — ×3 whites out under ACES). The card's ring numbers were wrong: the default ring moves **0.1666 → 0.1360** (card said 0.203 → 0.166). Zoom-wrap pops reduced from 12× to ~4× the median frame difference (one residual bump).
- **interactive-fisheye**: the wave force is the Laplacian of the *deviation from rest height* (the Laplacian of h itself spread the lens +60 %), on a 1.5 %-of-height stencil with a dead-band (the 1-texel stencil sparkled on rgba16float), and κ ≈ 1e-3 at the defaults (hard cap 0.25; CFL limit 0.75; stable on f16 over ≥300 frames at 8 slider corners). So **the waves are subtle by design**; `WAVE_SPEED` is the dial. The unmasked specular (R2) was the largest look change in the batch: idle meanL 0.7412 → 0.5000, because the whole frame no longer gets a +0.6 white wash.
- **double-exposure**: the dwell is stateless (no hold-duration state), so at the default rotation (0.15 rad/s) its smear is only a few pixels; it integrates in scene-referred light (inverse ACES of C), so the held steady state equals HEAD's and nothing pops at press/release.
- **heat-haze-mirage**: scintillation uses the divergence of the displacement field's own fbm (ray focusing) rather than independent noise, with a photosensitivity taper above ~8 cycles/s.
- **interactive-zoom-blur**: HEAD's `min(springSpeed·4, 0.5)` constant was tuned for a velocity that was always 0, so it is now `min(lag·rate, 0.5)`; weights are normalised so revived FFT voices cannot brighten the streak. Gamma-2 accumulation is a deliberate highlight look change (neutral on mean luma).

## Open items (not fixed here; for a human / real GPU)
1. **heat-haze-mirage geometry is vertically inverted in HEAD.** Heat column, false-water fold and caustics are strongest at the TOP (uv.y = 0) and the "rising" shimmer scrolls down; at default settings |bend|·48 ≈ 0.09 against a 0.55 critical value, so the fold never triggers (only with bass, held, or high heat). The card forbade touching fold geometry; flipping is a small, separate, revertable change that needs a product decision.
2. **interactive-fisheye HEAD refraction gradient and 1-texel caustic Laplacian are noise-dominated on rgba16float at ≥576 px** (terraces / sparkle inside the droplet; clean at f32). Needs a wide-baseline gradient and caustic Laplacian and a real-GPU look.
3. **multi-fractal-compositor-lens**: HEAD's CA taps sample the unlensed photo, so ~70 % of R/B bypasses the lens. Left (KEEP VERBATIM) — deserves its own pass.
4. Tuned-by-eye constants seen only on SwiftShader: `PRISM_GAIN`, spectral lobe widths, ascii edge threshold 0.08, quantum hue plateau 0.78, fisheye `WAVE_SPEED/LAP_CORE/WAVE_STENCIL/SNELL_CAP`, flare glare weight 0.5 / ghost gain ×0.55.
5. Harness FFT is constant per band, so per-voice (per-bin) differences are untested; harness stores textures as rgba32float except fork B's f16 re-runs.
6. **interactive-fisheye cost.** The wave term adds 8 exact C loads and 8 analytic rest-height evaluations per pixel. SwiftShader CPU timing at 576 px, 20 frames, 2 rounds: HEAD 31.7 / 36.7 ms, new 54.7 / 57.5 ms per frame (~1.65x). Not a GPU number; cyber-magnifier (41.3 -> 38.5 ms) and multi-fractal-compositor-lens (44.3 -> 45.5 ms) are within noise, interactive-zoom-blur measured 0.97x of HEAD by fork C. If the fisheye is too heavy on a real GPU, the wave block can be skipped when `wave_kappa` is below a threshold (uniform control flow: it depends only on the sliders).
7. Thumbnails are stale for all 10 (ledger marks them; refresh on a GPU machine).
8. JSON `description` strings of heat-haze-mirage and double-exposure still mention the old spring (briefs limited edits to `features`/`tags`/`x-meta`).
9. Four descriptive tags were added (`ascii`, `lens` on ascii-lens; `quantum`, `chromatic` on quantum-flux); `upgraded-rgba` was dropped from 4 definitions that apply no ACES (cyber-magnifier, cross-mouse-spec-dispersion-lens, quantum-flux, interactive-zoom-blur) and from the ascii-lens / cyber-magnifier / cross-mouse / quantum-flux / zoom-blur banners, `fast-motion` dropped from double-exposure, false `mandelbrot` / `julia` features dropped from multi-fractal-compositor-lens.
