# NOTES — fork A (rain, prismatic-3d-compositor) — sonnet/batch-51

Harness: SwiftShader, `agents/mr*.mjs` as patched by the coordinator (re-zeroes extraBuffer[133..255] each dispatch). No real GPU: **no visual QA claim**. Scratch: `/tmp/claude-0/-root-image-video-effects/ca8ee2a1-4d82-49d9-a35a-5be25191af56/scratchpad/a/` (HEAD copies `<id>_head.wgsl`, salvage `compositor_salvage.wgsl`, `analyze.py`).
Cards + §12.1 answers + §12.4 admission: `BRIEFS-forkA.md` (with the salvage AMENDMENT).

## Salvage check (coordinator request)
- `rain`: `git log -S'Ideas'` empty, history = initial + "push fix" commits. Nothing to salvage.
- `prismatic-3d-compositor`: `9acc4b18` (sonnet/batch-28) had afterglow + cursor light shafts; `9b5cd56e` (jules-bot) reverted it and deleted that batch's notes. Audited the lost WGSL: clean (no pow-negative / ACES / state-texel read as colour; exact clamped `textureLoad`). **Adopted** its afterglow (HEAD's A packing, intent of the dead feedback), with `prev` clamped to [0, 8]. **Not adopted**: cursor light shafts (pointer is a plain parallax driver here; adds un-conserved light against idea 2; would exceed the 3-idea cap). Its "no tone map / no limiter" rule kept (my first-draft `shoulder()` removed). Coordinator may re-add the shafts from `9acc4b18:public/shaders/prismatic-3d-compositor.wgsl`.

---

## rain  (1st pass; `Upgraded: 2026-11-21`)

**KEEP VERBATIM:** 4 sliders + roles (density 6..72, fall 0.3..4.2, wind ±0.12 + mouse.x·0.08, wetness 0.06..0.55 → mist), saved params/defaults, grid-cell streak kernel (`step(0.65)` presence, `step(0.75)` splash gate, width family, slant), splash arcs at `local.y > 0.92`, bloom (pow(L,3)·2.5 from the uv+0.002 tap), rain tint + chroma mix, mist blend `hdr·0.72 + tint·0.28`, 0.9+bass·0.15 exposure, ACES, alpha structure + 0.04..0.96 clamp, depth out.
**A packing:** unchanged diagnostics `(dropletAlpha, motionBlurStrength, mistLayer, finalAlpha)`; nothing reads C. Display RGBA on writeTexture only.

| # | Idea | Where in the diff | §12.2 row |
|---|---|---|---|
| 1 | Per-lane terminal velocity + shutter-length streaks (size seed per column → 0.7–1.3× fall speed, width ×0.75–1.25, tail 0.45–1.0 of the cell, constant-exposure brightness `clamp(0.72/tailLen, 0.8, 1.0)`; head leads at the bottom; x jitter per cell) | `// ── Idea 1` block (`laneSeed`, `laneSpeed`, `xc`, `tailLen`, `behind`, `exposure`) | tactics 2/3 (promotes dead `gravity`/`streakY`) — not a table row |
| 2 | Snell refraction through each streak as a water cylinder (η 1/1.333, `refract()`, normal from the streak's own x profile, lateral exit offset ×`depthScale`) | `// ── Idea 2` block (`waterHalfW`, `sx`, `bodyT`, `rayOut`, `lensOffset`) | Snell vector refraction (§12.2F) |
| 3 | Beer–Lambert mist on real depth: `mistLayer = 1 − exp(−τ)`, τ ∝ smooth advected value noise × wetness × path `0.6 + 0.5(1 − depth)` | `// ── Idea 3` block + `vnoise()` | Beer–Lambert (§12.2F) |

**Rescues (not ideas), all measured on HEAD at 384²/512², SRC=img, defaults:**
- **R1 rain fell UP** — `rainUV.y = uv.y·D + t·fall`. Alpha-pattern cross-correlation between t = 1.0 and 1.1 s: HEAD **−2 rows (up)**, new **+2 rows (down)**, expected 2.2. Tail profile flipped so heads lead at the bottom where the splash arcs already sat.
- **R2 lens offset grew with time** — `dropCenter.y` missed the `t·fall/D` scroll. Mean |HEAD − HEAD-without-lens|: 5e-5 at t = 1 s, **2.4e-3 at t = 300 s (48×)**. New: 5e-5 at both t = 1 and t = 300 (no growth). The `dropWorld` lens is gone; the old fake `(lensR − lensG, lensB − lensR)·40` chromatic offset was never per-channel and is not replaced by a per-channel Cauchy split (that row is the compositor's).
- **R3 comb lattice** — every streak sat at `local.x = 0.5` (evenly spaced dashed columns in the HEAD render); now jittered ±0.25 cell.
- **R4** dead `streakY`; `dropSeed2` re-rolled every frame; mist re-rolled as hard cells every 0.5 s (`floor(time·2)`) and scrolled upward — replaced by smooth noise drifting down + wind.
- **Behaviour change to flag:** depth direction of the mist is reversed (HEAD: nearer = more mist via `depthScale`; new: farther = more haze). At depth = 0 (no map loaded) the mist is ≈1.2× HEAD's at depth 0; with a map it ranges 0.29×..1.2× of HEAD's depth-0 value.

**Diff vs HEAD** (512², 60 frames, defaults, audio 0.3/0.2/0.1): 9.3 % of pixels differ > 2/255, mean |Δ| 0.0048 (streaks are sparse; meanL 0.491 → 0.489, meanA 0.042 → 0.041).
**Timing** (`mr_ab.mjs`, 256², 40 cycles, 3 rounds, box loaded): paired-median 0.81 / 1.00 / 1.09 → **≈ 1.0× HEAD** (cap 1.3×).
**Sweep** (256², 60 frames): extremes (1,1,1,1 + mouse + audio 1), (0,0,0,0), defaults + audio, aged click (`mr_c_abs.mjs`): **nan 0** everywhere.
**Gates:** precommit 1/1, naga-wasm 1/1, dead sliders AUDIT PASS (all four read: x→rainDensity, y→fallSpeed, z→windBase, w→wetness), `audit_extrabuffer` PASS (no extraBuffer use). Prelude migration done by the coordinator (no bump for it).
**JSON:** `description` appended; params/features/tags untouched. Pre-existing over-claim left alone: `tags` still lists `chromatic` and the old description says "chromatic droplet lensing" (HEAD's lens was never per-channel; the new Snell lens is achromatic).
**Not verified / open:** the lens sliver is sub-pixel to ~2 px at 384–1024² and only shows where a streak crosses an edge in the harness image (smooth source) — judge on a real photo on a real GPU. `LENS_GAIN = 3.5` and the `0.12` haze coefficient are tuned by eye. Per-frame float precision of `time·fall·laneSpeed` at very long run times is as HEAD.

---

## prismatic-3d-compositor  (1st pass; Pass 2 of `volumetric-rainbow-clouds`; `Upgraded: 2026-11-21`)

**KEEP VERBATIM:** 4 sliders + roles + defaults (glowRadius·0.01 tap spacing, glowIntensity, parallaxAmount, aberration), `PARALLAX_SCALE` and the `depth·(1+bass·0.4)·(1+down·0.5)` driver, in-bounds fade, 5×5 depth-weighted glow gather (threshold 0.2, `/max(Σw,1)`), prismTint (depth hue, 0.35 mix), abDir (radial 0.65 + flare dir), flare constants + boosts, ghost mix `depth·(0.4 + bass·0.5)`, `videoBlend = 0.5`, treble/bass/mids roles, alpha `|c|·0.7 + depth·0.3`, depth passthrough.
**A packing:** **unchanged from HEAD** — `A.rgb` = trail `mix(finalRaw, prev, 0.85 − mids·0.25)` (HDR), `A.a` = alpha, read back as colour with an exact `textureLoad`. Display RGBA on writeTexture. No ACES, no limiter (Pass 1 already tone-maps; HDR highlights are part of the look).

| # | Idea | Where in the diff | §12.2 row |
|---|---|---|---|
| 1 | Cauchy-weighted dispersion: R +0.73·δ, B −1.27·δ around the unshifted green tap (n(λ)−n(550) ∝ 550²/λ² − 1 = −0.284 / +0.494, scaled so R+B = 2: total R–B separation stays 2δ) | `// ── Idea 1` + `CAUCHY_R/B` | Cauchy dispersion (§12.2F) |
| 2 | Energy-conserving glow: `lit = max(layered − excess·min(spreadGain,1)·GLOW_EMIT, 0) + glow·spreadGain` — the above-threshold light a pixel radiates is taken from its core (`GLOW_EMIT = 0.75`; 0 = HEAD's additive, 1 = fully conserving) | `// ── Idea 2` + `GLOW_EMIT` | energy-conserving bloom (§12.2F) |
| 3 | Depth-consistent parallax: 3-step fixed point `offset ← drive·depth(fetch)` (iteration 0 = HEAD's offset exactly; flat depth reproduces HEAD) + ghost fades where the last two depths disagree (`settled`) | `// ── Idea 3` block | tactic 1 (deepen the kernel) — not a table row |

**Rescues:** afterglow (salvaged, see above) — `max(prev − finalRaw, 0)·(0.45 + 0.4(1 − depth))` added to the live frame, so the previously write-only trail is visible; static scene settles and adds nothing. Exact `textureLoad(dataTextureC)` (HEAD sampled at the texel corner `gid/dims` with a sampler). Stale comment about `extraBuffer[0..2]` params removed (the code used constants).
**HEAD defects reported, not changed:** `upgraded-rgba` tag with no ACES (pre-existing, and none is right here); `uv = gid/dims` has no +0.5 (half-texel bilinear blur, the whole chain does the same); Pass 1 depth `.g` (optical depth) is not available to this pass (`writeDepthTexture` is `r32float`).
**Correction to COMMON.md Finding 3:** the catalog **does** have the Pass 1 partner (`volumetric-rainbow-clouds.wgsl`, ACES'd output).

**Diff vs HEAD** (256², 40 frames, defaults, audio 0.3/0.2/0.1): **93 % of pixels differ > 2/255, mean |Δ| 0.0995; meanL 0.619 → 0.507** (HEAD's glow adds ≈ +26 % brightness and clips cores to white-yellow; new keeps the halo ring and prism tint, cores much less blown out). This is the biggest default-look change in my two files — **open call**: `GLOW_EMIT` is the one dial (0.75 chosen by eye; lower it toward 0 to approach HEAD's blown cores).
**Timing:** `mr_ab.mjs` 256², 40 cycles, 3 rounds: paired-median 0.98 / 1.08 / 1.07 → **≈ 1.05× HEAD** (cap 1.3×; +3 depth taps, no new colour taps).
**Sweep** (256²): defaults, params (0,0,0,0), extremes (10,4,4,0.2 + mouse down + audio 1: meanL 1.95 vs HEAD 2.05, same saturated regime as HEAD), two aged click flares (`mr_c_abs.mjs`): **nan 0** everywhere. (`MPATH` test invoked with a wrong format and crashed the harness; pointer-moving case covered by static mouse (0.9,0.2,down) renders — parallax compared HEAD vs new at (4,0,4,0).)
**Gates:** precommit 1/1, naga-wasm 1/1, dead sliders AUDIT PASS (x glowRadius, y glowIntensity, z parallax, w aberration all read), `audit_extrabuffer` PASS (no extraBuffer use). Prelude migration by the coordinator.
**JSON:** `description` appended; params/features untouched.
**Not verified / open:** real-GPU visual QA; afterglow on fast video input (whole-frame trail of up to 0.85·(prev − final), same as the lost batch-28 version); `GLOW_EMIT` tuned by eye; cursor light shafts from the lost version were left out on purpose.
