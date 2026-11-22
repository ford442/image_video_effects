# BRIEFS — fork C (temporal-decay-multiresolution, temporal-layered-time-stamps)

Written BEFORE any WGSL edit. HEAD = `scratchpad/coord/head/<id>.wgsl` (copied to `scratchpad/c/<id>_head.wgsl`). Harness: `mr_hist.mjs` (private copy `scratchpad/c/mr_hist_c.mjs` adds absolute-start ripples for the click check). Engine fact verified this session: the ring stores the slot's **output** (`slotDispatch.ts:204` sets `blitReadTex = writeTex`; `frame.ts:223` copies it into layer `head`, then `head = (head+1) % layers`), so both files read *their own previous outputs* through binding 13 — they are feedback shaders. The stock 1-layer-ring harness hides that; that is why the 2026-10-30 pass could not see HEAD defect R1 below.

## HEAD verification (coordinator table + mine)

| check | decay-multiresolution | layered-time-stamps |
|---|---|---|
| tags true? | `mouse-driven` TRUE (pointer 0.5,0.5 → 0.2,0.8: 59 % of px differ); `click-reactive` TRUE (one ripple at t−0.4 s: 7.7 % px differ, max 0.30); `audio-reactive` TRUE (bass/mids/treble read); `upgraded-rgba` FALSE (no ACES) | `mouse-driven` TRUE (spiral centre; 98 % px differ); `audio-reactive` TRUE (bass → warp, mids → sat); `upgraded-rgba` FALSE (no ACES) |
| ring depth | D=8, 4, 1: NaN 0, sane picture (ageCap/reach logic correct; D=1 collapses to the live frame) | D=8, 4, 1: NaN 0, sane picture (echoLayers clamps to reach; D=1 → accumulated = base) |
| gates at HEAD | precommit 1/1, naga-wasm OK, dead-sliders PASS, extrabuffer 0 violations | same |

## RESCUES (found at HEAD)

**temporal-layered-time-stamps — R1 (the important one): onion-skin outlines are a positive-feedback loop.** Outlines are detected on the ring frames, which are previous *outputs* that already contain last frame's ink; each frame re-detects the ink line (both flanks of a 1–2 px line respond at 1.5 px offsets), re-inks it one pixel wider, so ink area grows every frame. HEAD at defaults, moving scene: frame 6 shows stacked, clean tinted outlines of the disc and squares (the intended look); frame 24 is full-frame outline noise burying the picture (`scratchpad/c/h_lay_f6.png`, `h_lay_f24.png`, `h_lay_d8.png` at 40 frames). Attribution: with `onionCov = 0` the same scene is stable at 60 frames (`lay_noink_f60.png`), so the stamps/tint/warp feedback is fine and only the outline loop diverges. **Fix:** outline from a *clean* signal the ink can never enter: store the live frame's luma in A as a 4-deep ring (`A = (L_now, C.r, C.g, C.b)`; next frame `C.rgba` = luma at ages 1..4) and detect edges there (exact `textureLoad(dataTextureC)`). Cost: 3 loads/age (a vec4 gives all 4 ages at that texel) replace HEAD's 2 filtered ring samples/age. Behaviour: sheets 1–4 are outlined (HEAD: up to 8, but ages 5–8 carry weight ≤ 0.46 and the default is 4 sheets); past positions of moving objects are still outlined (that is what the clean ring remembers), the ink no longer feeds itself. **A packing changes** from "display RGBA" to "clean-luma history ring" — nothing reads A except this shader's own next-frame C (HEAD never loaded C at all), so no downstream consumer exists; said loudly in the header and notes.

**temporal-decay-multiresolution — R2: `plasmaBuffer[regionBin]` (regionBin 1..8) is never uploaded** — the engine writes only `plasmaBuffer[0]` (`audioDepth.ts:62-71`), so the per-region audio term `fftRegion` is a permanent 0. Re-source it from the real FFT bins `extraBuffer[5..132]` (guarded). Effect ≤ 1 % of a decay constant (`× 0.01 / 0.008`) — a dead term made live, not a visible change; no claim beyond that.
**R3 (reported, not changed):** the `extraBuffer[133..138]` pointer spring never integrates in the TS engine (`writeExtraBuffer` zeroes `[133..255]` before every dispatch; thread (0,0) just writes `rawMouse` back, readers see `rawMouse` either way — benign race, pixel-identical to using `u.zoom_config.yz` directly). The code comment and JSON description call it "spring-following". Engine decision, left alone (batch-51 precedent); JSON description reworded to "pointer-centred" so it stops claiming a spring. Header band comment (R=ages 1–2 …) is stale vs. the overlapping windows shipped on 2026-10-30; refreshed.

## Idea Card — temporal-decay-multiresolution

```
SHADER: temporal-decay-multiresolution
IDENTITY: four timescales pulled from the history ring show up as R=fast, G=medium, B=slow, A=ultra-slow luma, each with its own decay slider, max-held against the live frame
KEEP VERBATIM: 4 params + roles; overlapping exponential windows (fast 1–3 / medium 3–6 / slow 5–7); cross-scale cascade; stationary mute; click time-inversion rings; mouse history-lens; per-channel max(current, held·decay); A packing = display RGB with A = ultra-slow luminance (unchanged); ring depth handling (8/4/1)
ADD:
  1. Scale-coupled timescales — a temporal pyramid's slower levels are also spatially coarser (this file is literally "multiresolution" but only the time axis differs per band). Ring age `a` is read at a tap offset of radius ρ(a) = {0,0,1,1,1.7,1.7,1.7} px (golden-angle direction per age), so the medium/slow windows average their ages at different offsets = a free 3-tap softening of the slow band; zero extra samples.
  2. Temporal band-pass glint (Eulerian-magnification style) — `bp = luma(medK − slowK)` is already implied by the windows the file builds (promoted intermediate, tactic 3); its positive part (what has risen above the long-run baseline = arrivals) lifts the held colour a little. The max-hold floor (out ≥ current) is kept: no negative part, no new param, gain a literal scaled by the existing `(1 − origBlend)` role.
FORBID on this file: springs, IQ palettes, ACES on the photo path (P-ACES: nothing here emits beyond range), a second set of click rings, new params
A PACKING: display RGB, A = ultra-slow luminance (unchanged)
```
§12.1: tactic 1 (kernel — the window is exponential in time only; the pyramid analogue is exponential in scale too) → idea 1. Tactic 2 (physics one step further — a leaky-integrator bank's band-pass is the difference of two adjacent low-passes) → idea 2. Tactic 3 (promote an intermediate: `medK`, `slowK` are computed, only `agree`/cascade use them) → idea 2. Tactic 6 (history the shader owns — it reads outputs, so the glint must be bounded: clamp + max-hold floor keep the feedback loop gain < 1). §12.4: no §12.2 row used (domain-native). Expert test: a vision engineer calls (1) "scale-time coupling" and (2) "temporal band-pass amplification" — both standard temporal-pyramid vocabulary. Deletion test passes both ways (without either the file is still the decay bank; either alone is not it).
Pre-registered failure rule: if idea 1 differs from HEAD in < 1 % of pixels at defaults on the moving scene it is invisible and is dropped, said so in the notes.

## Idea Card — temporal-layered-time-stamps

```
SHADER: temporal-layered-time-stamps
IDENTITY: a stack of 4–8 past frames, each hue-tinted, spiralled about the cursor, peg-shifted and smeared, with the sheets inked in their own hue like an animator's onion skin
KEEP VERBATIM: 4 params + roles; per-age spiral about the pointer; peg-bar shift; inter-stamp smear; exponential sheet weights; per-layer hue tint; onion outline *look* (smoothstep(0.04,0.18) on a 1.5 px luma gradient, ink coverage 0.35+0.5·colour_intensity); semantic alpha; ring depth handling
ADD: none new — SATURATED. Four shipped ideas on the line; the honest work this pass is R1 above (the outline idea was shipped but diverges within ~20 frames of real use because the ring feeds it its own ink). I do not invent a fifth idea; `Upgraded:` is not bumped (rescue-only).
FORBID: springs, clicks (not a click effect), ACES (P-ACES: photo composite, nothing emitted), new params
A PACKING: CHANGES — clean-luma history ring (A.r = live luma, A.g/b/a = C.r/g/b); HEAD's display copy was never read by anything
```
§12.1: tactic 6 → R1 (use the history the shader owns *without* its own ink in it). Tactic 5 candidates considered and dropped (exposure-sheet holds; line-weight taper; flip-through depth lens around the pointer needs a loop to 8 sheets everywhere ≈ 2× cost; cel-stack product transmission replaces the weighted mean = reimagining; motion-gating the ink would erase outlines on still photographs, which is how most users run this).

## Tags (P-ACES, §8)
Neither file has ACES and neither emits light beyond the source range → `upgraded-rgba` is removed from the WGSL `Features:` line and from JSON `features` in both files (tag-without-ACES is the 2026-06 drift bug). `mouse-driven`, `audio-reactive`, `click-reactive` (decay) stay: verified true above.
