# COORDINATOR REVIEW — sonnet/batch-39 (liquid / flame / iris / loom / obsidian / hex-cymatics ten)

Reviewed against `BRIEFS.md` (cards written before any WGSL edit), `NOTES-fork{A..E}.md`, and the diffs. Everything here is **structural + SwiftShader + numpy evidence. No real-GPU visual QA has been done**, and none is claimed. **No unanchored reviewer pass was run** (the user asked for the PR directly); the coordinator read the loom, obsidian, ambient and liquid diffs and the flame diff in full, and looked at the RD / hex renders. The other files are fork-reported and gate-checked only.

## Result at a glance

| Shader | Pass | Ideas landed (card → file) | Rescues (HEAD defect → result) | Alone re-time ×HEAD (256 px, idle / audio / clicks) |
|---|---|---|---|---|
| ambient-liquid-coupled | 1st | compound refraction + Beer–Lambert (§12.2F); torn-film rim bead | `vortex_strength` was DEAD (0.00 % → 3.10 %) via A-texel pointer track; `pow(neg)` | 1.01 / – / 1.15 |
| liquid | 2nd | Snell vector refraction (§12.2F); dispersive wake train (§12.2D); sun glint (optional 3rd) | dead spring term removed; two `pow(neg)` | 0.93 / – / 1.06 |
| viscous-drag | 2nd | thickness-gradient meniscus lighting; strain-directed smear | R1 sub-pixel advection **not shipped** (quantisation real, but bilinear = 0.24 % of pixels idle, blurs the trail held) | 0.98 / 1.05 / 1.06 |
| luma-velocity-melt | 2nd | Marangoni thermocapillary spread; rivulet meander | `pow(neg)` in click ring | 1.11 / – / 1.19 |
| gen-fractal-flame-classic | 2nd | colour-index averaging; two-layer tint (ring vs white-hot core) | **plateau**: flat orange wall stdL 0.011 → 0.163 | 1.12 / 1.12 / – |
| gen-iris-bloom-fractal | 3rd | hippus + click light reflex; contraction furrows; corneal catchlight (0.5 % of frame by design) | `pow` guard on HEAD's `crypts` | 1.12 / 1.13 / – |
| gen-prismatic-quantum-loom | 1st | weave interlace; Cauchy-dispersed glow halos (§12.2F) | audio never read (idle ≡ audio, 0.00 %) → `plasmaBuffer`; `%` fold fix (72 % of pixels); mouse-well scale; **new R5: camera rode the lattice axis (fully black at t = 6 s) → follows the gap** | **0.62 / 0.54** |
| gen-acoustic-obsidian-resonator | 1st | conchoidal scars; gold schiller + convex-edge wear (§12.2E SDF curvature) | black at silence (meanL 0.008 → 0.091) via Fresnel environment reflection; unguarded `normalize`; `fracture_scale` now live at silence | **1.68 / 1.65 — over the 1.3× cap, see below** |
| chromatic-reaction-diffusion-rgba | 2nd | isotropic 9-point Laplacian (§12.2D); photo-luma-scaled diffusion length | **HEAD solver unstable** (D·dt 0.66 vs 0.25 limit; both U layers flip 0/1 per pixel) confirmed in numpy + SwiftShader; the 9-point stencil is both the stability fix and the idea | 1.15 / – / – |
| gen-cymatic-hex-mandala | 1st | hex-symmetric m = 6 modal wave; Chladni sand in A.a | **the "hex" was a skewed parallelogram checker** → true hex lattice; filtering sampler on C → exact `textureLoad` | 1.01 / 1.02 / – |

Re-time method: coordinator, interleaved HEAD/new, min-of-drained frames, 6 rounds, median of per-round ratios, machine load 1.3–4.3 (three other agent sessions share it). Individual rounds still spread ±0.2–0.3; read each figure as ±0.1.

## What the deviations mean (read these before merging)

1. **Obsidian is 1.65–1.68× HEAD on SwiftShader — over the 1.3× cap.** Fork D measured 1.33–1.36× under load; the alone re-time says otherwise. Variant timing (each vs HEAD, 6 interleaved rounds): full 1.62, scars off 1.58, normal taps off 1.40, both off 1.57, **shading removed 1.22, shading + scars removed 1.30**. So ≈1.2–1.3× is march-side plumbing that is not the scar term (the `localFrame` refactor, `cell` floor, `dEnd`), ≈ +0.2 is the 4 normal taps, ≈ +0.3–0.4 is the extra shading. The scar term is within noise. Not trimmed in this PR; **a follow-up trim commit is planned** (fork D resumed). Treat the PR as draft until then.
2. **Loom default composition changes** (R5). HEAD's camera sat on the lattice axis and was inside / touching a thread 4–6 % of the time (fully black frame) and within 0.1 of one 30–44 % of the time. The camera now follows the centre of the warped gap channel, so the picture is a lattice seen from inside a gap, not a brown shaft. It is also ~0.55× the cost (the HEAD march burned its 64 steps hugging threads).
3. **Obsidian's silent frame is the biggest default-look change in the batch** (black → a lit glossy monolith field with environment reflection and gold sheen). Scars read as soft reflected undulations rather than crisp arcs. Miss pixels now write alpha 0 (HEAD wrote a bare 1.0).
4. **Flame changes its default look** (flat orange wall → structured flame; meanL 0.548 → 0.363). The fix narrows the trap ring (12 → 24) and centre glow (4.5 → 9) — the card said to keep HEAD's constants; a black point alone only reached stdL ≈ 0.05. Open: a straight `atan2` seam across the left half, from the polar/julia variations the card said to keep, is now visible against the higher contrast. Owner's call.
5. **`liquid` Snell refraction flips the sign of HEAD's thin lens**: refraction now follows Snell's law (a mound converges the photo). Fork A measured 12–27 % of pixels differing from HEAD, mostly that physical sign flip; the steep-slope nonlinearity alone is ≈ 0.1 % idle and ≈ 5 % held/with clicks. Magnitude is calibrated to HEAD. **Eyeball this on a real GPU.**
6. **RD changes its default look** (pixel noise → a stable warm/cool pattern; idle meanL/stdL 0.222/0.218 → 0.363/0.122). With U stable near 1 the untouched pigment formula reads as a lilac/purple wash. The display was not touched; owner's call. Pre-existing presets land on a different pattern scale (the Laplacian is ≈ 0.3·∇² now).
7. **Ambient sacrifices two corner pixels' sim state** to carry the pointer track (cyber-lens scheme, no clock stored because rgba16float cannot hold one). Also applied Beer to the top layer by its own column (`BEER_TOP` 0.4) to make Idea 1 visible at the default layer separation (the lower layer only carries a few percent of the mix there), which tints wave swells everywhere.
8. **Hex idle is still dim** (meanL 0.015 → 0.028) because the file keeps its premultiplied `col·alpha` convention (eight other `gen-*` files do the same). Left alone: a catalog-wide question. The 576 render shows a faint vertical seam below the centre and fine horizontal line texture inside some cells — not investigated.
9. **Viscous-drag smear is 0.0 % at idle by design** (`dragEnergy` ≈ 0.05–0.12 there); visible only under a held cursor, click or audio (2.6–5.9 %).
10. **Melt meander phase is shared across ≈5 columns**, so a seam between groups would show on a real photo; the melt ideas are strongest above the saved default Melt Speed.

## Floor checks (all ten)

- Saved `params` byte-exact against HEAD in all ten definitions (checked programmatically). Description growth ≤ +77 chars. `x-meta.upgrade.params` added additively to 5 definitions (ambient, liquid, loom, melt, hex); loom gained a `features` list, obsidian and hex gained `upgraded-rgba`; `spring-interaction` removed from ambient and liquid (false: the host wipes `extraBuffer[133..255]` each frame). No new schema keys beyond those.
- Bindings from `#include "_prelude.wgsl"` everywhere; `ambient-liquid-coupled` + `chromatic-reaction-diffusion-rgba` migrated header-only first (no `Upgraded:` bump for the migration) and removed from `src/contracts/prelude_migration.json` `pending`.
- A packing stated and consistent with how C is read: ambient / liquid / viscous-drag / RD raw (no ACES on stored fields); melt HDR + semantic alpha; flame + iris raw HDR display history, ACES on `writeTexture` only; loom + obsidian display RGBA (nothing reads C); hex A.rgb colour trail + A.a Chladni sand (HEAD stored an unused `bassEnv`).
- Exact `textureLoad` for history everywhere (hex was the one filtering-sampler-on-`rgba32float` offender); `pow(negative, 2.0)` replaced by squares in ambient, liquid, melt, iris.
- No spring / ripple / IQ-palette overlay added to any file that did not already own it. The only A-texel state is ambient's pointer track.

## §12.7 formula accounting (no row on more than one file)

Beer–Lambert (ambient) · Snell vector refraction + deep-water dispersion (liquid) · Cauchy dispersion (loom) · SDF curvature (obsidian) · isotropic 9-point Laplacian (RD). Everything else is native to its own file (colour-index averaging, hippus, contraction furrows, Marangoni, rivulet meander, meniscus lighting, strain smear, torn-film rim, conchoidal scars, schiller, weave, modal wave, Chladni sand). **Unused:** viscous-drag sub-pixel advection (measured, not worth it).

## Gates

| Gate | Result |
|---|---|
| `wgsl_precommit_gate.py --files` (ten) | pass 10/10 |
| `verify-naga-wasm.mjs --files` (ten) | 10 valid, 0 invalid |
| `audit:dead-sliders -- --files` (ten) | 0 new |
| `audit:extrabuffer` | pass |
| `upgrades:record -- --ids=<ten>` | see the commit; scoped (an unscoped run sweeps ~107 unrelated shaders) |
| `verify:shaders:fix`, `verify:toolchain-foundation`, `test:ci`, `npm run build` | see the PR description |

## Open items for the owner

1. **Obsidian cost 1.65× (over the cap)** — follow-up trim; do not merge before it, or accept it knowingly.
2. **Real-GPU look** at the default-look changes: obsidian, loom, flame (+ the `atan2` seam), liquid (refraction sign), RD (lilac wash), hex (dim idle; seam / line texture at 576).
3. Several ideas are pointer- or click-local and invisible at idle by design (ambient rim 0 % idle, viscous smear 0 % idle, liquid wake 0 % idle/held); they were measured with held cursor / injected ripples.
4. No unanchored review pass. Earlier batches' reviewers found 14 real defects in a ten-pack (batch-37); expect some here.
