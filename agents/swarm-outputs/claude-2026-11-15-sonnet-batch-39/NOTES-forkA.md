# NOTES — fork A (ambient-liquid-coupled, liquid) — batch-39, 2026-11-15

Worktree `/root/iv-sonnet-batch-39`. No git operations. Edited only: `public/shaders/ambient-liquid-coupled.wgsl`, `public/shaders/liquid.wgsl`, `shader_definitions/advanced-hybrid/ambient-liquid-coupled.json`, `shader_definitions/liquid-effects/liquid.json`.
Evidence: SwiftShader WebGPU, scratch COPY of `agents/mr.mjs` (adds ripple injection via `RIPPLES`, min-of-drained-frame timing, and — **important — re-zeroes `extraBuffer` every frame like the real host**; the stock harness never wipes it, so HEAD's dead spring looks alive there). Saved-default sliders passed explicitly (ambient 0.5,0.5,0.5,0.4; liquid 0.5,0.4,0.5,0.3). `pct` = % of pixels with max-channel |Δ| > 0.02 between the file and the same file with one idea's constant zeroed (`COMPOUND`/`beer`, `BEER_TOP`, `RIM_AMP`, `WAKE_AMP`, `GLINT_AMP`, Snell→HEAD thin lens, vortex velocity→0). Cases: idle (cursor parked, no click), held (0.4,0.6 pressed), move (pressed cursor sweeping (0.2,0.3)→(0.8,0.7)), rip (2 clicks), audrip (2 clicks + bass/mid/treble 0.8/0.5/0.9). **No real-GPU claim of any kind.**

Harness caveat found on the way: HEAD's `hasSpring` block makes the harness's `move` case differ from the real app. With the host-faithful zeroing, `HEAD ≡ all-ideas-off` to maxD ≤ 0.002 (ambient, idle/held/move/rip/576) and exactly 0.000 (liquid, held + 2 clicks).

---

## 1. ambient-liquid-coupled — 1st pass

**KEEP VERBATIM held.** Solver lines (both Laplacians, coupling, damping, velocity/height updates, clamps, press/twist/click impulses, ambient forcing) are textually unchanged except: neighbour loads go through `simLoad()` (Neumann at the two track texels), the spring block is replaced by the track, and the click ring's `pow(x,2)` became a square. Params byte-exact (checked programmatically), roles unchanged. All four sliders live (192 px, ripples + moving held cursor, min→max): wave_strength 41.5 %, viscosity 19.3 %, vortex_strength 3.35 %, layer_separation 30.6 % of pixels >0.02.
**A packing:** raw coupled-height state, unchanged — except texels (0,0)/(1,0), which carry the pointer track (`[mouse.xy, 0, 0.7371]` / `[smoothed per-frame cursor delta, 0, 0.7371]`). Those two pixels' sim state is sacrificed; the solver reads them as the centre value (Neumann) and the track pixels themselves borrow the pixel below as their state (display-only effect on 2 px at the corner). No ACES on A. B untouched.

### Rescue 1 — `vortex_strength` dead: CONFIRMED
HEAD's pointer spring lives in `extraBuffer[133..138]`, re-uploaded as zero every frame (`audioDepth.ts` writes the whole 256-float scratch), so `pointerVelocity ≡ 0` and the only use of the slider (`pointerTwist`) never fires. Proof: HEAD with a moving cursor, vortex 0 vs 1 → **0.00 % / maxD 0.000**; new → **3.10 %** (192 px, 90 frames). Cursor track is now in A texels (cyber-lens scheme) but **stores no clock**: the track is the smoothed per-frame cursor delta (`mix(prev, delta, 0.35)`, delta clamped ±0.08 uv/frame, × 60 → "uv/s"). Reason: the internal colour format can be `rgba16float` (HDR canvas, #1512) and an f16 time quantises to ≥ 8 ms at t≈10 s, which would make a `dt`-based velocity spike. Stroke impulse per frame ∝ cursor distance per frame → a stroke's total twist is its path length at any frame rate. Verified under `A16=1` (real rgba16float A/B/C, 300 frames, moving cursor + clicks): `nan 0`; vortex on vs off still differs (0.43 % >0.02, 5.2 % >0.005); f16 vs f32 of the same shader 0.13 % >0.02. Sentinel 0.7371 compared with tolerance 0.002 (f16 nearest 0.7373).
Spring block deleted (it only raced). `features` loses `spring-interaction` (provably false at HEAD and now absent); description "bounded pointer velocity" is now true.

### Rescue 2 — `pow(negative, 2.0)` in the click ring: fixed by reading (invisible on SwiftShader; HEAD ≡ all-off to 0.002).

### Idea 1 — compound refraction + Beer–Lambert (§12.2F "Beer–Lambert"), `ambient-liquid-coupled.wgsl` L121-141
Lower layer's ray now also inherits 0.8× of the top-surface bend (HEAD: membrane only), and is tinted `exp(-(gap-0.06)·σ)`, σ = (2.4,1.0,0.4), `gap = (top-lower)/nz` (neutral at 0.06 so HEAD's fixed blue tint still holds at a typical gap; torn-through = undimmed/warm). **Visibility finding:** at the default `layer_separation` 0.4 the lower layer carries only a few percent of the mix (|gap|·3.6·0.4, gap p99 0.05 idle / 0.2 held), so the lower-layer part alone is 5.2 % of the frame (move case; 0 % idle). To make the idea visible without changing the blend, the same Beer law is applied to the **top** sample by its own column relative to resting depth 0.1 (`BEER_TOP` 0.4 — 1.0 was too strong: 28 % of an idle frame). The ambient field is NOT quiet at default (top height p1 0.055 / p99 0.249 after 4 s idle), so the top Beer is a gentle wave-height tint everywhere.
Measured new vs idea-1-off (192 / 576): idle 5.2 % (49.6 % >0.005, a faint tint) · held 13.4 / 13.0 · move 26.9 · rip 8.8 / 8.7 · audrip 10.7. Mean luma change small (held 0.507→0.499, move 0.505→0.494).

### Idea 2 — torn-film rim bead (native), L106-117 (+ `bulge` into both UVs, `bead` into colour, `rim` into alpha/depth)
Gap gradient from the 8 neighbour values already loaded (no extra loads): `rim = smoothstep(0.4, 3.0, |∇gap|·res.y/2)` — **slope per uv**, not per pixel (first version used per-pixel thresholds and fell from 6.4 % at 192 px to 0.8 % at 576). Effect: both layers are displaced along the gap gradient (the bead lenses), and a signed highlight/shadow pair (light from upper-left) sits on the two flanks. Quiet where the surface is: idle 0.00 %. Measured vs idea-2-off (192 / 576): held 6.1 / 6.0 · move 8.6 · rip 9.5 / 9.8 · audrip 14.0. Looked at `A_new_held576.png`: the pressed dimple now has a blue beaded rim and a lens-like interior (HEAD: a faint flat disc).

§12.2 rows: Beer–Lambert (ambient only). **Default-look changes to eyeball on a real GPU:** gentle blue/dark tint on wave swells (top Beer), rim beads around pressed/clicked regions, vortex wake dipole when the cursor moves.
Timing (min-of-drained, interleaved, 6 rounds, 256 px, load 18–55 so ±0.3): idle median 1.03 (0.84–1.38), live clicks + held 0.88 (0.79–0.93). Added work: 0 extra texture loads for the rim; 2 extra `exp` for Beer; the removed spring block offsets it. Coordinator re-times alone.
Gates: precommit ✅ · naga-wasm ✅ · dead-sliders 0 new · extraBuffer 0 new (file no longer touches extraBuffer).
JSON: params byte-exact; `x-meta.upgrade.params` added (4 entries); description +21 chars ("layer-separation optics" → "double-refraction Beer optics, torn-film rim"); `spring-interaction` removed. `upgraded-rgba` NOT added (the definition never had it, and the card is a first pass — owner's call; ACES is present).
Open: `Upgraded:` header written 2026-11-15; the two corner texels are a known 2-pixel sacrifice; vortex impulse scale (`·0.012`, `·60`) is HEAD's intended spring-velocity scale, calibrated only by "3 % of frame at a sweeping cursor" — eyeball whether the wake dipole reads as a twist.

---

## 2. liquid — 2nd pass

**KEEP VERBATIM held.** Solver, A raw packing (R=height, G=velocity, B=foam, A=coverage; no ACES on A), Idea 1 (precursor) and Idea 2 (foam drain) of 2026-09-21, caustic, Fresnel tint, Beer tint `exp(-height·…)`, params byte-exact, ACES on writeTexture only. **Proof:** with all new ideas zeroed (Snell → HEAD's thin-lens line, `WAKE_AMP = GLINT_AMP = 0`) the output equals HEAD exactly (192 px, held cursor + 2 clicks + audio: 0.00 % / maxD 0.000). All four sliders live (192 px, 2 clicks): viscosity 39.8 %, turbulence 37.1 %, ripple_strength 46.7 %, color_shift 2.6 % (21 % >0.005; it only scales a tint, as at HEAD).
**A packing:** raw, unchanged.

### Rescue 1 — dead spring term: CONFIRMED by reading + host source
`length(pointerVelocity)·0.008` is identically 0 (`extraBuffer[133..138]` wiped each frame). The spring block and the term are deleted; the cursor is used directly (the race wrote `p = mouse, v = 0` anyway, so the picture is identical — the all-off ≡ HEAD result above covers it). `features` loses `spring-interaction`; description drops "bounded pointer inertia".
### Rescue 2 — `pow(negative, 2.0)`: the main ring and the precursor used `pow((dist-front)·k, 2.0)` with a negative base behind the front → `ringArg*ringArg`. Invisible on SwiftShader (identical result).

### Idea 3 (card 1) — Snell vector refraction (§12.2F), L117-127
`refract(vec3(0,0,-1), normal, 1/1.33)`; lateral = `T.xy / max(-T.z, 0.2)` × column depth `(0.012 + h·0.052)·4`. Calibrated against HEAD's thin lens: ratio 0.99–1.03 at small slopes, 1.12 at g = 0.2, 1.38 at 0.4, 1.86 at 0.8 (magnification now grows steeply with slope). **Sign:** `refract` bends toward −N, so the photo now converges under a mound; HEAD offset the other way (+N.xy). Honest accounting: of the 12–17 % of pixels that change vs HEAD's thin lens at 192 px (idle 11.9, held 17.4, rip 27.5 %), almost all is that sign flip; the **nonlinear (steep-slope) part alone** — new vs a linear small-angle physical-sign variant — is 0.08 % idle, 5.0 % held, 5.8 % rip @192 and 1.1 % rip / 1.7 % held @576. The sign flip is a default-look change (mirror image of the local distortion; magnitude unchanged), please eyeball.
### Idea 4 (card 2) — dispersive wake train (§12.2D deep-water dispersion), L72-93
Three trailing crests per click at `front / sqrt(1 + 1.2·j)` (crest j ~ λ₀/(1+1.2j), c ∝ √λ), alternating +/−/+, 0.72× amplitude per crest, `WAKE_AMP = 1.8`, gated in over the first 0.45 s and damped `exp(-age·mix(0.6,1.3,visc))`; folded into `clickEnergy` (×0.2) so foam follows the crests. Pebble-drop trains that spread with age and crowd toward the centre. (First try at 1.0 amplitude with HEAD-like damping was 1.1 % of the frame — invisible; at 2.4 it was 14.5 % and dominated; 1.8 settled.) Click-only: new vs wake-off rip 16.7 % @192 / 11.3 % @576 (idle/held 0 %, as designed). `audrip` 19.7 % @192 (measured at the same 1.8 amplitude but before the glint was narrowed to a cone).
### Idea 5 (card optional 3) — sun glint, L128-132 + colour
Added because ideas 1+2 were <3 % of the frame by the honest measure. `smoothstep(0.965, 1, dot(normal, sunH))²`, sunH = half-vector for a low upper-left sun, × `coverage`; zero on flat water by construction (first version used `pow(…, 80)` and lit 21 % of an idle frame with a flat sheen — rejected). new vs glint-off: idle 7.2 %, held 6.8 %, rip 8.0 % @192; rip 4.8 %, held 1.5 % @576 (the normal is built from per-pixel neighbour differences exactly as at HEAD, so higher working sizes see gentler slopes; same dependence as HEAD's refraction).

§12.2 rows: Snell vector refraction, Deep-water dispersion (liquid only); sun glint is native (not a table row). No 9-point Laplacian, no Cauchy.
Default look vs HEAD (meanL/stdL, 256-ish): idle 0.499/0.173 → 0.502/0.173; held 0.498/0.170 → 0.507/0.169; rip 0.503/0.170 → 0.508/0.172.
Timing (same method): idle median ≈ 0.76 (0.64–0.97; the removed spring block costs on SwiftShader), clicks + held 1.05 (0.71–1.59 — load-noisy). Coordinator re-times alone.
Gates: precommit ✅ · naga-wasm ✅ · dead-sliders 0 new · extraBuffer 0 new (file no longer touches extraBuffer).
JSON: params byte-exact; `x-meta.upgrade.params` added; description +32 chars; `spring-interaction` removed.
Open: the glint is the most "look" of the three (a sun is assumed upper-left); `GLINT_AMP` is a one-line const if the owner wants it quieter or gone. Header Idea numbering follows the file (1 precursor, 2 foam drain, 3 Snell, 4 wake, 5 glint) — card 1/2/optional-3 map to 3/4/5.

## Not done / not verified
- No real-GPU look (SwiftShader differences and PNGs only). No Vitest/lint/build run (coordinator). Search index / shader lists / ledger untouched.
- Timings are load-noisy (load avg 18–55 during the runs); do not use them as a cost claim.
