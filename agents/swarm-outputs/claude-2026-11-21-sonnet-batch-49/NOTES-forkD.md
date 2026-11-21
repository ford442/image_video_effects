# NOTES — fork D (aerogel-smoke-hdr, atmos-fog-volumetric)

Baseline = migrated worktree files (scratchpad `d/*_head.wgsl`). Renders: `node agents/mr.mjs … SRC=img` (SwiftShader, synthetic image + synthetic depth: near disc upper-right, far disc lower-left). **No real-GPU visual QA was done**; every statement below about "looks" is from SwiftShader frames only. All comparisons are HEAD vs new at identical params/mouse/ripples.

Harness caveat: `mr.mjs` writes three panels — raw RGB | RGB composited over white by alpha | alpha. The middle panel looks near-white for low-alpha fog; judge fog from panel 1 + alpha.

---

## aerogel-smoke-hdr

**Idea Card (as implemented)** — see BRIEFS-forkD.md; implementation differences from the card are listed under "Deviations".

| # | Idea | Where in the WGSL | Formula row |
|---|---|---|---|
| 1 | Rayleigh λ⁻⁴ chromatic extinction: `transC = exp(−ρ·gain·σ)`, σ=(0.41,0.80,1.79) blended to grey by Blue Scatter; scene × `transC` (reddens transmitted light); in-scatter × `selfAtt=(1−e^{−τ})/τ` | `// ── Idea 1` (`sig`, `tau`, `transC`, `trans`, `selfAtt`) | §12.2F Rayleigh |
| 2 | Phase functions toward a drifting lamp behind the smoke: Rayleigh `0.75(1+cos²θ)` on the blue term, forward HG (g=0.6) × soft inverse-square on the Mie term | `// ── Idea 2` (`lampV`, `cosT`, `rPhase`, `mPhase`) | §12.2F Henyey–Greenstein (+ Rayleigh lobe) |
| 3 | Energy-conserving bloom: core scatter × (1−k), wide 8-tap ring of the energy channel (inner 4 + 4 diagonals at ~H/90 px) gives it back, k=0.4·bloom | `// ── Idea 3` (`br`, `wide`, `k`) | §12.2F energy-conserving bloom |

**KEEP VERBATIM (unchanged):** whole sim update (advect, diffusion mixes, buoyancy-ish `vel`, brush, click rings, decay, clamps); 4 params and their roles/ids/defaults; state packing; Rayleigh vector (0.18,0.62,2.4), Mie vector (2.6,1.45,0.42), `rim`; ACES on writeTexture only; alpha = 1 − trans + 0.2·rim (trans is now the mean of the three channel transmittances).

**A packing:** raw sim state (ρ, energy, vel.x, vel.y) — unchanged, not tone-mapped.

**Rescues**
- *Finding 1 (pass-through at default): CONFIRMED.* HEAD at defaults, no pointer, no click: `meanA 0.000`, picture = source. Added an idle emitter = the existing brush on autopilot (Lissajous path, 25 % strength, off while the pointer is held; same ρ/energy/vel injection). Result at defaults, 400 frames: `meanA 0.062`, visible drifting smoke plume. **This changes the default look (pass-through → plume).** Pointer/click behaviour is byte-identical.
- *Finding 2 (`pow(x,2.0)` click ring):* replaced by `rr*rr` (bit-identical for finite values). Latent on real GPUs, SwiftShader never showed NaN (HEAD and new: nan 0). NOT a confirmed bug.
- *In-scatter cap `selfAtt`* (part of Idea 1): HEAD's scatter was linear in ρ without limit and at ρ≈2 blew out to flat white. `selfAtt` is 1 for thin smoke and 0.39 at ρ=2/gain 1.15. **Changes thick-smoke brightness** (dimmer, shows colour) — say so in review.

**Deviations from the card:** (a) idle strength 25 % (card said "small"); (b) the Mie lamp falloff is `0.9/(0.25+d²)` clamped with HG to [0.2,5]; (c) Idea 3's halo vector (0.75,1.63,3.75) = HEAD's (0.3,0.65,1.5) scaled so the halo carries the same amount as HEAD's at bloom 0.5 (k=0.2); the core gives up the same 20 %, but the halo keeps HEAD's blue-white tint and energy-channel units, so conservation is "in kind", not photometrically exact.

**Pixel diff vs HEAD** (256 px, 400 frames, dragged pointer, p=0.08,0.8,0.5,0.5): mean |Δ| over RGBA = 0.0140. Ablations (mean |Δ| new vs new-with-idea-off): lamp phase 0.0187, chroma+cap 0.0050 (cap alone 0.0038), bloom k=0 0.0036. Each idea is individually visible in the data; the chromatic extinction on its own is the subtlest at low density.

**[SUPERSEDED — fixed in the Follow-up section below] HEAD observation (originally reported as not fixed):** integer advection `round(vel·res·dt)` plus per-component velocity clamp ±1 gives terraced, rectangular smoke edges (also a saturated white *square* if the pointer is held still ~6 s). Identical in HEAD at 256 px and 512 px.

**Timing** — see the Timing section. **Gates:** precommit 1/1, naga-wasm 1/1, dead sliders 0 new (4/4 `zoom_params` read), `audit_extrabuffer` PASS.

---

## atmos-fog-volumetric

| # | Idea | Where in the WGSL | Formula row |
|---|---|---|---|
| 1 | Beer–Lambert on real scene depth: `dist=0.08+0.92(1−depth)` (MiDaS inverse depth, 1=near); each of the 8 slices counts only while `z<dist` (smoothstep window) — near objects stay clear, far ones fog | `// ── Idea 1` (`dist`, `front`) | §12.2F Beer–Lambert |
| 2 | HG forward scatter toward a per-pixel sun direction: ray `normalize(((uv.x−.5)·aspect, .5−uv.y, 1))`·`sun` → two-lobe HG (g=+0.55/−0.2) drives the existing warm↔cool mix (`phase`) and the in-scatter gain (`glare`) | `// ── Idea 2` (`ray`, `cs`, `hg`, `phase`, `glare`) | §12.2F Henyey–Greenstein |
| 3 | Exponential height fog: density × `exp(−max(0.5−uv.y,0)·2.6·z/(0.15+0.55·height))` per slice (one `exp` per pixel, repeated multiply per slice) | `// ── Idea 3` (`hStep`, `hf`) | §12.2F height stratification |

**KEEP VERBATIM:** whole sim update (advect, diffusion, `terrain` source band, turbulence, pointer clear/moisture/stir, click rings, decay, clamps); 4 params and roles; per-slice `layer` formula and `absorb` structure; HEAD's colour pair (cool (0.2,0.32,0.48) / warm (1.4,0.92,0.5)) — only *where* each applies changed; ACES on writeTexture; alpha = 1 − trans.

**A packing:** raw sim state (ρ, vel.xy, moisture) — unchanged.

**Rescues / findings**
- *Finding 1:* does not apply (ambient `terrain` source; HEAD defaults meanA 0.031).
- *Finding 2:* `pow(x,2.0)` → `x*x` in the `terrain` Gaussian and the click ring (latent on real GPUs; SwiftShader NaN 0 before and after).
- *Finding 3:* the `depth-aware` / `beers-law` tags and the `Depth Weight` slider were not backed by any depth read; Idea 1 makes them true. `sun` was a constant vector whose only used component was `.z` (a per-pixel-constant phase); Idea 2 gives it a per-pixel angle. The JSON promised "height-based density mixes with Beer's Law"; Idea 3 adds the height profile.
- With no depth map (all zeros) `dist=1` and slices behave as HEAD; only the HG/height terms differ.
- Default look changes: warm glare is now localised around the sun (upper-left, ≈(0.19,0.07)) and cooler away from it, instead of one flat warm tint; near objects are no longer fogged.

**Pixel diff vs HEAD** (256 px, 400 frames, p=1,0.5,0.6,0.5): mean |Δ| 0.0424. Ablations (new vs new-with-idea-off): depth 0.0308, HG sun 0.0057, height 0.0037. Height fog is the weakest of the three (the HEAD `terrain` band already concentrates fog near `height`, so little is left above it to thin).

**HEAD observation, NOT fixed (jitter only; the terracing noted below it IS fixed, see Follow-up):** the per-slice jitter `hash21(p + (j·31, time·0.4))` is a per-pixel white hash that changes every frame (frame-hash static on the fog density, ±25 %). Left as is (update/jitter structure is KEEP VERBATIM). With a held pointer the same integer-advection terracing as aerogel shows up (identical in HEAD).

**Gates:** precommit 1/1, naga-wasm 1/1, dead sliders 0 new (4/4 `zoom_params` read), `audit_extrabuffer` PASS.

---

## JSON
Both: `description` extended (visible behaviour changed), `features` += `audio-reactive`, `upgraded-rgba` (both are true: `plasmaBuffer[0].xyz` modulates the sim; ACES present and Idea Cards implemented). `params`, `x-meta.upgrade.params`, `tags`, `feedbackPacking` untouched.

## Cross-fork de-dup
HG appears on both files (cap 2): aerogel = point lamp + inverse-square + Rayleigh lobe; fog = distant sun + per-pixel ray. No spring/extraBuffer/ripple/IQ overlay anywhere; the idle emitter exists on aerogel only. §12.4 note: aerogel uses three rows (Rayleigh, HG, energy-conserving bloom), one above "at most two"; each is one expression in the existing render tail and the batch claim table assigned all three to this file.

## Timing (SwiftShader, `agents/mr_perf.mjs`, 320 px, 40 frames, 2 ripples, HEAD/new interleaved, 9 rounds)

**The box was at load average ≈ 19 (five forks timing at once), so single rounds swing 0.65×–1.64×.** Treat these as an upper-bound sanity check, not a measurement; the coordinator should re-time on a quiet box.

| file | best-of ratio (min new / min HEAD) | median of per-round ratios | per-round range | cap ≤ ~1.3× |
|---|---|---|---|---|
| atmos-fog-volumetric | 1.02 (HEAD 17.7 ms → new 18.1 ms) | 1.10 | 0.65–1.40 | within |
| aerogel-smoke-hdr | 1.21 (HEAD 12.2 ms → new 14.7 ms) | 1.11 | 0.74–1.64 | within (closest to the cap: +4 energy-channel loads, 1 pow, 3-channel exp) |

Static cost: atmos-fog adds 1 depth sample, 1 `exp`, 2 `pow` per pixel and 8 `smoothstep` (the per-slice `exp`/hash are unchanged); aerogel adds 4 `textureLoad`, 1 `pow`, 1 `inverseSqrt` and 2 extra `exp` per pixel. No trimming was needed.

---

## Follow-up (coordinator request): boxy plumes — root cause fixed in aerogel-smoke-hdr and atmos-fog-volumetric

**Trigger.** My idle emitter (Finding 1) exposed HEAD's terracing at the *default* view, not just under a held pointer; the coordinator rejected a rectangle as the default look. Reproduced at 224 px / 200 frames / t=7 (hard-edged terraced box).

**Root cause (measured, not guessed).** Three HEAD mechanisms, in order of impact:
1. `round(vel·res·dt)` integer snap + per-axis rounding in the back-trace (the coordinator's diagnosis).
2. Per-component velocity clamp (±1 aerogel, ±0.8 fog) → a square velocity distribution.
3. **The rho-gradient swirl `vel += (n.x−s.x, w.x−e.x)·gain`** (gain 0.22 aerogel, `0.12+0.4·turb` fog) — found by ablation at 256 px, pointer held 300 frames: removing it alone took the plume's diagonal/axis extent ratio from 1.23–1.41 (square) to 0.98 (circle) and velocity roughness `|v−avg4(v)|/|v|` from 0.067 to 0.026. Its steady state is gain ÷ (1−e^{−1.25/60}) ≈ 10× the 2-px density difference, so at every density cliff it pins velocity at the limit and shears the rim into axis-aligned facets. Fixes 1+2 alone removed the terraces but left a rounded square.

**Changes (same idea as fork C's jelly rescue J1: manual bilinear + one magnitude limiter — shared, with this file's own units).**
- Back-trace: `sp = p − vel·res·dt`, 4 exact `textureLoad(dataTextureC)` blended by hand (`mix`/`mix`/`mix`, clamped by `stateAt`); no filtering sampler on rgba32float. +3 loads.
- Velocity limit: per-component clamp → `vel *= min(1, VMAX/|vel|)`, **VMAX 1.0 (aerogel, uv/s, = HEAD's per-axis peak) and 0.8 (fog)**. Fork C's 0.03 is uv/frame on jelly (= 1.8 uv/s); sweeping 1.0 / 0.6 / 0.3 on aerogel showed 0.3 is *worse* (roughness 0.25 idle/held, 11–13 % of pixels pinned at the limit) and 1.0 ≈ 0.6 — so 1.0 keeps HEAD's speed ceiling.
- Swirl: same gain for faint smoke, **soft-saturated per-frame injection** `gs·(gain·0.025/(0.025+|gs|))` (max `gain·0.025` per frame). Tested against plain gain reductions (0.11 / 0.055 / 0.0275 of HEAD's 0.22): those still left faceted held plumes (ratio 1.07–1.08); the soft saturation gave 1.03 and kept HEAD's linear response where gradients are small. **This does change the swirl in dense smoke (rescue, loud).**
- Untouched: brush/clear/click injection lines (byte-identical to HEAD apart from the earlier `pow`→`x*x`), diffusion mixes, decay constants, ρ/energy/moisture clamps, A packing (raw state), params, idle emitter, all three Ideas per file, no new extraBuffer.

**Measured (SwiftShader, raw state via a debug variant that writes `(vel, ρ, aux)` to writeTexture; 300 frames; `mr_c_abs.mjs`; JSON-default params; aerogel):**

| scenario | HEAD-after-ideas (before follow-up) roughness @256 / @512 | now @256 / @512 | `|v|max` before → now @256 |
|---|---|---|---|
| idle | 0.220 / 0.309 | 0.066 / 0.069 | 1.34 → 0.27 |
| held still | 0.142 / 0.108 (bbox fill 0.92 = square) | 0.029 / 0.021 (ratio 0.98 @512 = circle) | 1.41 → 0.50 |
| dragged | 0.276 / 0.279 | 0.055 / 0.055 | 1.41 → 0.60 |
| aging click (abs start 0.3 s) | 0.218 / 0.260 | 0.069 / 0.069 | 1.18 → 0.27 |

NaN 0 in all 8 cells and in the 5 picture renders; no pixel pinned at the limiter (`frac_mag_sat` 0.000).

**Pictures (Read, not just numbers).** Aerogel at 224/200/7 and 256/300 idle: soft curled plume with smooth edges (was a terraced box). 512 px: idle = soft plume; held still = round disc; dragged = rounded stripe (tiny notches along the top edge from the 1-px pointer stamps); aging click = plume + ring. Atmos-fog, alpha panel at 256 px, p=0.6,0.5,0.8,0.5: pre-fix showed a hard clear *square* (held), a terraced stripe (drag) and a square (click); now rounded/soft blobs. A short diagonal staircase remains at the start of a dragged-pointer clear (also in HEAD), not a box — left.

**Click test note.** The stock `mr.mjs` RIPPLES third value is a *constant age* (`ripple.z = t − r[2]`); my earlier click renders pinned the ring at one age. All follow-up click runs use `agents/mr_c_abs.mjs` (absolute start time 0.3 s, ring ages from 0 over the 5 s).

**Cost (re-timed vs the HEAD copies, interleaved, 8 rounds, `mr_perf.mjs` 320 px):**

| file | best-of | median | note |
|---|---|---|---|
| aerogel-smoke-hdr | 1.27 (loaded box) / **1.22 (quiet box, load ≈2)** | 1.21 / **1.25** | close to the cap: 13 loads vs HEAD's 7 (+3 bilinear, +4 bloom ring) |
| atmos-fog-volumetric | 1.09 | 1.17 | +3 loads, +1 depth sample |

**Pixel diff vs HEAD (now includes the follow-up):** aerogel dragged, p=0.08,0.8,0.5,0.5: 0.072 (was 0.014 before — the HEAD dynamics are intentionally different now); atmos-fog p=1,0.5,0.6,0.5 idle: 0.043 (unchanged — the fix only matters under interaction).

**Gates re-run after the follow-up (both files):** precommit 1/1 each, naga-wasm 1/1 each, dead sliders 0 new (4/4 `zoom_params` read in each), `audit_extrabuffer` PASS (0 out-of-range). Saved `params` untouched, JSON untouched by the follow-up.

**Not verified / residual:** no real-GPU look; the held-still plume and dense drags are still saturated white where ρ hits its HEAD clamp of 2.0 (dense smoke, not a boxing defect); the aerogel timing is within ~4 points of the 1.3× cap on this box — re-time on a quiet box before landing.
