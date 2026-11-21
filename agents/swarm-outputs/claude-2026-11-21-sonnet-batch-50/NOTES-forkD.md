# NOTES — fork D (sonnet/batch-50): dragon-core + serpent-ouroboros

Cards + mechanism interrogation + amendments: `BRIEFS-forkD.md`. Nothing committed. Repo files touched: the two `.wgsl`, the two `shader_definitions/generative/*.json` (description only). `reports/*` got re-dirtied by the audit scripts I ran (coordinator discards).

Scratch (HEAD copies, renders): `/tmp/claude-0/-root-image-video-effects/12631154-16b4-44ad-a621-195684eec032/scratchpad/d/`.

---

## gen-symbiotic-bismuth-crystal-dragon-core

**RESCUES (loud — the default picture changes completely)**
1. **All four sliders were dead and the mouse mis-routed.** HEAD pasted `Uniforms { config, zoom_params, zoom_config, ripples }`; engine order is `config, zoom_config, zoom_params, ripples`. Proof at HEAD: sliders `1,3,.5,0` vs `2,6,1.5,.7` -> bit-identical picture (mean |diff| 0.0); moving the mouse changed it (13.3). zoom_level was time, complexity = mouse x, breathing = mouse y, iridescence = mouse_down, "mouse_uv" = sliders 2/3. Fixed by replacing the pasted header+struct with `#include "_prelude.wgsl"` by hand (codemod refuses this on purpose). HEAD's picture was a flat gold smear; the labyrinth was never visible. The saved defaults 1.0/3.0/0.5/0.0 were never actually applied before.
2. **Step-exhausted rays were shaded as hits** (`mat_id` stays >= 0 when the 100-step loop ends without landing) -> speckle: 0.6 % of pixels at complexity 3, 2.3 % at complexity 5 (scratch A/B). Only a real landing (`landed`) counts now.
3. `pow(1 - n.v, k)` base is clamped to [0,1] (n.v = max(dot,0) is not bounded above; latent NaN, unproven on SwiftShader).

**Idea Card — ADD (2; both visible in the diff; code labels continue the file's own numbering, so card 1 = `Idea 4`, card 2 = `Idea 5`)**
1. **Fold-count oxide terraces (§12.2E "fold count as material")** — `folds += dot(select(0,1,bp<0), 1)` inside the existing KIFS loop -> `g_fold`; `oxide = g_fold*0.11` offsets the iridescence palette phase (`iridescence_shift` keeps its role as the global phase). Effect: every terrace gets its own oxide colour (teal/magenta/gold/violet mosaic) instead of one purple.
2. **Schlick conductor Fresnel silver rim (§12.2F "Fresnel–Schlick")** — `F = 0.04 + 0.5*(1-n.v)^9`; grazing terrace walls mix toward silver (tinted 22 % by the oxide colour so identity survives). First version (`0.05 + 0.95*(1-n.v)^5`) greyed the whole tunnel (it is mostly seen at grazing angles) and was tightened.
- **Dropped with evidence (see BRIEFS amendments):** SDF curvature edge wear (one-sided + floor()-stepped DE: tetra Laplacian positive on 39 % of crystal pixels, never negative; shell stencil only ~1 % speckle at 3 sizes) and over-relaxed sphere tracing (min 427 vs 423 ms: no speed-up).

**KEEP VERBATIM held:** 4 param roles, KIFS fold/rotate/stepped-modulation loop, modulo repetition, artery + mouth cap + lumen, smin seam, ichor seep, heart-bolus, furnace underlight + haze, mouse gravity well, ACES display, depth, semantic alpha. Saved JSON `params` untouched (description appended only).

**A packing:** ACES display RGBA in A, stateless, no C read (unchanged). No extraBuffer use.

**Numbers (256 px, SwiftShader, box at load 40-55 from the other forks — timing is NOT reliable)**
- diff vs HEAD at defaults: 87.9 % of pixels differ > 8/255 (rescue 1 dominates); ideas-only diff vs the prelude-fixed baseline: 45.8 % (mean 32/255).
- NaN 0 in all renders (defaults, bass .5, click+mouse, zoom .5). meanL 0.598 (HEAD) -> 0.444, stdL 0.145 -> 0.221.
- cost vs prelude-fixed baseline (interleaved min / p25 / paired-median): complexity 3: 1.26 / 0.90 / 0.77; complexity 5: 1.29 / 1.15 / 1.16. Pure ALU (one dot+select per fold, one pow + mix per hit). Coordinator should re-time on a quiet box.
- Gates: precommit naga OK; verify-naga-wasm 2/2 valid; dead sliders: grepped by hand, `zoom_params.x/y/z/w` all read (lines 78-81 + main); extraBuffer audit pass. Precommit WARNs "still pastes a non-canonical header (struct-field-order)" only because the id is still in `src/contracts/prelude_migration.json` pending with that reason — `verify:shaders:fix` removes it (the file now includes the prelude).

**Open calls:** the capped artery mouth fills ~35 % of the frame end-on at default (author's 09-27 composition, not touched); crystal wear needs a continuous DE to be worth doing (the floor() terraces make the DE discontinuous).

---

## gen-quantum-chrome-serpent-ouroboros

**Diagnosis of the near-black default (app feeds all four sliders 0.5; JSON has no `params`, so the intended x-meta defaults 1.5/1.0/2.0/1.2 never reach the shader):** meanL 0.072 / stdL 0.024. Causes: (1) chrome reflected an environment that peaked at ~0.1; (2) twist was a shear; (3) camera is near edge-on to the ring (<=14 deg elevation, 0 at t=0) with p4 acting as FOV (focal = 1/(0.5*p4): 14 deg total FOV at 0.5) so the app default is a dark close-up slab of the near tube. (3) is the author's framing and was left alone (lifting the camera puts the centre ray through the ring hole -> empty void at the app FOV; recorded for the coordinator).

**RESCUES (loud)**
1. Environment strips raised: same two cyan/purple sine bands, `0.1 -> 1.2` amplitude and `pow 4 -> 10` so the void stays dark between narrow neon strips; chrome now has something to reflect. meanL 0.072 -> 0.19, stdL 0.024 -> 0.165 at the app default.
2. Twist shear fixed: `pos.z` used the already overwritten `pos.x`; now a true rotation (temporary variables).
3. `pow(1 - n.v, 5)` base clamped to [0,1] (latent, unproven).
4. Header A-packing corrected: code stores the PRE-ACES `col` in A and reads it back as colour history; ACES only on writeTexture (HEAD header claimed "ACES display RGBA").

**Idea Card — ADD (3)**
1. **Ouroboros head-swell / tail-taper profile** (native anatomy, no §12.2 row) — `s = fract((theta - 0.12 t)/2pi)`; radius = tail taper (1 -> 0.55 over s .5..1) x neck (0.55 -> 1 over s 0..0.05) + head bulge (0.3, polynomial bump at s=.07); continuous at the seam (0.55 both sides); circulates slowly. Seen at wide FOV: a swollen head with the tail narrowing into it.
2. **Shingled keeled scale plates** (tactic 1, deepens the same scale operator; no row) — brick-offset (theta, phi) lattice, counts `nU = floor(10*p2*8)`, `nV = 2*floor(1.2*10*p2)` (integers so it closes around both angles; Scale Density keeps its role), sawtooth overlap with a bowed (rounded) free edge, keel down the plate, amplitude 0.045; the sine-product swell is kept.
3. **Step-count AO on the chrome reflection (§12.2E)** — 2 taps up the normal (cut from 5 for cost), occludes env reflection, diffuse and half the spec in the plate grooves.

**KEEP VERBATIM held:** 4 param roles (p1 coil twist, p2 scale density, p3 core heat, p4 FOV), torus r1 3 / r2 0.8, sine-product scales + audio bump, KIFS micro term, Schlick conductor Fresnel (already at HEAD; kept, not extended), audio chromatic reflection aberration, dispersion trail, fbm plasma leak, fog, 5 % temporal blend, 0.7 under-relax march. Cauchy dispersion NOT added (metals do not disperse; fails the expert test).

**A packing:** raw linear pre-ACES `col` + alpha in A, read back as C colour history (`prev.rgb*0.92` 5 % blend); ACES on writeTexture only (unchanged; header text corrected). Depth written. No extraBuffer use.

**Cost control (first version was 1.8-2.4x HEAD):** far-zone early-out `if (d_coarse > 0.15) return` (plates move the surface < 0.04, KIFS adds < 1 %); `sdTorus(r2+dr) = sdTorus(r2) - dr` so plates reuse the coarse distance; `exp()` in head bulge and keel replaced by polynomial bumps; arch computed once; AO 5 -> 2 taps.

**Numbers (256 px, box at load 43-55 — NOT reliable)**
- diff vs HEAD at app default: 70.5 % of pixels differ > 8/255 (mean 61.6/255), dominated by rescue 1.
- NaN 0 at: default, p2=.1 + FOV 2, p2=2.5 (200 plates, aliases at 256 px as expected), max params + click + bass .9 at t=60.
- cost vs HEAD after trimming (interleaved, several runs): min 1.25 / 1.28 / 1.86 (load spikes), p25 ~1.57, paired-median 1.3-1.5. **Probably still above the 1.3x cap; the coordinator must re-time on a quiet box.** If it is over, the cheapest lever is dropping the AO to 1 tap or the head-profile smoothsteps.
- Gates: precommit naga OK; verify-naga-wasm 2/2 valid; dead sliders: JSON has no `params` (audit scans 0 defs) -> grepped by hand, `zoom_params.x/y/z/w` all read (lines 102 / 124 / 292 / 273); extraBuffer audit pass.

**Open calls:** (a) JSON has no `params`, so the app never shows or applies the x-meta defaults and the "Dispersion" slider is really the FOV (rewiring it would be param theft; adding `params` is outside the brief); (b) the ring is only ever seen edge-on / as a near-tube close-up at the app FOV; (c) at the app default the plates are large tiles (40 around the ring) — a viewer sees ~3 plates across.
