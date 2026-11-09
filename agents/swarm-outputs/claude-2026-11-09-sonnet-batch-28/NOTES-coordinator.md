# NOTES — coordinator (generative-psy-swirls + psy-swirls, interactive-origami-coupled, murmuration)

Harness: SwiftShader WebGPU single-dispatch render harness (scratchpad; `README.md` there). Structural / PNG evidence only — **no real-GPU visual QA claimed.** The harness cannot run `@group(1)` sim-ring shaders, so murmuration is Naga + gate verified only (see open items).
Plumbing: 8 files migrated to `#include "_prelude.wgsl"` with `scripts/migrate_to_prelude.py` before any idea work (infrastructure, no `Upgraded:` bump for it).

## generative-psy-swirls (+ psy-swirls — same WGSL; both JSONs keep `params` byte-exact)
**Kept verbatim:** 4 slots (twist / layers / frequency / depth-reduction; psy-swirls labels the same four slots swirl_speed / layer_count / rainbow_speed / twist_intensity — label/role mismatch is pre-existing and was not touched), arm × ring product, fbm warp, mids hue fan, R/G/B layer stagger, click ring, 0.04 trail mix + 1.2 clamp, ACES(color·1.1), alpha, relief depth.
**A packing:** raw trail colour (clamp 1.2, pre-ACES, C read as colour); texel (0,0) = (glide.xy, 7, fract(time)).
**Ideas (`// ── Idea n` in `layeredSwirlLayer`):**
1. Arm-wound hue — `hue += wound/TAU`, `wound = a + d·twist·freq`; continuous across the atan2 seam (jump of exactly 1.0).
2. Rankine eye-wall cores — `coreR = 0.05 + 0.07/(1+0.5·twist)`, calm eye `smoothstep`, Gaussian wall ring (+0.5 val).
**Rescue R1:** HEAD's spring state in `extraBuffer[133..138]` is re-uploaded zero every frame, so it always fell back to the raw cursor. Replaced by a first-order glide (rate 8 = HEAD ω) in A(0,0); C(0,0) masked in the trail read. Visible change: none at rest; moving, layer centres lag the cursor ~1/8 s.
**Default look: yes (ideas).** Harness 576 px, 30 frames, params .5 ×4, idle cursor: meanL 0.2469 → 0.2056, stdL 0.1899 → 0.1812 (eye darkens each layer centre; hue now spirals). nan 0 in every render (192/576, params 0,0,0,0 and 1,1,1,1, held cursor, audio 0.8,0.5,0.9, click ripple). Viewed PNG: recognisably the same swirl field, rainbow now follows the arms, thin eye-wall rings near the layer centres (busy where several layer centres overlap — QA on real GPU).
**Formula rows:** none from §12.2 (both ideas are the file's own vortex vocabulary).
**Gates:** Naga valid, precommit gate pass, dead sliders pass. JSON: dropped the now-false `sprung-mouse-vortex` feature from `generative-psy-swirls.json`; `psy-swirls.json` unchanged (it never claimed it).

## interactive-origami-coupled
**Kept verbatim:** 4 params, crease height + finite-difference grad, advection/viscosity, pointer drag + vortexDir, click push, edge damping, capillary pooling, Kármán street (same crease, same amplitude law), tint, lighting, specular, ACES, alpha.
**A packing:** raw (vx, vy, **curl**, density) — z is now the true curl (HEAD stored `vel.x − vel.y`); texel (0,0) = (prevMouse.xy, 7, fract(time)), masked to zero in `loadFluid`.
**Ideas:**
1. Vorticity confinement (§12.2D) — real curl from 4 C neighbours, ∇|ω| from their stored z (one frame old), `f = ε·(N.y, −N.x)·ω`, ε = 0.5·Vortex Strength.
2. Crease gutters — `vel −= grad·dens·0.0008·(1+0.5 bass)·foldInfluence` (grad points uphill): pooled fluid drains along the folds.
**Rescue R1 (the big one):** `prevMouse` came from `extraBuffer[133..134]/[138]`, re-uploaded zero every frame → `mouseVel = 0` always → pointer drag, `vortexDir` and the Kármán street (all ∝ mouseVel / mouseSpeed) never ran in HEAD. Now prev pointer is read from A(0,0); a smoothstep dead-zone (0.04–0.12 uv/s) absorbs f16 quantisation of the stored position. **R-phase:** street phase was `time·(4 + mouseSpeed·10)`; now `−time·4` (speed stays in amplitude) — it would have strobed the moment R1 made it live.
**Default look:** idle cursor identical (meanL 0.4936 → 0.4937, 60 frames). Moving pointer (synthetic circular path in a scratch copy): HEAD fluid state is all zero (A = 0), new state is a live velocity/density wake. meanL 200 frames: 0.4693 (HEAD 0.4693) — the fluid only tints and shifts ≤ ~2 px, so the displayed mean barely moves; stable between 60 and 200 frames (0.4692 / 0.4693), nan 0. Confinement on vs off at Vortex 1.0: curl std 0.023 → 0.091 (it injects curl, as designed) without growth over time.
**Gates:** Naga valid, precommit gate pass, dead sliders pass. JSON: `feedbackPacking` text updated; params unchanged.

## murmuration (`murmuration-flock.wgsl` + `murmuration-render.wgsl`; JSON unchanged)
**Kept verbatim:** all four params and roles, hash window / MAX_VISITS, sep/ali/coh weights, wind, predator, vmin/vmax, stamp patch, crowding statistic (still unweighted `count`), diffusion + keep, silhouette thresholds, chromatic wake taps, sunset sky, A/C packing (.rgb emission, .a energy), ACES, alpha 1.
**A packing:** unchanged. No new state.
**Ideas:**
1. Forward vision cone (flock pass) — alignment and cohesion neighbours weighted by `smoothstep(−0.35, 0.25, cos angle(heading, d))`; separation untouched; a bird with only rear neighbours (`wsum ≈ 0`) is gated rather than divided by ~0.
2. Sunward rim (render pass) — rim light × `0.3 + 0.9·smoothstep(−0.2, 0.6, n_out·sun)` with `n_out = −∇crowd`; the sun is the horizon glow of `sunset()`. Wake haze stays non-directional.
**Verified:** Naga valid (both files), precommit gate pass, dead sliders unchanged. `tests/sim-hash.swiftshader.spec.ts` (real engine, SwiftShader, built `build/`, main + worker render thread) passes 6/6: murmuration compiles, plans 3 passes and draws. That is compile/draw proof only — the single-file harness has no sim-ring support, so flock dynamics under the cone (ribbon vs blob, any clumping) are untested. Open item for real-GPU QA: if the cone makes flocks chase their own heads (cohesion forward bias) lower the −0.35/0.25 window.


## Closeout gates (coordinator)
Naga 10/10 valid; `wgsl_precommit_gate` 10/10; `audit:extrabuffer` clean; `audit:dead-sliders` 10 defs, 0 new dead; `generate_shader_lists`; Vitest 203 files / 1822 passed; `npm run build` ok; sim-hash SwiftShader spec 6/6 (needed `PLAYWRIGHT_BROWSERS_PATH` symlinks because the VM's Chromium revision is 1243, the repo's Playwright wants 1228). Coordinator tuned spec-bicubic-crystal Beer–Lambert σ to half after fork A's first pass measured 13% darker (now −6%: meanL 0.4822 → 0.4526).
