# Sonnet batch 15 — fractal-set ten — Idea Cards (written before any WGSL edit)

Batch: `claude-2026-11-01-sonnet-batch-15` · 2026-11-01 · explicit list from the task (sonnet/batch-15): gen-julia-set (`gen_julia_set.wgsl`),
gen-mandelbox-explorer, gen_mandelbulb_3d, spec-quaternion-julia, hyperbolic-dreamweaver-julia, gen-audio-spirograph-julia,
gen-grok41-mandelbrot (`gen_grok41_mandelbrot.wgsl`), kimi-fractal-dreams (`kimi_fractal_dreams.wgsl`), multi-fractal-compositor, gen-3d-sierpinski-chaos.
The three underscored *filenames* are fine: the "skip underscore-prefixed" rule is about files that START with `_` (e.g. `_prelude.wgsl`). None is multipass.
Theme: fractal-set math. Family notes: these are generative, so ideas may be bolder than a photographic filter, but still extend each file's own iteration.
Ledger (reports/shader-upgrade-ledger.json): gen-mandelbox-explorer upgraded 2026-10-12, gen-grok41-mandelbrot upgraded 2026-10-17 (second passes); the other eight have no event
(gen_mandelbulb_3d's ledger id is `gen_mandelbulb_3d`). HEAD `Ideas:` lines are NOT re-added.

Pre-state (naga-wasm and Tint/SwiftShader on main): 9/10 compile. **gen_mandelbulb_3d does not compile at HEAD** (`unresolved value 'mouse'`; it is on the naga known-failures ratchet).
Eight files still paste the 13 bindings → `migrate_to_prelude.py` (infrastructure; the two that already include the prelude are gen-mandelbox-explorer and gen_grok41_mandelbrot).

## Findings that shape the cards

1. **gen_mandelbulb_3d is broken three ways:** `mouse` is undeclared; `hitAlpha` is declared inside `if (hit)` and used after it; the history is read with `textureSampleLevel(dataTextureC, u_sampler …)`, a filtering sampler on rgba32float. All three are floor fixes, without which no idea can run.
2. **multi-fractal-compositor is not a fractal renderer.** Its code is the same naga-translated "layered zoom tunnel" template as particle_dreams_alpha (5 zoom layers, flow noise, click vortex, chroma split, edge glow, fog). In both, `baseColor` — the layer composite — is computed and never used, so the layers only feed depth. In this file slider z (saved "Domain Warp") is not referenced at all, and there is no bounds guard. The JSON description (Mandelbrot/Julia/Burning Ship/Newton blend) does not describe the code. I keep the zoom-tunnel identity (a rewrite into real fractals would be a new shader) and say so in the description.
3. **gen_grok41_mandelbrot has dead controls:** after frame 1 the Center X/Y sliders do nothing (the spring goal is built from `navCenter`, never from the slider targets), and the click re-target is dead twice over (it multiplies by `ripple.w`, which is always 0 padding, and ages the ripple with `time × 5` instead of real seconds). Its per-star "band" energy reads `plasmaBuffer[1..8].x`, which the engine never writes (only `plasmaBuffer[0]` is), so the band term is constant 0.
4. **kimi_fractal_dreams** has the same `plasmaBuffer[1+layer].x` zero read (per-layer treble bins).
5. (Struck: I first believed gen-mandelbox-explorer declared `var dr` twice in `mandelboxDE`; that was an artifact of overlapping `sed` ranges when I printed the file. It declares it once. No repair needed.)
6. Tone curves that are the look are kept and recorded: gen_mandelbulb_3d Reinhard `x/(1+0.5x)`, gen-mandelbox-explorer's Hable-style "acesToneMap". No new tone map is forced on them.

---

## SHADER: gen-julia-set (gen_julia_set.wgsl)
IDENTITY: z^n + c Julia set (n 2..6) with orbit-trap and velocity-trap colouring, c orbiting a cardioid, mouse-drag c, over the input image.
KEEP VERBATIM: 4 params (zoom, exponent, trap mode, trap scale); cpow orbit; smooth μ; circle/line/cross traps incl. HEAD's trap-mode interpolation and velocity trap; filament accumulator; 2-sample AA; chromatic mix; C blend; A raw HDR + ACES on writeTexture.
MECHANISM INTERROGATION: tactic 3 — the orbit already tracks |z|; its derivative |dz/dz0| is one multiply per step and gives the distance to the Julia set itself. HEAD colours the exterior by escape time and traps only, so the thin filaments between bands are missed, and the interior (Fatou set) is coloured by traps with no structure of its own.
ADD:
1. Distance-estimate boundary filaments — accumulate log|dz| (log n + (n−1)·log|z| per step), DE = ½·|z|·ln|z|/|dz|, normalised by pixel footprint; a thin warm lace follows the true boundary of the set.
2. Interior multiplier banding — the same log|dz|/maxIter is the average multiplier of the attracting cycle; it varies smoothly across each Fatou component, so the interior gets concentric bands around attractors.
FORBID: springs, ripples, new params, replacing the traps.
A PACKING: unchanged — raw HDR display RGBA in A (read as C colour).

## SHADER: gen-mandelbox-explorer
IDENTITY: 2-D cross-section of the Mandelbox (box fold + sphere fold + scale) shaded as a metallic surface with DE lighting, fold itinerary colour, diagonal trap, glassy interior, fold-radius click shock.
KEEP VERBATIM: 4 params; boxFold/sphereFold; fold itinerary; space-diagonal trap; bounded interior; DE gradient normal lighting; contours; ripple fold shock; Hable-style tone curve; C blend; A = display RGBA.
MECHANISM INTERROGATION: tactic 2 — the surface is described as "metallic" yet reflects nothing: lighting is diffuse + Blinn only, and the normal `n` is already computed. Tactic 3 — the orbit loop tracks closest approach to the origin and to the (1,1,1) axis but not to the box-fold planes themselves (|z|=1), which are the Mandelbox's own structure.
ADD:
1. Metallic environment reflection — reflect the view vector about `n` into a procedural sky/ground gradient, weighted by Schlick Fresnel (F0 0.6 for a metal) and the DE shell, so the surface reads as polished metal (§12.2F Fresnel–Schlick).
2. Fold-wall orbit trap — closest approach of the orbit to the fold planes `| |z.c| − 1 |` (§12.2E orbit trap, different trap than HEAD's origin/diagonal), brightening a lattice that follows the box walls.
REPAIR: none needed (the "duplicate var dr" I noted was a printing artifact).
FORBID: new params, springs, a different tone map.
A PACKING: unchanged — display RGBA, C read as colour.

## SHADER: gen_mandelbulb_3d
IDENTITY: ray-marched power-8 Mandelbulb with orbit-trap colour, soft shadow, audio-driven power/glow/trails, fog.
KEEP VERBATIM: 4 params; DE and ray march; orbit-trap colour; soft shadow; fog; glow; Reinhard-style tone curve + vignette; A = final display colour (read as C colour).
MECHANISM INTERROGATION: tactic 3 — `iter` (the march's final step count) is computed and unused; the normal needs six DE taps and shading has no occlusion, so crevices read as flat as ridges. Tactic 1 — soft shadow exists, ambient occlusion does not.
ADD:
1. Step-count/DE ambient occlusion — five DE taps along the normal, Σ (h − d(p+n·h))·½ⁱ (§12.2E step-count AO), applied to the ambient and diffuse terms.
2. Curvature edge wear — the DE Laplacian from six axis taps, (Σ d(p±e) − 6d)/e² (§12.2E SDF curvature): convex ridges catch a warm metallic highlight, concave crevices tarnish toward the cool end of the existing trap palette.
REPAIR (floor, required for any output): define `mouse`; hoist `hitAlpha`; exact `textureLoad` of C. Leaves the naga known-failures list (ratchet −1).
FORBID: new params, springs, ripples, replacing the DE.
A PACKING: unchanged — display RGBA in A.

## SHADER: spec-quaternion-julia
IDENTITY: raymarched 4-D quaternion Julia set, c animated, orbit-trap IQ palette, mouse orbit or auto-rotate.
KEEP VERBATIM: 4 params; quaternion algebra and DE (escape 256, ½·r·ln r/dr); camera/orbit; palette and glow; dither; A raw HDR colour.
MECHANISM INTERROGATION: tactic 2 — a quaternion Julia set is a 4-D object shown as a 3-D slice, and the slice is fixed at w = 0 (only c.w moves); the header says the 4th dimension animates. Tactic 1 — lighting has diffuse/spec/step-AO but no shadow.
ADD:
1. Hyperplane slice drift — the start quaternion becomes (p, w0) with w0 = 0.18·sin(0.37·t_morph), so the 3-D cross-section slides through the 4-D set and the lobes grow and pinch (the DE derivation is unchanged: dq still starts at 1).
2. DE cone soft shadow — 12 steps toward the light, min(8h/t) penumbra, so the lobes cast shadows on each other.
FLOOR: add the missing bounds guard (HEAD writes for every invocation).
FORBID: replacing the palette, new params, springs.
A PACKING: unchanged — raw HDR colour in A (no reader), ACES on writeTexture.

## SHADER: hyperbolic-dreamweaver-julia
IDENTITY: a quaternion Julia set raymarched through a Poincaré-disk view, hyperbolic translation of the camera origin, photo albedo on the hit, horocycle fog.
KEEP VERBATIM: 4 params; Julia DE; hyperbolicTranslate / hyperbolicDist; disk mask; mouse orbit; photo albedo mix; horocycle fog; A = ACES display RGBA.
MECHANISM INTERROGATION: tactic 1 — the disk model only moves the ray ORIGIN; ray directions are an ordinary pinhole, so the "hyperbolic" view has no hyperbolic perspective. Tactic 1 again — the photo is sampled at `uv + n.xy·0.08`, a pseudo-refraction, where the next-better operator is Snell's law.
ADD:
1. Hyperboloid-perspective rays — ray direction from the translated disk point p via p/(1 − 0.8|p|²) (the hyperboloid-model spatial coordinate, equal to HEAD near the centre), so the scene compresses toward the rim as in a Poincaré disk.
2. Snell refraction of the photo — `refract(rd, n, 1/ior)` with Cauchy-split IORs (1.43/1.45/1.48) for R/G/B (§12.2F Snell + Cauchy), three photo taps instead of one pseudo-offset.
FORBID: springs, new params, replacing the Julia DE.
A PACKING: unchanged — ACES display RGBA.

## SHADER: gen-audio-spirograph-julia
IDENTITY: five audio-breathing spirograph rings (epi/hypotrochoids) whose glow is coloured by Julia sets whose constant follows the mouse, with trail accumulation.
KEEP VERBATIM: 4 params; ratios/harmonics; epi/hypotrochoid families; orbit-trap filaments; screen Julia overlay; C trail blend; ACES; A = col·0.95 + alpha.
MECHANISM INTERROGATION: tactic 5 — a spirograph's signature is the pen: here each ring is a single 0.05-time segment (the pen at one instant) whose crisp trace exists only through the trail slider's history. Tactic 4 — the Julia constant is one global value for all five rings.
ADD:
1. Pen-driven Julia constant — each ring's embedded Julia uses c_i = juliaC + 0.25·pen position, so the filaments around a ring morph as its pen travels.
2. Ink tail — three more fading segments behind the pen (t−0.10 … t−0.20) so each ring carries a crisp comet of ink independent of the trail history.
FORBID: springs, new params, changing the A/C trail packing.
A PACKING: unchanged — ACES display RGBA ×0.95 in A, read as C colour.

## SHADER: gen-grok41-mandelbrot (gen_grok41_mandelbrot.wgsl)
IDENTITY: Buddhabrot orbit accumulation (Monte-Carlo c sampling) with Mandelbrot body, dwell iso-bands, comet, antenna tip, spectral stars, gliding navigation.
KEEP VERBATIM: 4 params and roles; MC sampler; orbit rainbow; comet; body/dwell/antenna; stars; navigation spring in extraBuffer[133..136]; linear accumulation in A (ACES display only).
MECHANISM INTERROGATION: tactic 5 — the canonical Buddhabrot render ("Nebulabrot") colours by orbit LENGTH (three iteration limits → R/G/B); this file colours by position along the orbit. Tactic 1 — dwell bands use the integer dwell, which bands hard; a smooth potential plus the sign of Im z_n (binary decomposition) is the standard better operator.
ADD:
1. Nebulabrot channels — each orbit's contribution is split into three channels by its length (short → blue, mid → green, long → red) with smooth class weights.
2. Smooth potential + binary-decomposition rays — μ = n − log2(log2|z|) (§12.2E smooth iteration count, bailout 256) drives the bands, and the sign of Im z_n flips the tint, so external rays show as a checker along the dwell bands.
REPAIR (floor, live controls): the spring goal now comes from the Center X/Y sliders (`goalBase`), the click pull no longer multiplies by padding `ripple.w` and ages ripples in real seconds; star band energy reads real FFT bins (`extraBuffer[5+4k]`). Perf (exact): c inside the main cardioid or period-2 bulb never escapes and contributes nothing, so it is skipped before the 64-iteration test.
FORBID: new params, a second spring, replacing the sampler.
A PACKING: unchanged — linear RGB accumulation + presence in A, ACES display only.

## SHADER: kimi-fractal-dreams (kimi_fractal_dreams.wgsl)
IDENTITY: three-layer Burning-Ship Julia with orbit traps, treble filaments, spring-morphed c, click zoom pulses, interior lake from C.
KEEP VERBATIM: 4 params with their original and "honest" second roles; spring in extraBuffer[133..136]; layers/rotation; trap palette; filaments; creases; interior lake; A = ACES display RGBA.
MECHANISM INTERROGATION: tactic 3 — the Burning-Ship `abs()` is a reflection; how many times the orbit was reflected is thrown away (the creases only use closeness to the axes). Tactic 1 — exterior colour uses only the smooth escape time and trap distance; the argument of z along the orbit (stripes) is unused except in the interior.
ADD:
1. Fold-parity checker — count how often each orbit reflected (sign flips before the `abs`, §12.2E fold count as material); odd/even parity swaps the layer's colour channels, tiling the escape region into mirrored chirality regions.
2. Stripe-average colouring — mean of 0.5 + 0.5·sin(5·arg z) over the orbit modulates the layer light, giving the fine wood-grain texture of stripe-average Julia colouring.
REPAIR: per-layer treble "bins" read `plasmaBuffer[1+layer]` (always 0) → real FFT bins 48/64/80 via `extraBuffer[5+bin]`.
FORBID: springs (already there), new params, changing the lake.
A PACKING: unchanged — ACES display RGBA.

## SHADER: multi-fractal-compositor
IDENTITY (as the code actually is): the input image zoomed through five depth-weighted layers with flow-noise wobble, click vortex, chroma split, depth edge glow and fog; name and JSON promise fractal blending that the code does not do.
KEEP VERBATIM: 4 param ids/names/defaults; 5-layer loop; layer speed mix(x, y); click vortex from extraBuffer[10]; fog (w); volumetric alpha; edge glow; no A/C.
MECHANISM INTERROGATION: tactic 3 — `baseColor` (the layer composite, i.e. the "compositor") is computed and never used. Tactic 4 — layers all share one zoom phase at default (x = y) and the zoom is linear 1→5, so they stack as copies, not as a self-similar zoom; the linear wrap also pops. Slider z ("Domain Warp") is unreferenced.
ADD:
1. Staggered octave composite (promotes the dead composite) — layer i runs at phase fract(t·speed + i/5), exponential zoom 2^(2.32·phase), sin² birth/death window; the windowed layers composite into the picture (mix up to 0.55), a Droste-style self-similar zoom with no wrap pop.
2. Zoom dispersion — red and blue taps sample each layer at zoom·(1 ∓ 0.018), a lens-like chromatic fringe that grows with the layer's zoom.
REPAIR / floor: slider z made live in its saved role (flow-noise warp amplitude × (1 + 6z)); bounds guard; `extraBuffer[0]` (bass) was used raw as a UV offset → `plasmaBuffer[0].x · 0.05`; ACES on display; JSON description rewritten to match the code.
FORBID: pretending it is a fractal renderer, new params, springs.
A PACKING: none (HEAD writes no A, reads no C).

## SHADER: gen-3d-sierpinski-chaos
IDENTITY: a chaos-game Sierpinski tetrahedron splatted per pixel with rotation, attractor-biased die, corner flares, age hue, face chroma, cavity, edge filament, temporal accumulation.
KEEP VERBATIM: 4 params; the chaos-game loop, die, projection; all six HEAD ideas; temporal accumulation; A = ACES display RGBA.
MECHANISM INTERROGATION: tactic 3 — the chaos game's state is its address: the last picks name the sub-tetrahedron the point lies in; HEAD keeps `lastVi` only to flare repeats. Tactic 2 — splats are world-space points but have a constant screen radius, so perspective gives no size cue.
ADD:
1. IFS address colouring — the last two vertex picks (16 sub-tetrahedra at level 2) offset the hue, so the self-similar nesting is visible as coloured sub-copies.
2. Perspective splat radius — the squared splat radius scales with (CAMERA_DIST/projZ)² (clamped 0.4–3), so near points are bigger and far points finer.
FORBID: new params, springs, changing the die/attractor.
A PACKING: unchanged — ACES display RGBA (history is display colour).

---

## Formula / mechanism ledger (≤ 2 files per §12.2 row)

| row / mechanism | files |
|---|---|
| E step-count AO | gen_mandelbulb_3d |
| E SDF curvature | gen_mandelbulb_3d |
| E orbit trap (fold-wall) | gen-mandelbox-explorer |
| E smooth iteration count | gen-grok41-mandelbrot |
| E fold count as material | kimi-fractal-dreams |
| F Fresnel–Schlick | gen-mandelbox-explorer |
| F Snell + Cauchy | hyperbolic-dreamweaver-julia |
| derivative distance estimate (Julia) | gen-julia-set |
| none (tactic-derived) | spec-quaternion-julia, gen-audio-spirograph-julia, multi-fractal-compositor, gen-3d-sierpinski-chaos |
