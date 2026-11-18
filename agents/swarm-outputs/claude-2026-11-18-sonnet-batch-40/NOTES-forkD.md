# NOTES — fork D (sonnet/batch-40): gen-sonoluminescent-chrono-geode-matrix, gen-crystalline-chrono-dyson

Cards + §12.1 interrogation: `BRIEFS-forkD.md` (written before any WGSL edit). Numbering: both files already carried in-body `Idea 1–5`; the two new ideas per file are `Idea 6` and `Idea 7` in the WGSL (cards called them 1 and 2). Scratch (renders, variants, diff + perf scripts): `/tmp/claude-0/-root-image-video-effects/914950b4-f44b-4d87-a537-edda39759ec7/scratchpad/forkD/`.

Method for every visibility number: scratch copy with the idea's contribution multiplied by `0.0` (`sono_no6/no7`, `dyson_no6/no7`), same time / sliders / history length, RAW write-texture float diff, **% of pixels with max-channel |Δ| > 0.02** and mean |Δ| over the frame, saved-default sliders (sono 0.5,0.5,0.5,0.5; dyson 4,1.5,1,50), no audio, no cursor. Sonoluminescent frames are measured at flash phases φ because ideas are phase-local (10 frames over the last 0.35 s so C history is warm); Dyson at clock t.

---

## gen-sonoluminescent-chrono-geode-matrix (`public/shaders/gen-sonoluminescent-chrono-geode-matrix.wgsl`)

**KEEP VERBATIM held: yes.** Sliders and roles; KIFS geode SDF + noisy core; orbital camera + warp; `exp(-7φ)` primary collapse, `regrow`, `ringR`; stateless `kick`; Ideas 1–5 untouched; swirl-advected C history (0.86, clamp 5.0); ACES on display only. `params` still `[]` in the definition (defaults live in `x-meta.upgrade.params`, unchanged).
**A packing: unchanged** — raw HDR history RGB (pre-ACES, ≤ 5.0) + semantic alpha; C read via exact `textureLoad`. `A16=1` 60-frame run: meanL/stdL identical to rgba32float (0.328 / 0.269), nan 0.

### Idea 6 — Rayleigh–Plesset afterbounce (native: bubble dynamics) — L208–224
`ab1/ab2` Gaussians at φ = 0.20 / 0.38 give `rebound = 0.22·ab1 + 0.09·ab2` (added to `collapse` inside `ctx.flash`) and `radiusDip = 0.22·ab1 + 0.10·ab2` (multiplies `ctx.coreR`). Both are ≈ 0 at the main collapse (φ = 0): HEAD's implosion and decay are untouched; the secondaries carry ~35 % of the primary's flash energy. §12.2 row: none (native physics; the table has no bubble row).
Visibility (192 px; 576 px within 0.01 of these): φ=0.05 **7.7 %** of pixels, mean |Δ| 0.012; φ=0.20 **99.8 %**, 0.050; φ=0.38 **99.9 %**, 0.054; φ=0.60 **99.9 %**, 0.042; φ=0.85 **99.0 %**, 0.029. Whole-frame because `ctx.flash` drives the void tint, plasma accumulation, shell and translucency, and C history (decay 0.86) carries the pulse across ~7 frames. (An earlier 0.40/0.16 amplitude drove a +30 % frame luma and washed the geode white at φ = 0.38; trimmed to 0.22/0.09.)

### Idea 7 — shock-heated ember afterglow, blackbody cooling (§12.2F Rayleigh/blackbody) — L55 `wienTint`, L317–330
Wall inside the front (`φ > r/(5+3·kick)`) incandesces: `heat = exp(−5·age)`, `T = 1700 + 5200·heat` K, tint = Wien radiance at 650/550/450 nm (max-normalised), brightness `sqrt(heat)` (T⁴ would make the cool tail vanish), blended into the surface colour at ≤ 50 % (`clamp(2·heat, 0, 0.5)`) so the blue-white sheen survives. Inner walls (crossed first) are redder/dimmer than the freshly crossed outer wall.
Visibility (192 px): φ=0.05 **15.1 %**, 0.016; φ=0.20 **7.7 %**, 0.005; φ=0.38 **14.8 %**, 0.015; φ=0.60 **15.6 %**, 0.028; φ=0.85 **15.8 %**, 0.027. At 576: φ=0.2 6.4 %, 0.38 14.5 %, 0.6 14.6 % — i.e. ~50–100 % of the geode disc (the geode covers ~16 % of the frame). At 576 the strata and pearls read under a warm cream/pink wash; at 192 it is a subtle warm tint on facets and the lower rim.

### Rescues
- **R1 flash phase scrubbed by audio — CONFIRMED, fixed (L200–206).** HEAD `flashRate` had `+ bass·0.6`, so a bass change re-phases the cycle by `animTime·0.6·Δbass` cycles. Measured at T0 = 60 s, HEAD: bass 0 → 0.05 changes **99.8 %** of pixels, mean |Δ| **0.134** (0.10 → 0.113); control at T0 = 0.5 s: 0.029. After the fix the same test gives 0.037 (0.05) and 0.0715 (0.10), a monotone amplitude response through `kick` / `ringR` instead of a random re-trigger. Identical to HEAD at bass = 0. Under live audio the flash timing is now a steady `0.8 + 1.2·Speed` cycle (the "faster flashes with louder bass" nudge is gone; bass still scales flash amplitude and shell reach).
- **R2 `pow` with a negative base — NOT reproduced on SwiftShader, fixed defensively (L263–265, L291).** `pow((pearlPhase − 0.5)·7.0, 2.0)` is negative-base for half of each period; SwiftShader evaluates it as a square (pixel diff 0.00 % at three times, nan 0), but the spec makes it undefined and GPUs that lower to `exp2(y·log2 x)` give NaN, which would then persist in the C history. Now `pearlX·pearlX`; `fresnel` base `max(1 − dot, 0)` (−1e-7 face-on).

### Default look, frameMs, gates
- 192 px, 30 frames / 2 s (SRC=img): idle meanL/stdL **0.166/0.179 → 0.202/0.229**; held cursor 0.172/0.192 → 0.205/0.236; audio (0.8,0.5,0.9) 0.704/0.150 → 0.570/0.268 (not like-for-like: R1 changed the flash phase at the sampled frame; HEAD's frame happened to be a full white-out at the primary collapse). nan 0 everywhere; 60-frame run with audio 0.3,0.2,0.2: finite, meanL 0.328, no runaway.
- All four sliders move the picture (min/max meanL: Intensity 0.18/0.30, Speed 0.29/0.26, Scale 0.19/0.31, Mouse 0.27/0.22 — mouse here = decay length, cursor up).
- Timing (min-of-drained, interleaved, 4 rounds, 192 px, load from sibling forks 8–28): idle ratios 0.98 / 0.71 / 0.87 / 0.59; audio 0.50 / 0.50 / 0.65 / 1.18 → **no measurable cost** (nothing added in the march loop; Idea 6 is per-pixel scalars, Idea 7 is one `exp` + `sqrt` + 3 `exp` in `wienTint` at the surface hit). Under this load the numbers are noise-dominated; coordinator re-times alone.
- Gates: `wgsl_precommit_gate` pass, `verify-naga-wasm --files` pass, `audit:extrabuffer` no new findings (file only reads extraBuffer[6..9]), `audit:dead-sliders`: the definition has `params: []`, so the audit scans 0 sliders for it (blind spot); by reading, all four `zoom_params` are consumed (x Intensity, y Speed, z Scale, w Mouse) and the sweep above confirms each changes the picture.
- Header: `Upgraded: 2026-09-27, 2026-11-18`; `Ideas:` appended (one line); `A packing:` unchanged. Definition: description +~75 chars; no tag changes (`audio-reactive`, `mouse-driven`, `upgraded-rgba`, `fast-motion` were already listed and true).
- §12.2 rows used: Rayleigh/blackbody (Idea 7). Afterbounce is native, no row.

### Open items
- Real-GPU look: the whole-frame brighter flash (secondary pulses) and the ember tint are default-look changes; the ember reads best at ≥ 576 px.
- The geode occupies ~16 % of the frame at default Scale; both ideas are legible mainly on the ball.
- Audio-driven flash timing is slower/steadier than HEAD's chaotic one (intended, see R1); if the owner wants a bass-quickened cycle it needs persistent phase (A-texel scheme), not a rate term.

---

## gen-crystalline-chrono-dyson (`public/shaders/gen-crystalline-chrono-dyson.wgsl`)

**KEEP VERBATIM held: yes.** Four params and roles (Panel Density, Quasar Glow, Flux Speed, Swarm Count; Quasar Glow now additionally widens the halo of Idea 6 — still "how much the quasar glows"); the whole `map()` smin chain; Ideas 1–5; flat Beer–Lambert blue subsurface, `spectralGlow`, fog, integer-offset chromatic C feedback, ripple spectral glow.
**A packing: unchanged** — clamped HDR linear RGB (≤ 8, pre-ACES) + semantic alpha (`0.3 + lum·0.65` on hits); ACES on `writeTexture` only. Nothing added to the 100-step march loop.

### Idea 6 — Cauchy-dispersed plate transmission (§12.2F Cauchy dispersion + Snell vector refraction) — L88 `cauchyIndex`, L291–309
`n(λ) = 1.45 + 0.10/λ²` at 650/550/450 nm (B exaggerated ×~25 over BK7 so the fringe is legible); `refract(rd, nPlate, 1/n_c)` per channel on `onShell` hits (air→glass, so no TIR); each refracted ray is compared with the direction to the quasar (`acos(dot(r_c, coreDir))`) against the quasar's angular radius `asin(0.5/dist)` widened by `(1.6 + Quasar Glow)` (glare halo, ~3.1× at default); per-channel coverage tints cream light on the plate → colour-fringed image of the quasar through each tilted louvre. Closed plates facing the core show it near-white; tilted plates fringe cyan/magenta/amber.
Visibility: 192 px t = 10 / 25 → **2.6 % / 2.6 %** of pixels, mean |Δ| 0.003 (≈ 0.1 per affected pixel); 576 px t = 25 → **2.6 %**. This is the plates in the central cone around the quasar (~8 % of the frame), not the whole shell; an earlier hard-disc version was 0.35 %, a 2.2× halo 1.3 %. Below "several percent"; strengthening further would mean light on plates that cannot see the quasar. Reported honestly.

### Idea 7 — lume sweep hand (native: chronometer dial) — L316–329
Escapement-stepped seconds hand: 60 beats/revolution at 1.5 beats per Flux-clock unit, step settle `1 − e^{−14f}·cos(38f)` (continuous across beats, spring overshoot). Lume (green-cyan, 0.30/1.0/0.62) is charged behind the hand: `exp(−0.6·behind)` afterglow, strong on the existing tick crown (`tickBand·ticks·0.9`), faint on the plates (`onShell·0.30`), plus a thin hand line (`exp(−28·angle)`) on the tick band. Extends Idea 4 without changing the scrolling ticks. Uses the same `tD` clock as the rest of the file (slider scrubs it — HEAD's documented behaviour).
Visibility: 192 px t = 10 / 25 / 37 → **3.6 % / 11.7 % / 4.8 %**, mean |Δ| 0.003 / 0.007 / 0.004; 576 px t = 25 → **11.3 %**, 0.007. Varies with where the hand sits relative to the visible hemisphere (the wedge is partly on the far side at some times); average ≈ 6.7 %.

### Rescues / truth fixes
- **Header truth.** `Ideas:` listed only tick-crowns and twin seams; the body also has the statite swarm, power-grid packets and louvred plates (in-body Ideas 1–3). Appended all three (additive) plus the two new ideas.
- **Fresnel hardening (L64–65).** `pow(1 − cosθ, 5)` → `pow(max(1 − cosθ, 0), 5)`; same ulp-overshoot argument as sono R2; not reproducible on SwiftShader, output unchanged.
- **Premise check: HEAD is not broken.** Idle / held / audio all render a readable lattice, conduit, spokes, statites, quasar; no audio-from-C, no `ripple.w`, Y flip already fixed, semantic alpha. No picture rescue needed.

### Default look, frameMs, gates
- 192 px, 20 frames / 2 s, saved defaults: idle meanL/stdL **0.250/0.312 → 0.256/0.321**; held 0.242/0.306 → 0.248/0.316; audio 0.313/0.336 → 0.317/0.341. nan 0. 8 slider extremes at 128 px (Panel Density 1/10, Quasar Glow 0/5, Flux Speed 0.1/3, Swarm 10/100, audio 0.3,0.2,0.2): nan 0, every slider moves meanL (0.15–0.33).
- Timing: HEAD is ~1.4–2.3 s/frame at 192² on SwiftShader, so 128 px × 4 frames, 5 interleaved rounds, min-of-drained: ratios 1.00 / 1.58 / 1.50 / 1.05 / 0.65, median **1.05**, but head min alone ranged 233–474 ms across rounds (sibling-fork load) so the spread is noise. By construction the added work is in the hit branch only (3 `refract`, 3 `acos`, 1 `asin`, ~6 `exp`, 1 `atan2`-free reuse of `lon`) against ~100 `map()` calls per pixel: expected < 1 %. Coordinator re-times alone.
- Gates: `wgsl_precommit_gate` pass, `verify-naga-wasm --files` pass, `audit:dead-sliders` 0 new (1 def scanned), `audit:extrabuffer` no new findings.
- Header: `Upgraded: 2026-10-10, 2026-11-18`; `Ideas:` extended (one line); `A packing:` unchanged. Definition: description +~50 chars; no tag changes.
- §12.2 rows used: Cauchy dispersion + Snell vector refraction (Idea 6). Idea 7 is native (chronometer escapement + lume).

### Open items
- Idea 6 reaches only ~2.6 % of the frame at default; it reads best around the quasar and rises with Quasar Glow.
- Real-GPU look for the lume hue (green on a violet/cream palette) and the fringe contrast; no real-GPU claim made.
- `dysonClock()` still scrubs when Flux Speed moves (HEAD, documented in-file); the lume hand jumps with it.

## Row budget across fork D
Blackbody (sono Idea 7); Cauchy + Snell (dyson Idea 6). No row shared. No generic overlay (no spring, ripple, IQ palette, new param); Dyson untouched in the march loop.
