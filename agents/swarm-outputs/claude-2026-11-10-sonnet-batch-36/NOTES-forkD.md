# NOTES — fork D (neon-warp, hybrid-fractal-feedback)

HEAD = 75dbf877. Final files: `neon-warp.wgsl` (last edit 02:57), `hybrid-fractal-feedback.wgsl` (last edit 03:26, includes the `histTaps` change). Every number below was taken on those files unless it says otherwise. All renders: SwiftShader WebGPU, `agents/mr.mjs` extended in a scratch copy (ripple injection, per-frame zeroing of `extraBuffer` like the app, step-function pointer, aspect, honest `onSubmittedWorkDone` timing). **No real-GPU visual or cost claims.** "Visibility" = % of pixels whose max-channel |Δ| > 0.02 between the file and the same file with that idea's constant neutralised (`GD_G=0`, `CA_ON=0`, `VEIN_ON=0` + integer iteration, `FB_ON=0`), default sliders, step-function pointer.

## neon-warp  (3 ideas shipped 2026-10-05 → +2)

KEEP VERBATIM held: 4 params and roles, ThermalField/addSource + plume stretch, shipped ideas 1–3, ripple sources, idle ember 0.15 / held 1.4, whip, blackbody glow + fog glow, 18 % advected exact-C history mix, saturation 1.18, ACES on display, depth lifted by heat. Saved `params` byte-exact (JSON diff: description +25 chars only).

Numbering: HEAD already has `// ── Idea 1/2/3` comments, so the new ideas are **Idea 4** and **Idea 5** in the WGSL (card ideas 1 and 2).

| Idea | Where | Visibility, default sliders (192 px / 576 px) |
|---|---|---|
| 4 Gladstone–Dale density refraction (native) | consts L59–63, code L134–145 | held pointer 15.7 % / 15.5 %; idle ember 5.5 % / 5.2 % |
| 5 Planck-cooling afterglow (native) | consts L64–70, code L157–175, store L189 | moving held pointer (60 f) 25.3 % / 25.3 % (17.3 % / 17.2 % > 0.1); static pointer 0 % by design (a trail needs motion) |

**Idea 4.** `f(heat) = ((1+g·ref)/(1+g·heat))²`, g = 1.5, ref = 0.5, capped at 3, multiplies the whole `grad·(−0.3)+whip` displacement. **Deviation from the card:** normalised at heat = 0.5 (not 1.0) so the *idle* ember keeps a sensible magnitude (normalising at 1 would make f(0.15) ≈ 4.2). Core flattens (f(1.4) ≈ 0.32), shoulder refracts ×2–3.

**Idea 5 — deviation from the card's mechanism, same idea.** The card tinted the 18 % colour history toward red. That history also holds the *photo* (A.rgb = displaced picture + glow), so tinting it casts every static frame warm, and "glow = hist − photo" turns every moving video edge into a red ghost. Instead a **per-pixel heat memory** is kept: `mem = max(min(field.heat, 2), memPrev·exp(−cooling·1.3/60) − 0.008)`, and the trail glows from `blackbodyRGB(300 + mem·6000)` — the *same* ramp as the live ember, so white → yellow → orange → red → dark falls out of the physics. `max` keeps the live ember untouched and bounds the memory at 2. Decay is keyed to **Cooling** (half-life ≈ 1.5 s at 0 → 0.24 s at 1; ≈ 0.45 s at the default). The memory is not advected (the colour history's `advect` pulls toward the source up to 0.15 uv and would collapse the trail onto the cursor). Alpha: `max(field.heat, mem)` so the trail has coverage. The trail glow is behind `if (mem > 0.06)` (identical result, because the smoothstep is 0 below that; SwiftShader found the branch cheaper).

**A packing change (declared in the header):** `A.rgb` unchanged; **`A.a = 10 + mem`**, validity band 9.5–12.5 (glitch-reveal's idiom) — HEAD stored the output alpha there and nothing read it. `writeTexture` alpha is still the semantic alpha. A foreign C alpha in 10..12 (glitch-reveal) would show a brief trail after a shader switch. The `− 0.008` floor exists because rgba16float has step 2⁻⁷ at 10..16: a pure ×0.97 decay stalls a faint trail forever (A16 vs f32 on a moving run: 1.2 % of pixels differ, max 0.054).

Slider sweep (held, 30 f, % px > 0.02 slider 0 vs 1): Emission 36.6, Diffusion 64.5, Refraction 25.1, **Cooling 0.0** (no effect for a static pointer in the new file — the afterglow needs motion). Moving pointer (60 f): Diffusion 40.8, Cooling 36.4. Dead-slider audit: 0.

Default-look (meanL HEAD → NEW, 192 px): idle 0.521 → 0.521; held 0.591 → 0.593; moving held pointer 0.550 → 0.576 (meanA 0.472 → 0.518); click ripples 0.593 → 0.622; audio 0.564 → 0.564.

Boundedness: 300 frames, Cooling = 0, Diffusion = Emission = Refraction = 1, hot audio, held + moving, f32 and A16 → `nan` 0, meanL 0.632 / 0.634 (no growth); static held 300 frames HEAD 0.708 vs NEW 0.707. (Taken on this file; unchanged since.)

Cost (SwiftShader CPU, frameMs median, alternating HEAD/NEW runs): 192 px 12.0 → 13.5 (1.12×); 576 px 98 → 85 (0.87×, noisy; min-ratio 1.12×).

Rescues: none found at HEAD. Not touched: `advect`, schlieren, mirage.

## hybrid-fractal-feedback  (first pass; 2026-05-23 hygiene header only → Ideas line added)

KEEP VERBATIM held: 4 params and roles, z²+c / 45 iterations / c = mix(cBase, cMouse, 0.5)·(1+bass·0.1)+clickC, accumulativeAlpha, RGB-delay split along `delayVec`, blend over the current input, depth lowering, A = accumulated RGBA.

| Idea | Where | Visibility, default sliders, held pointer, 120 f (192 px / 576 px) |
|---|---|---|
| 1 smooth iteration + orbit-trap veins (§12.2E) | consts L20–23, loop L184–208 (shade L206–208) | 72.0 % / 71.7 % (14.3 % / 14.4 % > 0.1) |
| 2 video-feedback transform (native) | consts L24–30, L141–159 (bilerp taps L71–95, used L219–222) | 64.6 % / 64.6 % (29.4 % / 29.6 % > 0.1) |

**Idea 1.** Same z²+c, 45 iterations, but the loop keeps running to |z|² > 64 so `nu = n − log2(log|z|/log 2)` (the continuous radius-2 index) is smooth. A circle orbit trap (radius 0.55, measured as `|r² − R²|`, no sqrt per iteration) gives `vein = exp(−6·trapD)`: `veinShade = 0.5 + 0.5·vein` multiplies the palette and `trapD·0.35` shifts its phase. HEAD's interior was one flat colour (every bounded point = 44/45); it now has contour veins. (Earlier split on a previous revision: veins alone ≈ 56 %, smooth-count alone ≈ 27 %; not re-split on the final file.)

**Idea 2.** History is read at `pivot + R(θ)·(uv − pivot)·s` in aspect-correct space, via a hand-rolled exact bilerp from four `textureLoad`s (`histTaps`). Pivot = Julia origin leaning 30 % toward the sprung pointer. Drift per frame is proportional to the alpha the history sheds per frame (`accumulationRate·0.08`), so a trail's total travel over its lifetime is constant (~16 % scale, ~14°) at every Feedback Strength and frame rate. **First attempt used per-second (dt-scaled) rates and washed the whole frame green** at a 30 fps cadence and at Feedback 0 (41 % travel); retuned and verified: at Feedback 0 after 600 frames (moving pointer, hot audio) the haze is a soft halo around the veined set, not a frame wash.

**Cost trim that changes how the RGB-delay taps are read (final file):** the red/blue delay taps used to be two more full bilerps (8 more loads). They now come from the SAME four texels as the centre tap: a bilinear field is `v + gx·dx + gy·dy + cross·dx·dy` inside its cell, which is exact there, and the result is clamped to the four texels' range if the delay (≤ 0.006 uv) reaches past the cell. Against the exact-bilerp version: 0.00 % of px > 0.02 at default audio, 0.03 % (192) / 0.11 % (576) with treble 0.9, max |Δ| 0.078; meanL identical.

Rescues:
- **R1 dead spring → A-texel scheme (chosen, not the raw pointer).** `extraBuffer[133..138]` is re-zeroed every frame, so HEAD's Julia c followed the raw pointer. Revived with texels (0,0) = (pos.xy, vel.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371), cloned from `chroma-kinetic` incl. the f16 rest-snap. Evidence it is worth it, pointer teleport (0.2,0.2)→(0.8,0.8) at frame 40: mean |frame N+1 − frame N| right after the jump 0.0039 raw vs **0.0020** sprung, and the sprung picture is still moving 1 s later (0.0505 vs 0.0404 over frames 60→80). Modest, because the accumulation already smooths a jump. Costs 2 texel loads and 2 invisible corner texels (history read at those texels is masked in `histTexel`); a static pointer is **bit-identical** to the raw-pointer variant in A16 and f32; corner pixels of `writeTexture` continuous (0.298, 0.295, 0.295).
- **R2** filtering `u_sampler` on C → exact loads. HEAD sampled at `gid/res` (a texel corner): a 2×2 box blur and +0.5 px drift every frame; gone.
- **R3** `plasmaBuffer[1..8]` (per-region shimmer) was out of range, read as 0 → each 4×4 region now listens to bass/mids/treble by index mod 3. At audio 0 the picture is unchanged.
- **R4** no tone-map → ACES on the **fractal term only** before it is mixed over the photo (the photo is already display-referred); A keeps the pre-ACES accumulation. JSON gains `aces-tone-map`.
- **R5** aspect: `z.x *= aspect` (verified on 576×324: round Julia spirals instead of stretched).
- **R6** `uv = (gid+0.5)/res`.

Boundedness, final file: 300 frames, 128 px, hot audio (0.9/0.9/0.9), moving pointer — Feedback = 1: `nan` 0, meanL 0.258 f32 / 0.258 A16; Feedback = 0: `nan` 0, meanL 0.456 / 0.457. Earlier 600-frame runs (pre-`histTaps` revision) also had `nan` 0 and f32 = A16. The history is a convex combination, and the delay taps are clamped to the four texels' range.

Default-look (meanL HEAD → NEW, 192 px, P = 0.4,0.7,0.3,0.5): idle 0.323 → 0.347; held 0.345 → 0.362 (stdL 0.121 → 0.108); moving held pointer 0.264 → 0.317; audio 0.337 → 0.369; click ripples 0.360 → 0.395. Large intended change: the flat green blob becomes a veined set with an outward-streaming halo; ACES lifts the fractal term; the aspect fix changes 16:9 framing.

**Cost — over budget.** 576 px, 30 frames, alternating runs, medians: HEAD 42.5 ms → NEW 58.5 ms (**1.38×**; a 5-rep run gave 42 → 59, 1.40×; the exact-bilerp version before the trim was 67, 1.60×). 192 px was 1.04× median on the pre-trim version (not re-run on the final file). Ablations on the final file (576 px, 4 reps, ms): no orbit trap 56, no spring-state loads 57.5, history read as one nearest load 51.5 (1.21×) — no single removal reaches 1.3×, and the trap is half of Idea 1. Two "optimisations" (a fast-path `if` in the bilerp, an `if (i < 16)` around the trap) were slower on SwiftShader and were reverted; divergent branches cost more than the ALU they skip there. Real-GPU cost is unknown.

## Gates (final files, run 04:4x)
`wgsl_precommit_gate.py --files`: both pass. `verify-naga-wasm.mjs --files`: both valid (0 new). `audit:dead-sliders -- --files neon-warp hybrid-fractal-feedback`: 2 scanned, 0 new dead. `audit:extrabuffer`: 0 new violations, 0 dynamic-index writes outside baseline.

## Open items / could not verify
- Real-GPU look and cost; harness time is SwiftShader CPU time.
- hybrid frameMs ratio 1.38× at 576 px exceeds the 1.3× target; no further trim attempted after the coordinator's stop.
- **RGB Channel Delay is nearly dead at HEAD** (delay ≤ 0.002 uv acting on a smooth history). Left as is (a fix changes the default look); worth a decision.
- Feedback Strength is semantically inverted for trail length at HEAD (higher = faster alpha shed); untouched.
- Frame-rate dependence: neon-warp's afterglow decay and hybrid's alpha shed are per-frame (60 fps cadence), like HEAD's own history.
- A foreign shader's C.a in 10..12 gives a brief neon-warp afterglow after a switch.
- Search index not touched (coordinator).

---

## Round 2 — reviewer-C fixes (finished by the coordinator; fork D stopped responding mid-round)

Measured by the coordinator on the committed files, SwiftShader, 576 px, alternating HEAD/NEW runs, default sliders. No real-GPU claims.

### neon-warp
| Reviewer finding | Fix | Measured now |
|---|---|---|
| A.a = 10 + mem collides with glitch-reveal / pixel-reveal / mosaic-reveal band | marker moved to `A.a = 13 + mem`, validity band 12.5–15.5 (`CA_BASE`); mem ≤ 2 keeps an rgba16float A at step 2⁻⁷ | `SEEDC=0.4,0.4,0.4,10.7` (a reveal-shader leftover): new vs HEAD 7.14 % px > 0.02, identical to the no-seed idle run (7.14 %) → no milky whiteout |
| held-drag trail blows out ~half the frame | trail glow scaled by `CA_GAIN = 0.55`, mask opens at `CA_LO = 0.02` and saturates at `CA_HI = 0.30` | held-drag meanL 0.589 (HEAD) → 0.594; 0.0 % of pixels > 0.95 in HEAD and NEW |
| idea 5 invisible for hover | free-moving unheld ember (0.15) now leaves a faint dim-red smear | hover run: 8.8 % px differ from HEAD vs 7.1 % idle → the smear adds ~1.6 % of the frame (faint by design); static pointer and bass alone still give none (a trail needs motion) |
| idle ember 2.4× HEAD (idea 4) | `GD_MAX` 3.0 → 1.3 | idle meanL 0.521 → 0.522 |
| decay per-frame, not per-second | disclosed in the header (trail length scales with fps like HEAD's 18 % history) | — |

Cost: HEAD median 57 ms, NEW median 65 ms ≈ **1.15×** (5 alternating runs at 576 px).

### hybrid-fractal-feedback
| Reviewer finding | Fix | Measured now |
|---|---|---|
| cyber-lens leftover C misread as spring state | `stateOk` also requires `st1.y == st1.z == 0`, `st1.x ∈ [0,1)`, (pos, vel) in sane ranges | structural — not re-rendered with a cyber-lens seed |
| audio shimmer was hard columns | three voices on soft diagonal cosine bands (weights sum to 1); audio 0 unchanged | structural + fork D's earlier renders |
| frameMs 1.5–1.6× HEAD | R/B delay taps now read off the shared four-texel bilerp (8 fewer loads) | HEAD median 50 ms, NEW median 65 ms ≈ **1.30×** (5 alternating runs at 576 px) — at the limit, not under it |

**OPEN (not fixed):** the RGB Channel Delay slider is live but weaker than at HEAD. Slider 0 → 1, 60 frames, held pointer, 576 px: HEAD 1.54 % of pixels > 0.02 (mean |Δ| 0.0012); NEW 0.23 % (mean |Δ| 0.0008). At the default 0.3 the effect is 0.02 % (HEAD 0.20 %), i.e. invisible. Cause: the delay reaches ~3.5 texels at 576 px but the shared-bilerp shortcut clamps to the four texels' range. Restoring full separate bilerps costs the 8 loads back (≈ the 1.5× that was trimmed). Left as an explicit owner trade-off: cost or slider strength.

Gates on both files: precommit ✅, `verify-naga-wasm --files` ✅, `audit:dead-sliders` ✅ (0), `audit:extrabuffer` ✅ (0). The `wgsl_validation.json knownFailures.ratchet is 5 but ids lists 4` line that appears under precommit is the existing main failure.
