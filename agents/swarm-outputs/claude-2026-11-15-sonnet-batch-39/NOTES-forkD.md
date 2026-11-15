# NOTES — fork D (gen-prismatic-quantum-loom, gen-acoustic-obsidian-resonator) — batch-39, 2026-11-15

Worktree `/root/iv-sonnet-batch-39`. No git write operations. Edited only: `public/shaders/gen-prismatic-quantum-loom.wgsl`, `public/shaders/gen-acoustic-obsidian-resonator.wgsl`, `shader_definitions/generative/gen-prismatic-quantum-loom.json`, `shader_definitions/generative/gen-acoustic-obsidian-resonator.json`.
All numbers: SwiftShader WebGPU via a scratch COPY of `agents/mr.mjs` (adds drained-frame min/median timing; scratch `forkD/`), saved-default sliders passed explicitly (loom 1.0,0.0,0.5,1.0; obsidian 0.5,2.0,1.0,1.5), single frame at the stated time (neither file reads C, so there is no temporal state), `pct` = % of pixels with max-channel |Δ| > 0.02 against the same file with that idea zeroed. **The machine was at load average 30–60 (sibling forks) for most of this run; every timing is indicative. No real-GPU claim of any kind.**

C is read by neither file after this pass, so `A16=1` / 60-frame drift runs do not apply (stateless). `nan` = 0 in every render.

---

## 1. gen-prismatic-quantum-loom (card 7)

**KEEP VERBATIM held.** `map()` structure (domain warp → opRep → three crossing cylinder SDFs → min), the 64-step march, glow term shape `0.02/(0.01 + d²)`, the `sin(t·k + shift)` hit-distance tint, 4 saved params with RAW ranges and roles (density → spacing 1.5/x, shift → tint phase, gravity → ray pull, fluctuation speed → warp clock), forward drift 0.5/s, mouse gravity intent. Params in the JSON are byte-exact (checked programmatically); `x-meta.upgrade.params` added additively; `features` added (the definition had none): raymarched, audio-reactive, mouse-driven, upgraded-rgba.

**A packing:** display RGBA — ACES display RGB + semantic glow alpha `1 − exp(−3·mean(hdr))` clamped [0.04, 0.98]; A = same display RGBA (nothing reads C any more); depth = `t/10`.

### Rescues (what HEAD actually did)

| # | Card hypothesis | Result | Evidence |
|---|---|---|---|
| R1 | "audio" read from `textureLoad(dataTextureC, …)` is always 0 | **CONFIRMED** | HEAD idle vs audio render (same cursor): 0.00 % of pixels differ. Now `plasmaBuffer[0].xyz`: bass → thread radius (`0.05 + 0.07·bass`, HEAD's `audioPulse` intent), mids → tint phase, treble → glow gain. |
| R2 | `%` on f32 is truncated → opRep not centred for negative cells | **CONFIRMED** | R2 alone (`p − c·floor(p/c + 0.5)`) changes 72.3 % of pixels at HEAD's camera. It did NOT remove the thick shaft (see R5). |
| R3 | mouse well at the wrong place | **CONFIRMED by arithmetic, not by a render diff** | `mousePos = (mouse·2−1)·aspect` spans ±aspect against `uv` ±aspect/2: for a cursor at x = 0.8 and aspect 1 the well centre is at uv.x = 0.6, outside the ±0.5 frame; now `(mouse − 0.5)·aspect` → 0.3. The y-down convention of `uv` and the mouse already agree, so the "upside-down" part of the card is not a defect (symmetric lattice) and was not changed. A held-vs-free centroid test was tried and is uninformative (gravity 2.0 bends rays across the whole lattice). |
| R4 | floor: A/depth unwritten, alpha 1.0, Reinhard, no header | done | ACES (input gain 0.5 so the default frame stays at HEAD's brightness), semantic alpha, depth, A, header. |
| **R5 (new)** | — | **found by the HEAD render** | HEAD's camera rides the lattice axis (0,0), so every crossing plane (every 3 s at default density) puts the camera INSIDE a thread: the whole frame is black. **HEAD at t = 6 s renders meanL 0.000.** HEAD-formula CPU model (fmod emulated, 0.005 s steps over 60 s): camera inside/touching a thread 4.0 / 5.3 / 6.5 % of the time at density 1 / 2 / 3, within 0.1 of one 29 / 38.5 / 43.6 % of the time — that is the thick brown shaft that fills the HEAD frame. Fix: same forward drift, but the camera follows the centre of the *warped gap channel* (`ro.xy = half-cell − warp offsets`), so it threads the loom. This changes the default composition (a tunnel of converging z-threads instead of a shaft). Touches the card's "camera drift" item only in its xy path. |

### Ideas (visibility = % px > 0.02, mean |Δ|, idea zeroed, default sliders, idle)

| Idea | Where | 192 px, t = 2 / 5 | 576 px, t = 2 / 5 |
|---|---|---|---|
| 1 Weave interlace (native) | `map()` L62–87: cell parity ±1, cyclic sideways offsets `parity·amp·cos(π·axis/c)`, amp = `min(2.4·r, 0.22·c)`, SDF scaled by `1/√(1+slope²)` | 94.6 % / 94.8 % (0.322 / 0.325) | 94.5 % / 94.8 % (0.323 / 0.326) |
| 2 Cauchy-dispersed glow halos (§12.2F) | `main()` L129–151: per-channel halo soft-core `0.01·(n(λ)/n(550))²`, B = 0.25 → radii ×0.87 / 1 / ×1.22 | 81.1 % / 81.2 % (0.060 / 0.060) | 81.1 % / 81.2 % (0.060 / 0.060) |

Idea 1 relocates geometry (so the % is high by construction); I read the rendered frame: threads visibly pass in front of / behind each other at crossings and undulate between cells; identity (a lattice of glowing threads) holds. Idea 2 is a subtle but wide spectral fringe (red-tight, blue-wide halo per thread).

Sliders (128 px, free / held cursor): density 100 %/100 %, chromatic-shift 0 → 3.14 97.9 % (0 → 6.28 is one full period, ≈ 0 by design), gravity 0 % free / 99.9 % held (pointer-only, as HEAD), fluctuation speed 98.8 % / 99.1 %.

Default-look change (meanL / stdL, 256 px): HEAD t = 3 0.230 / 0.143 (HEAD t = 6: black) → new 0.268 / 0.171 (t = 2) and 0.268 / 0.171 (t = 5). With audio the new frame is brighter and shifted (idle ≠ audio now: 99.95 % of pixels differ).

Cost (new/HEAD, 256 px, drained-frame min over 12 frames, interleaved, 5 rounds, load 30–50): idle per-round [0.53, 1.51, 0.49, 0.64, 0.30] median **0.53**; audio [0.45, 0.20, 0.34, 0.38, 2.40] median **0.38**. Wide spread (load) but the median is clearly < 1: HEAD's camera spent its time hugging threads (many short steps); the new channel camera exits sooner. Not a GPU figure.

§12.2 row used: Cauchy dispersion (loom only). Idea 1 is native.

Open items: (a) default look changes completely because of R5 — real-GPU eyeball needed; (b) weave amplitude is tied to the audio-pulsed radius, so threads shift sideways on bass (intentional "breathing", but it moves geometry); (c) high density (3.0, spacing 0.5) clamps amp to `0.22·c` = 0.11 ≈ 2.2 thread radii — threads still separate but only just.

---

## 2. gen-acoustic-obsidian-resonator (card 8)

**KEEP VERBATIM held.** `map()` pipeline (mouse pull → domain repetition → rotation → box minus octahedron + mids fracture), the 100-step march, `ao = 1 − steps/100`, HEAD's gold-on-bass emissive `mix(0.02, gold·2·bass, smoothstep(0.8, 1, ao))·ao` (still the base of `col`), the 4 saved params with RAW ranges. Params byte-exact; `features` gains `upgraded-rgba` (ACES in the WGSL, card implemented); `x-meta.upgrade.params` already existed.

**A packing:** display RGBA — ACES display RGB + coverage alpha `mix(0.4, 1, ao)` on a hit, 0 on a miss; A = same display RGBA (HEAD wrote `vec4(0)`); depth unchanged (`t/50`, 1 on a miss).

### Rescues

| # | Card hypothesis | Result | Evidence |
|---|---|---|---|
| R1 | black at silence | **CONFIRMED** | HEAD idle meanL 0.008 / stdL 0.004. Now a Fresnel (F0 0.04) reflection of a cool sky gradient + two soft-box windows from a 4-tap tetrahedron normal (hit pixels only): idle **0.091 / 0.137**. |
| R2 | `fracture_scale` dead at silence; unguarded `normalize` | **CONFIRMED by code** | HEAD: `fracture_scale` only enters as `bass·z` on the octahedron size, so with no bass it changes nothing; mids fracture is unscaled. Now it also scales the scar relief (clamped 0–2), so it is live at silence: 0 → 3 changes 99.1 % of pixels idle. `normalize(p)` is guarded (`p / max(|p|, 1e-4)`). Not rendered at HEAD (read from the code). |
| R3 | scene upside-down / mouse inverted | **REFUTED as a defect** | `uv`, the mouse and world y all run down, so the pull is consistent with the screen; the lattice rotates in-plane. Nothing flipped. Only the sky direction in the new shading accounts for it (`up = −rr.y`). |
| floor | alpha 1.0, `A = vec4(0)`, no ACES | done | |

### Ideas

| Idea | Where | 192 px idle / audio | 576 px idle / audio |
|---|---|---|---|
| 1 Conchoidal scars (native) | `map()` L87–97, the `if (d < 0.2)` block: per-cell blow origin (sine-free hash), `sin(9·rr − 2.2·√rr)·0.022/(1 + 0.22·rr)·fracture_scale`; only near the surface | **20.1 % / 41.5 %** (0.030 / 0.059) | **22.4 % / 41.2 %** (0.036 / 0.061) |
| 2 Gold schiller + convex-edge wear (§12.2E SDF curvature) | `main()` L166–181 (stencil L143–155, R1 gloss L139–163), after the stencil: layered inclusion bands × grazing Fresnel (sheen); chip highlight from κ = 1.5·(Σ₄ − 4·d₀)/e², `d₀` = the march's final residual | **19.9 % / 61.5 %** (sheen only 19.7 % / 45.9 %; wear only 12.0 % / 55.4 %) | **14.8 % / 50.2 %** (0.032 / 0.119) |
| (R1 gloss) | environment reflection | 50.5 % / 62.3 % | — |

Two things I got wrong on the way, kept here because they will recur on the next curvature idea:
1. κ from `Σ d(p ± e·axis) − 6·d(p)` with `d(p) := 0` is wrong at a hit surface: the march stops at `d < 0.001`, so `6·0.001/e²` is a constant ≈ 15 that lit the wear term on every pixel (and drew the scar arcs by accident). The residual must be subtracted — `dEnd` (the last march distance) is free.
2. A debug colour that goes through `acesToneMap` shifts a "0" signal to 0.233; invert ACES before reading a debug value back.

Slider sweep (128 px, free / held cursor): rotation 94.7 % / 93.1 %, shockwave 0 % free / 94.4 % held (pointer-only, as HEAD), fracture scale 99.1 % / 95.4 %, domain spacing 67.9 % / 81.5 %.

Default-look change (256 px): idle 0.008 / 0.004 → 0.091 / 0.137; audio 0.484 / 0.383 → 0.502 / 0.291 (ACES compresses HEAD's unclamped gold; the yellow areas are less saturated).

Cost (new/HEAD, 256 px, drained-frame min over 6 frames t ≤ 4 s, interleaved, 6 rounds, load 20–50): **first version** (6-tap central stencil, `sin` hash, `exp` falloff) idle median ≈ 1.9× (min-ratio) / 2.1× (median frame). **After the trim** (sine-free hash, `1/(1+k·rr)` falloff, 4-tap tetrahedron stencil giving normal + Laplacian) idle per-round [1.13, 0.80, 1.22, 4.06, 2.44, 1.50] median **1.36** (median-frame 1.47); audio [1.45, 0.95, 1.73, 2.91, 1.04, 1.22] median **1.33** (1.36). Scars-off variant: idle 1.48 / 0.97, audio 1.85 / 1.43 — i.e. NOT separable from noise, so the scar term is not the cost driver; the post-hit stencil (4 extra `map` calls + `localFrame` + environment) is. That is at or just over the 1.3× cap on a loaded SwiftShader (spread per round is 0.8–4×); I did not trim further. **The coordinator should re-time alone.** A cheaper option if needed: drop the stencil to a 3-tap forward difference (normal only) and give up the wear term.

§12.2 row used: SDF curvature (obsidian only). Idea 1 is native. No orbit-trap / Beer–Lambert / Cauchy.

Open items: (a) scars read as soft undulations of the reflected lobes rather than crisp conchoidal arcs (amplitude 0.022; a deeper relief would need the step threshold relaxed); (b) at audio the diagonal black speckle in the alpha panel is step-exhausted rays (HEAD drew them black too; they now carry alpha 0); (c) the wear term is wide with the 4-tap stencil (12 % of the idle frame vs 2.6 % for the earlier 6-tap one) because the tetrahedron footprint is larger — thresholds (`smoothstep(0.12, 0.5, κ·e)`) were not re-tuned after the switch; (d) real-GPU eyeball for the silent frame, which is the biggest default-look change.

---

## Gates (per file)

| Gate | loom | obsidian |
|---|---|---|
| `wgsl_precommit_gate.py --files` | pass (naga OK, bindgroup compatible) | pass |
| `verify-naga-wasm.mjs --files` | pass | pass |
| `audit:dead-sliders -- --files` | 0 new | 0 new |
| `audit:extrabuffer` | no finding for either file | no finding |
| params byte-exact vs HEAD | yes | yes |
