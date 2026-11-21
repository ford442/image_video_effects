# NOTES — fork C (liquid-jelly-fluid, interactive-magnetic-ripple-em)

Scratch / evidence: `/tmp/claude-0/-root-image-video-effects/28bfd289-1a0d-46f8-916c-0eb131340909/scratchpad/c/` (HEAD copies, CPU port `em_port*.py`, raw-state variants, renders). Cards + interrogation: `BRIEFS-forkC.md` (+ its AMENDMENTS section). VM = SwiftShader, **no real-GPU visual QA**.

---

## 1. liquid-jelly-fluid (1st pass)

**Idea Card ADD (all in the diff, each under a `// ── Idea n` comment):**
1. Translucent jelly body — Beer–Lambert + subsurface wrap (§12.2F). HEAD's mix weight `density·dyeGain·0.55` is now treated as optical thickness τ: `T = exp(−σ·τ)` with σ = `(1−dye colour)·1.0+0.15` (cyan jelly eats red), in-scatter `color·(1−e^(−1.2τ))·0.5`, subsurface wrap `color·(0.35+0.65·wrap(n·L))·(1−e^(−1.4τ))·e^(−0.6τ)·0.8` (peaks at mid thickness → thin rims glow). Replaces the opaque `mix(src, color, ≤0.88)`; fixes the JSON's unbacked `subsurface-scattering`.
2. Wet-jelly sheen — Fresnel–Schlick + Blinn (§12.2F). Normal from the four neighbour densities HEAD already loads (0 extra loads), slope capped at 1; Schlick rim `0.04+0.96(1−n_z)^5` + `pow(n·h,56)` gated by `smoothstep(0.02,0.3,density)` so the flat idle jelly is unchanged; alpha gains `spec·0.15 + fres·0.08·body`.

**Rescue J1 (loud):** the three per-component clamps (±0.06 / ±0.06 / ±0.065 UV/frame) → one magnitude limiter `limitSpeed()` at 0.03. HEAD under a held pointer saturated 20 % of pixels at the clamp and left a pixel-scale velocity field (roughness `|v−avg4(v)|/|v|` **0.230 / 0.251 / 0.252 at 128 / 256 / 512 px**); the dye hue is keyed to `atan2(vel)`, so the picture became white-noise speckle that hid the photo. Shipped file: **0.042 / 0.026 / 0.015** at 128 / 256 / 512, mean |v| 0.047 → 0.024; idle unchanged (0.087 → 0.071 at 192², mean |v| 0.0153 → 0.0143). Ruled out as causes: vorticity confinement (removing it: 0.230 → no change), pressure term, hue smoothing alone (picture still speckle).

**KEEP VERBATIM (holds):** 4 param roles (viscosity → diffusion + density persistence, dye_intensity → dyeGain, vorticity_strength → confinement, elasticity → ribbon/click forcing); vorticity confinement; 1-iteration pressure; ribbon/KH forcing; pointer stir; click fronts; density source/decay; cyan/violet/lime palette and angle/curl mix; speed/packet emission with audio; photo displacement `uv+vel*1.8`; depth write.
**A packing:** raw state `(vel.xy, pressure, density)`, unchanged; ACES only on `writeTexture`; B / extraBuffer untouched. Alpha stays semantic.
**Tried, rejected, not shipped:** elastic pressure memory `mix(avg, p_c, ε)` (ε 0/0.5/0.8/0.95: KE 8–32e-5 in all, inside ambient noise) and MacCormack dye advection (needs +4 loads for the neighbourhood clamp; unmeasurable gain with nearest fetches).
**Diff vs HEAD (192², final RGB):** idle 150 f: 100 % of pixels differ > 0.02 (mean 0.045; 4.2 % > 0.1 — the whole picture is retinted by the absorption model, deliberately mild at the default); held 60 f: 99.7 % (52.4 % > 0.1, mean 0.094 — speckle → swirl); click 90 f: 100 % (8.9 % > 0.1).
**Timing (512², idle, 30 f, 5 interleaved rounds, load avg 9–17):** median 1.08× HEAD (range 1.01–1.56; the 1.56 round coincided with another fork's job). Added work is ALU + 0 loads.
**Gates:** precommit 1/1, naga-wasm 1/1, dead sliders 0 new, extraBuffer audit pass. NaN 0 in every render (idle / held / click / sliders 0 and 1 / audio 0.8,0.6,0.7).
**Header:** banner added (`Upgraded: 2026-11-21`, `Ideas:`, `Rescue:`, `A packing:`), original 3 comment lines kept. JSON: description appended; `upgraded-rgba` added to tags/features (ACES present, ideas implemented); `params`, `x-meta`, `feedbackPacking` byte-identical to origin/main (checked by parse-compare).
**Open / not verified:** held pointer for > 4 s still drives density to the 1.5 cap (HEAD behaviour; the jelly is now translucent instead of opaque, so the photo stays readable); small white sheen specks along a jagged dye boundary at 256² (visible in `jelly_final_blob.png`); no real-GPU look.

---

## 2. interactive-magnetic-ripple-em (1st pass)

**Rescues (all loud, all change the default look):**
- **R1 Faraday sign / scheme.** HEAD `B += c·curlE` with `E += c·curlB` ⇒ `∂²B/∂t² = −∇²B` (elliptic). CPU port, one B pulse, 128², clamp ±2.5: energy @10/60/120/240 f = 6.2 / 2.1e4 / 1.2e5 / 2.7e5 at default sliders (saturated), same at damping 0 and still growing at speed 0. GPU, HEAD, **true one-shot click** (t = 0.1 s, 128², defaults): 2.0e3 @30 → 5.9e4 @90 → 1.9e5 @150 → 3.0e5 @300 f, **99.4 % of pixels at |B| = 2.5** by frame 300; picture = a growing grid-aligned diamond of cyan checker noise (`em_head_click150.png`, `em_h_click.png`). Flipping the sign alone (forward Euler) blows up at the default speed (port: 0.52 → 1.6e-3 @60 → 5.0e4 @240). Fix: staggered Yee-style update (B with forward differences of E, then E from the new B with backward differences), 7 loads (HEAD 5), propagation constant `waveSpeed*0.77` (CFL ≤ 1/√2).
- **R1b divergence clean.** HEAD `E −= (∂xEx,∂yEy)·divE·0.025` is quadratic/indefinite; bisected on the GPU it alone drove the stable run to the clamp. Replaced by linear `E += 0.05·∇⁻(∇⁺·E)`.
- **R2 damping + amplitude.** `exp(-damping·(0.6+dt·30))` (≈0.91/frame at default) → `exp(-damping·0.04)` (ring-down ≈5 s at default; slider role unchanged). Sources multiplied by `srcCal = 2.5` because the instability had been supplying the amplitude (stable field peaks at |B| ≈ 0.1–0.5 with HEAD's constants and the display thresholds show nothing).
- **R3 idle antenna.** HEAD with no pointer/click: `meanA 0.000`, picture == photo. Now the held-dipole source runs at 0.35× on a small orbit (0.16 UV) around the pointer when not held (default pointer 0.5,0.5). Held behaviour unchanged. Idle 300 f: 16.9 % of pixels differ > 0.02 from HEAD (HEAD is pass-through).
- **R4** `pow((len−radius)*64,2.0)` → `rr*rr` (latent on real GPUs; SwiftShader never showed a NaN — unproven, not claimed as a confirmed bug).

**Idea Card ADD:**
1. Dielectric photo medium (§12.2D wave equation in matter): `eps_r = 1 + 2·luma`, `E += (cw/eps_r)·curl B'` → wave speed `c/√eps_r`; fronts slow in bright areas and refract around them (`em_f_held.png`, `em_f_click.png`: the wave distorts at the photo's bright/dark discs). Ablation (held + click 256² 300 f): 77.5 % of pixels differ > 0.02 (47.1 % > 0.1, mean 0.084).
2. Absorbing sponge boundary (§12.2D): `decay *= 1 − 0.15·ramp²`, `ramp = 1 − smoothstep(0, 0.09, d_edge)`. Ablation: 34.0 % / 12.0 % (mean 0.024).
3. Poynting-flux energy transport (§12.1 tactic 7): `S = (Ey·B, −Ex·B)`, upwind advection of the `energy` channel by `S/u·2cw` with the already-loaded neighbours (0 extra loads). Sign verified on a plane-wave packet (moves +x iff ΣEy·B > 0). Quietest idea: ablation 36.3 % > 0.02 but only 4.6 % > 0.1 (mean 0.015). Kept, flagged.

**KEEP VERBATIM (holds):** 4 params and roles (`fieldGain`, `waveSpeed` — also drives ring speed `0.11+0.16·waveSpeed` —, `damping` — also the click-ring fade `exp(-age·damping·7)` —, `spectral`); raw A packing `(Ex,Ey,B,energy)` with clamps ±2.5 / 0..4; held dipole + click ring sources (tangential E, ± B alternating by index); iron-filings `pow(cos(dir·10+…),12)`; cosine `spectralColor`; E-warp of the photo; semantic alpha `energy·0.32+filings·0.45`; ACES only on `writeTexture`. No spring/extraBuffer/IQ overlay added.
**A packing:** raw state `(Ex, Ey, B, energy)` — unchanged, not tone-mapped.
**Stability evidence (GPU raw state, final-form scheme):** one-shot click 128² defaults: E-energy 295 @30 → 3.9e3 @150 (source window ends at 2.4 s = 144 f) → 119 @300 → 0.03 @900 → 2e-5 @1800, 0 % pixels at the clamp; speed 1 / damping 0: 1.3e3 @300 → 20 @1500 → 1.9 @3000; idle 600 f max|B| 0.87; held 600 f at defaults max|B| 2.5 on ≈0.1 % of pixels at 128² (hotspot, measured before the last `srcCal` trim 3 → 2.5); NaN 0 everywhere. CPU port of the new scheme (ring, no source, sponge on): decays in all 8 slider combinations to 6000 steps; the one growing case (no sponge + varying ε + damping 0) cannot occur in the shader (sponge always on).
**Diff vs HEAD (192², 300 f):** idle 16.9 % > 0.02 (HEAD pass-through); held 100 % (99.6 % > 0.1, mean 0.37); one-shot click 99.3 % (99.2 % > 0.1, mean 0.41) — HEAD is the saturated noise diamond.
**Timing (512², held pointer, 30 f, interleaved):** first form (13-load leapfrog) median **1.47×** (1.24–1.75, 6 rounds) → over the cap, replaced; shipped 7-load form median **1.10×** (0.87–1.50, 7 rounds, load avg ≈ 11). Coordinator should re-time on a quiet box.
**Gates:** precommit 1/1, naga-wasm 1/1, dead sliders 0 new (all four sliders read: fieldGain, waveSpeed→cw & ring radius, damping, spectral), extraBuffer audit pass.
**Header/JSON:** banner (`Upgraded: 2026-11-21`, `Ideas:`, `Rescues:`, `A packing:`); JSON description rewritten for the visible behaviour, `audio-reactive` + `upgraded-rgba` added to tags/features (plasmaBuffer.xyz modulates sources/emission); `params`, `x-meta`, `feedbackPacking` byte-identical to origin/main.
**Open / not verified:** wave speed in UV/s depends on the working resolution (cw cells/frame ≤ 0.69; one-pass solver, no substeps) — at small sizes the click ring (0.19 UV/s) and the free wave are comparable, at 1080p the wake is much slower than the forced ring; the click ring is ≈1/64 UV wide, i.e. only ~3 cells at 192² (a wavefront at 512² is clean, at 192² it is a dot); real-GPU look; the `srcCal`/`0.04` calibrations are tuned by eye on SwiftShader.

---

## Housekeeping for the coordinator
- `agents/mr_c_abs.mjs` (untracked, `agents/` is gitignored) = `mr.mjs` with `ripple.z = r[2]` (absolute start time). Stock `mr.mjs` treats the 3rd RIPPLES value as a constant age (a click pinned at that age) — worth a one-line warning in the other forks' COMMON.
- The audit scripts rewrote `reports/dead_sliders_audit.*` and `reports/extrabuffer_write_audit.json` (timestamps); not mine to keep — discard.
- No commit, no stash, no shared generated files touched; `upgrades:record` / `generate_shader_lists` / `verify:shaders:fix` not run.
