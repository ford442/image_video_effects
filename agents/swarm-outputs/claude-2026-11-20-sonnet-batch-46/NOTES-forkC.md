# NOTES — fork C (sonnet/batch-46)

VM = SwiftShader, no real GPU. Renders via `agents/mr.mjs` (SRC=img), timings via `agents/mr_ab.mjs` (interleaved, load on the box was high: single rounds ranged ±30%). Nothing here is visual QA.

---------------------------------------------------------------------------------------------------
## ethereal-swirl-coupled   (public/shaders/ethereal-swirl-coupled.wgsl + shader_definitions/advanced-hybrid/…json)

**Pass:** first pass. Header now carries `Upgraded: 2026-11-20`, `Ideas:`, `A packing:`.

**ADD (as implemented; each is a `// ── Idea n` comment):**
1. **Two-way swirl↔fluid coupling** (tactic 3; D-family "one extra force"): `velOut = vel + flowVec·WIND·edgeDamp`, `densOut = dens + swirlCover·DYE_SEED`. flowVec / cloudDensity were computed and discarded at HEAD; the fluid only ever fed the swirl. Makes the fluid alive with the cursor at rest (ablation: 19% of pixels move >0.02).
2. **Dye-gradient refraction** (§12.2F Snell): the photo is sampled at `uv − ∇dye·REFRACT_PX/res`; dye filaments act as a refractive interface (4 exact neighbour loads of C.w). Ablation 4–5% of pixels at defaults with a click; strongest at ripple dye.
3. **Curl-tinted hue** (§12.2D, real vorticity): `hue += clamp(curl·res.y·0.08, ±0.15)` from the same 4 neighbour loads (HEAD stored a fake `vel.x−vel.y` that nothing read). Ablation ~5%.

**Tried and rejected — vorticity confinement (§12.2D snippet D1).** Implemented per spec (curl at centre + 4 neighbours, N×ω). Unstable at any useful strength on this solver: ε ≥ 0.7 grid-scale noise, ε = 1.5 → |vel| saturates every pixel; with a 2-px stencil or a larger normalisation floor it produced a 4-px lattice. ε ≤ 0.15 is stable but does nothing visible. Reason: advection is ≤ 1 px/frame so the field has almost no numerical vorticity loss to restore, and the global swirl wind (Idea 1) puts curl everywhere to amplify. Dropped, not shipped.

**KEEP VERBATIM (verified):** 4 params + their overloaded roles; advection back-trace (2 px·vel); viscosity; mouse drag + vortex injection constants; click-ripple loop (`config.y` count, ripple.z); edge damp; ±0.5 / 0..2 clamps; baseFlow/turb/flowVec/depthWarp/distortedUV; cloudBase/cloudDetail mix; hsv hue + sat/val; luminance-gated blend (0.5); absorption tint (1,0.85,0.6) and its mix.

**A PACKING:** `A = (vel.x, vel.y, display-luma history, dye density)`; texel (0,0) = `(mouse.xy, 0, 0)` (single writer; first frame = all-zero → no history). C read exactly (`textureLoad`, hand-bilinear `loadHistory` copied body-identical from ethereal-swirl.wgsl). Output ACES display RGB (×1.1 like the sibling), alpha = `0.6 + 0.3·swirlCover + 0.4·dye` (coverage).

**Rescues (HEAD defects, all fixed):**
- `fbm` hashed the continuous coordinate → per-pixel white-noise "clouds". Smooth value noise (`vnoise`, body-identical to the sibling's; plain octaves only — the sibling's billow octaves are its own idea and were not copied). Warp octave counts trimmed (baseFlow 3, turb 4, cloudBase 5, cloudDetail 4) for cost.
- `A(0,0)` mouse history overwritten by the fluid store → prevMouse≈0 → the cursor injected max velocity + vortex while merely hovering. Now single-writer.
- Feedback read `C.rgb = (vel.x, vel.y, vel.x−vel.y)` as the previous colour → `persistence` was "fade to black" (HEAD default mean luma 0.20; with persistence 0 it is 0.40) and a stroke of velocity-as-green trailed the cursor. Now persistence trails display luma (advected with the fluid).
- `textureSampleLevel(dataTextureC, u_sampler)` on rgba32float → exact loads.
- `audio-reactive` claimed, `plasmaBuffer` never indexed → bass×0.4 on vortex gain, mids×0.15 additive flow phase.
- alpha hard `1.0`, no ACES, noise not aspect-correct.

**Default-look consequences to flag:** grain → smooth clouds; picture no longer dimmed/pastel-shifted (mean luma ≈0.53 vs 0.20); hovering the cursor no longer pins the fluid; the green velocity stroke is gone.
**Diff vs HEAD:** 95.6% of pixels differ >0.02 (rescues dominate). **Timing vs HEAD (mr_ab, 384 px, 4 rounds):** paired medians 1.31 / 1.63 / 1.85 / 1.65 → ≈1.6× — **over the 1.3× cap**. Isolated: replacing the new `vnoise` with a single hash drops it to ≈1.2×, so the smooth-noise rescue (4 hashes/octave vs 1) is the cost, not the ideas. Left over cap (rescue is the point; a real GPU does ~100 hashes/px trivially) — flagging.
**Gates:** precommit 1/1, naga-wasm 1/1, dead-sliders pass (0), extrabuffer pass, params byte-identical to HEAD (script compare), NaN 0 at params 0000/1111/0.9-0.1-0.9-1 with mouse down + 2 ripples + audio.
**JSON:** `description` rewritten (visible behaviour changed), `features += upgraded-rgba`, `x-meta.upgrade.params` added (aligned to saved params). `params` untouched.

---------------------------------------------------------------------------------------------------
## hybrid-chromatic-liquid   (public/shaders/hybrid-chromatic-liquid.wgsl + shader_definitions/hybrid/…json)

**Pass:** first pass AND a **restoration** — see below. Header: `Upgraded: 2026-11-20`, `Ideas:`, `A packing:`.

**Big finding.** HEAD's WGSL was a halftone/ink print (dot size / edge threshold / levels / ink density on the 4 sliders; naga round-trip `_eNN` names; "audio" = `u.config.y` = ripple count). The JSON (name, description, slider ids `flow_scale / distortion / chromatic / flow_speed`, features, `x-meta.chunks_used`) all describe a **flow-field liquid with RGB split**. `git log`: `09c8ff85` created the real effect (it did not compile — `let rOffset` was assigned); `9983b1eb` "Fix batch of 24 shaders via subagent" replaced the body wholesale instead of changing `let`→`var`. Every UI label was therefore wrong at HEAD (param theft, §4.4). **Decision: restore the JSON-defined algorithm and upgrade that.** If the user would rather keep the halftone it is `git show origin/main:public/shaders/hybrid-chromatic-liquid.wgsl` and should get its own catalog id + params; the two cannot share these four sliders.

**KEEP VERBATIM (from 09c8ff85, constants unchanged):** flowScale `mix(1,5,x)`, distortion `mix(0.02,0.15,y)`, chromatic `z·0.08`, speed `mix(0.2,1.5,w)`; 4-octave angle fbm with the (5.2,1.3) offset; 5-step accumulated displacement with `(1−fi)` taper; R/G/B offsets (R: `+(flow+(1,0))·c`, B: `−`); `fract` wrap; blue highlight `(0.3,0.5,0.7)·mag·5`; `(0.8,0.9,1.0)` rim mix ×0.3; alpha `mix(0.5,1,luma+2·mag)`; depth·(1−mag).

**ADD:**
1. **Slope-driven dispersion** (§12.2F Snell direction; tactic 4): surface height = first-step `noiseVal` + 2 forward-difference `fbm2(…,3)` → slope → normal. Split vector = `(flow+(1,0))·mix(0.6,1.5,steep) + n.xy·3.0`, still scaled by the `chromatic` slider. Ablation: 65% of pixels differ >0.02 (fringes now follow ripple steepness). Not Cauchy (reserved for the prismatic lens).
2. **Surface-normal Fresnel + specular glint** (§12.2F Fresnel–Schlick): Fresnel cosθ = `n.z·(1−edgeDist)` (flat water == HEAD-original Fresnel), plus a Blinn glint `pow(n·H,160)·0.4` through `acesToneMap`. Ablation: 17% of pixels >0.02.

**Rescues:** body restored (above); `let`→`var` for the wrap; `@workgroup_size(8,8,1)`→16×16; "audio" is now `plasmaBuffer[0].x` (bass swells distortion ×(1+0.35·bass), also the click-ring) and `.y` (additive flow phase); HEAD's pointer behaviour (held-click ring + cursor pull, HEAD constants) ported onto the liquid's sample point so JSON `mouse-driven` stays true; `normalize(uv−mouse+0.001)` → guarded divide; noise in aspect-correct space; `pow` base clamped in `fresnelSchlick`.

**ACES:** only on the new glint term. The photograph and the original blue highlight are deliberately left ungraded (ACES on the photo is a grade, not this effect); the highlight is unbounded by design (at distortion=1 mean luma ≈1.05 → blown) — original behaviour, flagged, not changed.
**A PACKING:** display RGBA copied to A (nothing reads it as a field; no feedback). Depth as the original.
**Diff vs HEAD:** 100% (different effect, by design). **Timing:** HEAD halftone is a 9-tap shader, so ratio is meaningless (≈2.0–2.4×); vs the **restored original** the ideas cost ≈1.3–1.5× (2 extra `fbm2(…,3)` + a `pow`). Over cap; flagging.
**Gates:** precommit 1/1, naga-wasm 1/1, dead-sliders pass (0 — all four sliders read), extrabuffer pass, params byte-identical to HEAD, NaN 0 at 0000/1111/mixed with mouse down + audio.
**JSON:** description corrected (the old one described the halftone's "dot size and ink density"), `features += upgraded-rgba`, `x-meta.upgrade.params` added. `params` untouched.

---------------------------------------------------------------------------------------------------
## Formula rows used (for COORDINATOR_REVIEW de-dup)
- ethereal-swirl-coupled: coupling term (D-family extra force, tactic 3), Snell refraction (§12.2F) on the dye gradient, real curl (§12.2D).
- hybrid-chromatic-liquid: Snell refraction direction → slope-driven dispersion (§12.2F), Fresnel–Schlick + glint (§12.2F).
- Both use a "Snell"-flavoured refraction idea (different quantities: dye gradient vs displacement-noise slope; different effects: photo shift vs RGB split) — coordinator may want to count that as the same row twice (≤2 allowed).

## Not verified / external
Real-GPU look (esp. the 1.6–2× SwiftShader cost, the blown highlight at max distortion, the pastel default of ethereal-swirl-coupled). Non-square frames (harness is square-only; aspect handling is by construction). Real click-ripple aging (harness holds `elapsed` constant, so the dye blob there is continuously re-seeded).
