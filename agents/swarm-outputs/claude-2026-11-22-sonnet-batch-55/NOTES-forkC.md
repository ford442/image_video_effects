# NOTES — fork C (mouse-hyperbolic-navigator, breathing-kaleidoscope-morph)

Cards + HEAD defect verification: `BRIEFS-forkC.md`. Scratch (renders, HEAD copies, ablations): `/tmp/claude-0/-root-image-video-effects/741dbe8f-87a6-4dc9-8039-cfc9fd9fdfde/scratchpad/c/`.
Files touched: `public/shaders/mouse-hyperbolic-navigator.wgsl`, `public/shaders/breathing-kaleidoscope-morph.wgsl`, and the `description` string of their two JSONs. Nothing committed; no shared generated file touched (the gate runs rewrote `reports/wgsl_precommit_report.json` — coordinator discards).

## mouse-hyperbolic-navigator

**KEPT VERBATIM:** mobiusDisk / hyperbolicTile / hyperbolicDistOrigin, the four params and their roles, ring gutters + horo pulse, click hyperbolic ripples, Cauchy R/B split on Boundary Glow, ACES display, alpha = hDist/3·srcA, depth passthrough. **A packing:** ACES display RGBA (unchanged).

**Ideas in the diff (grep `── Idea`):**
1. *Conformal gutter* — `gutterHalf = clamp(0.084·N/(4π)·(1−r²)/r, 0.006, 0.08)`: wedge mortar of constant hyperbolic width, capped at HEAD's 0.08 in the middle, hairline at the rim. Not a §12.2 row.
2. *Circle-Limit two-colouring* — `wedgeId`/`ringId` (the integers `fract` threw away) → `parity` → ±8 % value and warm/cool ±4 % tint; the steps land under the mortar/ring gutters. Not a §12.2 row.

**Rescues (default picture changes; 64.6 % of pixels differ from HEAD at defaults and at mouse (0.7,0.4); meanL 0.306 → 0.305, meanA 0.162 → 0.162, i.e. the look moves, the exposure does not):**
- |a| could reach 1.08 (default speed, canvas corner) / 1.9 (max speed) → Möbius left the disk and the picture collapsed to one blob (HEAD render, mouse 0.95,0.95). Now `a · inverseSqrt(1+|a|²/0.94²)`; ≤ 1 % change for |a| < 0.15, so a centred pointer is untouched.
- tileCount `mix(3,12,p)` fractional (default 7.5) → hard seam at the atan2 cut. Now `round(...)`, default 8 (a stepped slider: 10 positions).
- Mortar was measured from fract == 0.5 (mid-wedge); the image discontinuity is at fract wrap. Mortar moved onto the real seam.
- JSON `audio-reactive` was a lie (no `plasmaBuffer` read). Now true: bass drifts the Möbius view point (`a += (cos .37t, sin .49t)·bass·0.12`, measured 67.8 % pixels differ at bass 0.9), treble ×(1+1.5·treble) on the horocycle pulse. Mids unused.
- `max(color, 0)` before ACES: floor only. Not a verified defect (negative ripple lobes darkened, mean Δblue −0.032; 0.9 % brightened on a 0.02 source).
- C stays unread (stateless navigator); A write = display RGBA for the downstream slot. No B. No spring.

**Header:** `Upgraded: 2026-10-27, 2026-11-22`; `Ideas:` extended; `Features:` gains `audio-reactive`. JSON `features` already had it (now true); `params` / `features` / `x-meta` byte-identical, description extended.

## breathing-kaleidoscope-morph

**KEPT VERBATIM:** the 4 params and roles (cycle_speed → breath + kernel radius, segments, rotation_speed → twist + gradient boost, breath_depth → max twist), ping_pong triangle breath, abs(fract) mirror fold, `finalUV = mix(uv, kaleidoUV, blend)`, elliptical structuring element around the pointer, golden-ratio per-segment erosion/dilation blend, gradient·0.3, white top-hat re-injection, mirror-seam bevel, alpha = top-hat luma, click ripple displacement, depth passthrough. **A packing:** display RGB + top-hat luma in alpha (unchanged), now also stored to A.

**Ideas in the diff:**
1. *Reflection loss per mirror bounce* (§12.2E fold count as material) — `folds = min(k, N−k)` with `k` = cell index mod N; `finalRGB *= (0.91, 0.93, 0.955)^(folds·blend)`. Ablated (ρ = 1): 84.4 % pixels differ, mean |Δ| 15.6/255 — the strongest visible change after the Segments rescue.
2. *Kramer–Bruckner toggle mapping* — snap toward erosion or dilation, whichever is luma-nearer to the centre sample, using `minLuma/maxLuma/centerLuma` (previously accumulated per tap and never read); mixed at 0.4 over the per-segment blend. Ablated (mix 0): 36.6 % pixels differ, mean |Δ| 4.8/255 (deliberately quiet). No new taps. Not a §12.2 row.

**Rescues (default picture changes completely: HEAD had no kaleidoscope — 99.3 % pixels differ at t = 2 s, meanL 0.389 → 0.442):**
- **Segments dead:** `max(1.0, slider∈[0,1])` ≡ 1. HEAD at 0 / 0.5 / 1: 0.00 % pixels differ. Now `round(mix(3,12,p))`, default 8. This also makes both 2026-11-10 ideas (seam bevel "along every reflecting edge", per-segment morph) act for the first time.
- **`zoom_config.x` is time, read as audio:** `audioReactivity = 1+0.3t` inside the phase → breath/twist accelerate without bound. Phase-matched test (t = 1 vs 61 s, same breath phase, frames 50 ms apart): HEAD 85.4 % → 96.5 % pixels change; NEW 60.5 % → 60.5 %. Real audio now: bass (`plasmaBuffer[0].x`) lifts the breath by 0.35 (bass 0.9 at t = 0.1 s: 92.9 % pixels differ vs silence), treble ×(1+1.2·treble) on the bevel. Mids unused. `audio-reactive` tag now true.
- Cell index mod N (odd N: the cell straddling the atan2 cut had two different indices → seam in the morph blend).
- `dataTextureA` store added (header promised the packing).
- No ACES (P-ACES policy: photo-passthrough filter; added light is ≥ 0 and left to the display); JSON has no `upgraded-rgba` tag, so none to remove.

**Header:** `Upgraded: 2026-11-10, 2026-11-22`; `Ideas:` extended; A-packing line extended. JSON: only `description` (was the bare name); `params`/`features`/`x-meta` byte-identical.

## Gates (each file)
precommit 2/2 (naga OK, bindgroup OK, extraBuffer violations 0, pasted headers 0) · naga-wasm 2/2 valid · `audit_dead_sliders` 2 defs, 0 new dead · `audit_extrabuffer` pass · all four sliders grepped live in both files · only `min(u32(config.y),50u)` as ripple count · no `fwidth`/`dpdx`, no `pow` with a possibly negative base (`pow` base is the constant vec3 ρ).

## Timing (SwiftShader, 256 px, interleaved `mr_ab`, **box load average 13–17 from the other forks → not trustworthy; coordinator must re-time on a quiet box**)
- navigator: min-ratio 1.19, p25 1.09–1.66, paired-median 1.18–2.4 across four runs (HEAD itself drifted 10.8 → 15.1 ms min). Added work: one inverseSqrt, 2 trig of `time`, floor/fract tile-id math, ~6 vec3 ops. Variants without the trig / with tanh were indistinguishable inside the noise.
- kaleidoscope: min-ratio 0.79–1.29, p25 1.00–1.18, paired-median 1.09–1.15 (two runs). Added work: one `select`, one vec3 `pow`, one A store; the toggle reuses the existing tap accumulators.

## Open calls for the user
- Both default pictures change a lot; the kaleidoscope's changes from "no kaleidoscope" to an 8-wedge one (that is the intent of the Segments slider; HEAD's look was the bug).
- tileCount and Segments are now stepped (10 positions each).
- breathing-kaleidoscope-morph slider roles are still shared/misnamed at HEAD (cycle_speed also sets the kernel radius, rotation_speed also sets gradient boost, "Breath Depth" only sets the twist amount) — left alone: renaming roles is param theft.
- Output alpha of the kaleidoscope is the top-hat luma (meanA ≈ 0.05) — kept (documented packing); a downstream slot that treats alpha as opacity will see it nearly transparent.
- Hyperbolic navigator's `hyperbolicTile` is still a wedge wrap, not a true {p,q} reflection tiling; a real fold/orbit-trap version would be a new shader.
- Real-GPU visual QA: external.
