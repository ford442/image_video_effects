# COORDINATOR_REVIEW — sonnet/batch-21 (depth / parallax / tunnels / labyrinths ten)

2026-11-08. Four forks (A tunnels/echo, B labyrinths/monolith, C parallax pair, D 4D pair). Cards + §12.1
interrogation: `BRIEFS-fork{A,B,C,D}.md`, written before the WGSL edits. Per-shader detail: `NOTES-fork{A,B,C,D}.md`.
Prelude migration of 5 files (header-only, no `Upgraded:` bump) is its own commit.

Structural gates (all run by the coordinator, not only the forks): naga + bindgroup 10/10,
`audit_extrabuffer` PASS, `audit_dead_sliders` PASS (9 defs scanned; psychedelic has no `params`, checked by hand),
Vitest 202 files / 1805 passed / 1 skipped, `npm run build` OK, `verify:toolchain-foundation` OK.
Real-GPU visual QA is external and still required: every picture below was judged on SwiftShader renders with
synthetic source / depth only.

## Pass/fail per file against its card

| Shader | Pass | Native ideas in the diff (grep `// ── Idea`) | §12.2 rows | Rescues (not counted as ideas) |
|---|---|---|---|---|
| chromatic-ghost-tunnel | PASS (after rework) | per-channel ghost lag; perspective ring thickness (cap 1.2x); vanishing-point glow | B chroma delay; F soft inverse-square | double tone-map + premultiply (rings were grey); dead extraBuffer spring -> A texels; dead plasmaBuffer[1..8] voices -> bands i%3; clamp before ACES |
| gen-feedback-echo-chamber | PASS, ideas subtle | frequency-dependent echo decay; second-order corner reflections | none | ACES-on-ACES feedback (flat grey); dead extraBuffer bass envelope -> A.a; treble veil -> sparse points |
| gen-psychedelic-layered-time-stamps | PASS | per-channel time lag; double-circle datestamp postmark + ink dropout | B chroma delay | broken OkLab pair (all ink green); clamp smear -> mirror fold; rim normal z |
| parallax_depth_layers | PASS | slab occlusion + disocclusion fill; dolly crossfade; rack-focus slice defocus; aerial perspective | F Beer-Lambert | composite never reached output (passthrough); inverted edge glow; extraBuffer[0] as uv offset; dead DoF slider |
| parallax-glow-compositor | PASS | energy-conserving bloom; Cauchy dispersion; depth-guarded fringe | F bloom, F Cauchy | same copy-pasted body; sliders realigned to JSON names; dead layer loop removed |
| gen-hyper-labyrinth | PASS | W-modulated wall thickness; corridor step-count AO | E step AO | camera inside wall ~20% of loop; mirrored/upside-down camera basis |
| gen-chromodynamic-glass-labyrinth | PASS | Cauchy dispersion; Fresnel-Schlick + exit transmittance; one-bounce reflection march | F Cauchy, F Schlick | camera inside glass at integer seconds |
| 4d-projection-dream-weavers | PASS | XW/YW hyper-rotation; 4D perspective divide + w-fog; dispersion along w | none (4D-native) | flat white frame; noise ignored w; dead spring (extraBuffer + dt = click count); hash lattice; filtering sampler on f32 history |
| tesseract-fold | PASS | true 4D double rotation + perspective; orbit-trap lead cames; fold-count glass thickness | E orbit trap, E fold count | A was never written |
| gen-fractured-monolith | PASS (after rework) | per-shard levitation phase; downdraft ring train (floor-hit only); chipped-edge curvature wear | D deep-water dispersion, E curvature | upside-down camera; unbounded shard tumble; audio times absolute time; chip snow; trail brightened to blue dome |

## Coordinator changes requested and verified

1. **Formula de-dup (§12.4).** Cauchy dispersion was on 3 files (tunnel, compositor, glass). Fork A replaced the
   tunnel's with per-channel ghost lag. Final tally from the files' `Ideas:` lines: Cauchy 2, chroma delay 2, every
   other row 1. No row on 3+ files.
2. **Monolith cost.** Fork B's first version ran the ring train inside every `map()` call (+87% frameMs vs HEAD, and
   barely visible). Reworked: rings evaluated at the floor hit only (normal tilt, pool light, crest glint), 4-tap
   curvature. Coordinator re-timed HEAD vs current back to back: 41-49 ms vs 51-52 ms (about 1.1-1.25x). Rings now
   read as concentric ripples under the slab. Hyper-labyrinth 16 -> 14 ms, glass 35 -> 44 ms (+26%).
3. **Tunnel ring width.** Outer bands capped at 1.2x HEAD width; the fat outer bands that remain come from the
   single-ACES rescue plus stacked echoes (HEAD hid them by premultiplying alpha), not from the idea.
4. **Dead-slider baseline.** `parallax-glow-compositor.aberration` and `parallax_depth_layers.depth_of_field/param3`
   are live now; both baseline entries removed and the audit still passes with 0 new.

## Honest caveats (do not read these as visual QA)

- Echo-chamber's two new ideas are subtle (about 1-2.5/255 mean difference when toggled in SwiftShader). The
  visible change in that file is the rescue, not the ideas.
- Default looks changed a lot at the saved sliders in: chromatic-ghost-tunnel (grey -> coloured), parallax pair
  (passthrough -> real layered zoom / bloom + haze, darker), monolith (blue dome + eroding slab -> dark night sky +
  intact slab), 4d-projection-dream-weavers (white -> soft cloud field), echo-chamber (flat grey -> psychedelic trail).
  All were broken at HEAD; each still needs a real-GPU look.
- Parallax pair: depth direction (larger = farther) is HEAD's convention and is unverified without a real depth map.
- Psychedelic time stamps: default distortion 0.5 is still extreme (mirrored smear on a static test source); left
  alone because changing it would be param theft. JSON has no `params`, so none were added (defaults stay 0.5 x4).
- A-texel state (4d spring, tunnel spring, echo envelope) cannot be exercised on rgba16float A tiers here
  (minirender uses rgba32float); fract(time) dt keeps f16 usable but is unproven on hardware.
- `public/shader-search-index.json` regenerates on build (embedding blob, whole-file churn); left out of the commit,
  as in earlier batches. Regenerate when someone next refreshes the index.
