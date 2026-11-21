# COORDINATOR_REVIEW — sonnet/batch-49 (9 files, 5 forks A–E)

Worktree `/root/iv-sonnet-batch-49`, branch `sonnet/batch-49` from origin/main d5c0fca6. **Uncommitted.** No real-GPU visual QA (SwiftShader only).

## Corrections to my own COMMON.md (read these first)

1. **My "click render → nan 0" check in COMMON.md Finding 2 was invalid.** Stock `agents/mr.mjs` treats the 3rd `RIPPLES` value as a *constant age*, not a start time (`z = t - r[2]`). With `RIPPLES='x,y,0.1,0'` the ring radius never grows past `age*speed ≈ 0`, so `length(cq) - radius` is never negative and `pow(neg, 2.0)` is never exercised. Fork C caught this (`agents/mr_c_abs.mjs` takes an absolute start time). I re-ran all four HEAD shaders (aerogel, heat-haze, atmos-fog, magnetic) with an aging click: mean alpha is now non-zero (ring active) and **NaN is still 0 on SwiftShader**. So Finding 2 stays "latent on real GPUs, unproven here", now on a valid test. Every file replaced `pow(x,2.0)` with `x*x` (bit-identical for finite values).
2. **My claims table let aerogel carry three §12.2 rows** (Rayleigh, HG, energy-conserving bloom). §12.4 step 3 says "at most two rows per file". Fork D disclosed it. Recorded as a deviation below, not hidden.

## Per-file result vs the §9 checklist

All nine: Idea Card written before the diff (BRIEFS-fork*.md); every idea findable at a `// ── Idea n` / `// Idea n` marker; saved `params` byte-identical to origin/main (checked by script); `#include "_prelude.wgsl"`, no pasted bindings; no `extraBuffer[` reference at all; A packing unchanged and stated; no spring / ripple overlay added; semantic alpha kept; clamps precede every `aces()`.

| File | Ideas shipped (formula rows) | Rescues | Diff / look | Cost vs HEAD (512 px, interleaved, quiet-ish box) |
|---|---|---|---|---|
| liquid-rainbow-prismatic (2nd pass; 2 old ideas kept) | film viewing-angle phase cosθ_t (thin-film phase); Fresnel-weighted film + transmitted energy (Fresnel–Schlick) | none | subtle in a still: 45% of px move >8/255 but the montage is near-identical at defaults | ~1.0× idle, ≤1.2× held |
| liquid-lens | Snell refraction; Jacobian-determinant caustic (main lobe only); deviation-proportional lateral CA | `smoothstep(b, b*0.35, d)` reversed edges → forward form (latent); exact early-out | far field exactly HEAD; core stronger when held | 1.1–1.27× |
| liquid-metal-prismatic | Cauchy band fan + prism-law fringe width; reflected strip light (sweep follows facet displacement) | none | sweep bar now bends into chrome ribbons (visible in montage) | ~1.0× |
| liquid-oil-iridescence | order-dependent thin-film colour (λ-scaled period, coherence washout); reflected radiance; thickness-dependent mobility | none | 89% of px differ because mobility changes the evolved state; picture still pearl-black islands with magenta/cyan/lime contours | ~1.0–1.06× |
| liquid-jelly-fluid | Beer-Lambert + subsurface wrap; Fresnel-Schlick + Blinn sheen | per-component ±0.065 velocity clamp → magnitude limiter 0.03 (HEAD was white-noise speckle under any held pointer — visible in montage) | translucent jelly instead of noise | 1.2–1.27× |
| interactive-magnetic-ripple-em | dielectric photo medium ε_r=1+2·luma; absorbing sponge boundary; Poynting-flux energy transport | **Faraday sign** (HEAD elliptic: one click → 99% of frame pinned at ±2.5, visible as a saturated noise disc) → staggered Yee update; div-clean made linear/dissipative; damping + source calibration; idle antenna (HEAD pass-through) | stable wave with fronts | 1.14–1.17× |
| aerogel-smoke-hdr | Rayleigh λ⁻⁴ chromatic extinction; lamp phase (HG + Rayleigh lobe); energy-conserving bloom | idle pass-through → idle emitter; boxing → bilinear back-trace + magnitude limiter 1.0 + saturated swirl injection (see follow-up) | idle = soft curled plume (was bare photo); held = round disc (HEAD white square) | **1.2–1.37×, median ≈1.28 — at the cap** |
| atmos-fog-volumetric | Beer-Lambert on real depth; HG toward per-pixel sun; exponential height fog (weakest) | same boxing fix as aerogel (limiter 0.8) | near objects clear, far sink; held clear is a soft blob | 1.0–1.44×, median ≈1.12 |
| heat-haze-volumetric | sun-baked surface source (scene luma); Boussinesq buoyancy; coherent curl-noise eddies (Gladstone–Dale weight) | idle pass-through; haze sank (+y is down; buoyancy sign); drift could not lift into empty air; depth tag with no depth read | still ≈ HEAD at idle on the synthetic image (motion effect) | 1.06–1.27× per-run median ≈1.1 (min-ratio 1.09–1.58 under load) |

## §12.4 de-duplication (rows per file)

Thin-film phase: rainbow, oil (2, theme files, different ideas). Fresnel–Schlick: rainbow, jelly (2; metal dropped its Fresnel idea after measuring ≤0.04 change). Henyey–Greenstein: aerogel, atmos-fog (2). Beer–Lambert: atmos-fog, jelly (2). Cauchy: metal only. Snell/Jacobian caustic: lens only. Rayleigh, energy-conserving bloom: aerogel only. Boussinesq, Gladstone–Dale: heat-haze only. Wave-in-matter / sponge: magnetic only. **No row appears on more than two files.** Aerogel alone carries three rows (deviation 2 above).

## Verification run by the coordinator

- Gates: wgsl_precommit 9/9, naga-wasm 9/9, dead sliders 0 new, extraBuffer pass, `npm run verify:shaders:fix` — all 11 shader gates pass. `npm run test:ci` 221 files / 2005 tests pass (1 skipped). `npm run build` ok. `upgrades:record` scoped `--ids=` (9 changed, 0 new).
- Visual (SwiftShader, synthetic image): rendered HEAD vs new montage for all nine; jelly, magnetic and aerogel rescues are unmistakable; oil, metal change visibly and keep identity; rainbow, lens, atmos-fog and heat-haze are subtle in a still. I Read the PNGs; I cannot judge real-GPU look.
- I sent fork D back after seeing a hard-edged rectangular plume at default (my Finding 1 idle emitter exposed HEAD's integer-advection defect). Fork D found a second cause (HEAD's density-gradient swirl) and fixed both; re-rendered idle/held for aerogel and fog and confirmed soft shapes.

## Open calls for the user

1. **aerogel cost** sits at ~1.28× median (cap ≈1.3×). Re-time on a quiet real-GPU box before landing; the cheapest trims are fewer bloom ring taps or dropping the lamp-phase term.
2. **Aerogel's three rows** vs the "≤2 rows" rule — keep, or drop energy-conserving bloom (smallest measured effect: 0.004 mean Δ).
3. **Behaviour changes at default** (all disclosed in the headers): aerogel, heat-haze and magnetic are no longer pure pass-through at idle; atmos-fog thickens for distant objects; oil's mobility changes motion; magnetic's wave speed in UV/s depends on working resolution (`srcCal=2.5` and the new damping were tuned by eye).
4. **Residuals not fixed:** dense held smoke saturates white where ρ hits HEAD's clamp of 2.0 (aerogel); fog's dragged clear keeps a short diagonal staircase (also in HEAD); jelly elastic-memory and MacCormack were tried and rejected (no measurable gain).
5. **Library-wide (not touched):** `writeExtraBuffer` zeroes `extraBuffer[133..255]` every frame (unchanged since batch 48); no file here uses it.

## Housekeeping

`agents/` is gitignored — notes need `git add -f`; the render/timing scripts `agents/mr*.mjs` are untracked copies. `reports/*` gate churn, `shader-id-aliases` and the search index were discarded; kept: nine WGSL + nine definitions, three `public/shader-lists/*.json`, `reports/shader-upgrade-ledger.json`, `src/contracts/prelude_migration.json`.
