# sonnet/batch-22 — fork B notes (forge, scarab, kryonic core)

Gates (all 3): `wgsl_precommit_gate.py --files …` 3/3 naga OK; `npm run audit:extrabuffer` PASS (0 violations); `npm run audit:dead-sliders -- --files …` 0 new (note: only the forge has top-level `params`; scarab/kryonic have x-meta only so the audit scanned 1 def — all four `zoom_params.xyzw` grepped by hand in each file and are read). Renders: 192 px sweeps over t, 576 px idle + (cursor 0.8,0.3 pressed, audio 0.4/0.3/0.2) — no NaN anywhere. Not touched: JSON, generated lists, ledger, commits (coordinator). No JSON edits are needed: features tags already match (audio-reactive via plasmaBuffer[0], mouse-driven via zoom_config). Real-GPU visual QA: external.

Formula names: forge — §12.2E fold count as material (R2 rescue, revives HEAD idea 1); kryonic — §12.2E fold count as material (idea 3) + §12.2E SDF curvature (idea 4); scarab — §12.2E SDF curvature (idea 4). Row totals in my fork: fold count 2 files, SDF curvature 2 files. No orbit trap, no over-relaxed tracing.

JSON caveat for the coordinator: scarab and kryonic JSON have no top-level `params`; the app feeds 0.5 x4 (authored x-meta defaults 4/1.5/0.8/2.0 and 1.5/0.5/1.0/0.2 are never what users see). Not changed per COMMON.md. Kryonic R1 below is the in-shader fix for the one value (0.5 scale) that was outright invalid.

---

## gen-radiant-quantum-crystalline-forge  (`Upgraded: 2026-09-27, 2026-11-08`)

KEPT VERBATIM: 4 params + roles; KIFS loop constants (offset, 1.8 scale, rotations), `d=(length(p)-1)/scale`, seam metric, iridescent baseCol, blackbody ramp, weld palette, cleavage glint, fog accumulation, alpha/depth, ACES, hit/miss semantics. A PACKING: ACES display RGBA (unchanged).

RESCUES
- R1 (fly-through blank forever): `ro.z = -8 + 2t` → inside the solid t≈3.5–4.7 (flat beige), past it from t≈5 for ever (HEAD t=5,6,8,12,30: meanL 0.065, stdL 0, meanA 0). Now z = -mix(max(7·density, 0.8), 8, 0.5+0.5cos(0.5t)): identical to HEAD at t=0, breathes with period 12.6 s, stand-off scales with the density slider (blob radius ≈ 3.5·density). Diff: `ro` block (~l.147). Default-look change: YES for t>0 (HEAD was an infinite flight into blankness). t=0 render identical (meanL 0.149 vs 0.146, stdL 0.224 vs 0.214).
- R2 (dead twin facets, §12.2E fold count): `twin = f32(i & 1)` was reassigned every pass → always 1.0 → twin tint never split. Now reflection-parity of the loop (mapSDF l.~40). Debug render: ~50/50 orange/blue per bead, no per-pixel noise. Default-look change: yes, modest (HEAD tinted everything warm; now half the beads are cool).

IDEAS IN THE DIFF
- Idea 5 hammer-strike heat front with cooling tail (not a §12.2 row): `Strike` struct + `strikeSetup`/`strikeHeat` (l.83–118), applied in the fog loop (l.~175, seam fog) and at the hit (l.~209, weld glow + `weldHeat` blackbody). Strike point on the camera-facing side, new blow every 4.5 s, gaussian shell + 0.3 cooling tail, envelope fades before the next blow. Bass/treble untouched; no new param. Per-blow constants are built once per pixel.
- Idea 6 albite twin flash: l.~216 — half-vector tilted ±0.24·cross(n, dominant axis) by the live twin parity, `pow(…, 64)` flash × twinTint, treble-weighted like the existing spec. Visible only because R2 made the parity real.

Open items: default view at 576 px is cream/pearl beads — the weld gold is near-uniform (g_seam ≈ 0.01 everywhere at the finest generation; left alone as identity), so the twin tint split and the flash are subtle at chroma=1. Strike flare is a soft bloom, not a crisp ring. World orientation not touched (light from below, symmetric mass). Timing (noisy, 4 interleaved rounds, 192 px, t=0): HEAD 80/65/48/69 ms vs new 73/69/75/96 (before precomputing the strike constants; the render is bit-identical after).

---

## gen-resonant-quantum-obsidian-scarab-engine  (`Upgraded: 2026-09-27, 2026-11-08`)

KEPT VERBATIM: 4 slider roles; torus core (pulse), 4-iteration KIFS with its in-place x/y shear (replayed in `scarabPlates`), `smin(…,0.5)`, plate seams + breath wave, plasma mirror, corona, core offset `(2mx, 2my)`, 5% temporal feedback, chromatic aberration, dust, ACES. A PACKING: ACES display RGBA (unchanged; C read as colour at 5%).

RESCUE
- R1 (upside-down camera, inverted pointer): `rd = (uv.x, -uv.y, 1)` (l.~149). HEAD: pointer y=0.1 → core low, y=0.9 → core top; key light from below. Now pointer y=0.1 → core high, 0.9 → low, x unchanged (checked with 3 renders), light from above. Default-look change: YES — idle cursor puts the core at lower-right instead of upper-right; carapace mirrored vertically. Statistics are nearly identical (meanL 0.051–0.078, stdL 0.09–0.116 before and after).
- Not a bug: "dim" (meanL ≈ 0.07) is the obsidian by design (`0.1·dif` base, plasmaIntensity 0.5 at the app's 0.5 fed value). Left alone.

IDEAS IN THE DIFF
- IDEA 4 joint fluid (§12.2E SDF curvature): `mapCurv` (l.~121, 7 map taps at the hit only, e=0.04) and the block at l.~195: concave valleys (κ<0, `smoothstep(1.5,8,-κ)`) go 75% darker, carry a tight wet cyan highlight and mirror the core 2.5x harder. Debug κ render confirmed valleys vs convex crowns. Subtle at 192 px, visible at ≥384 px as thin cyan lines in the valleys.
- IDEA 5 carapace flex: `shellFlex(pulse)` l.37–41; `map()` shares the single `sin(time·rate)` already used for the torus (hoisted, no extra transcendental); `scarabPlates` replays the same factor so seams stay on the shell. Measured effect at the breath extremes: 8% flex changes 13–21% of pixels by >24/255 vs flex 0.

Open items: curvature adds 7 maps per hit pixel — measured +10–35% frame time under concurrent load (HEAD 50–54 ms vs new 56–73 ms, 4 interleaved rounds, noisy); worth one real-GPU timing. The core is still not centred on the pointer (HEAD's `2·mouse` offset, kept). At the app's 0.5 complexity the carapace is a stack of layered bands rather than beads (HEAD geometry).

---

## gen-kryonic-quantum-aether-fractal-core  (`Upgraded: 2026-09-13, 2026-11-08`)

KEPT VERBATIM: 4 slider roles; `fold()` + 5-iteration loop + `length(q)/scale_factor - 0.02` DE; shatter noise; `smin` melt sphere under the pointer; mouse orbit; frost-rime orbit trap and shatter veins (and their constants); display chain; A = display RGBA.

RESCUES
- R1 (scale < 1 collapses the fractal): `s = (1 + scale)·(1 + 0.1·audio)` in `map` and `foldTraps` (l.61, l.98). The fed 0.5 gave a contracting fold (DE inflated 32x): HEAD default = smooth cyan disc + hairlines. Now the fed 0.5 gives the authored 1.5 fractal (rosette with rime beads). MAPPING CHANGE for the coordinator: authored range [0.5,5] now means expansion [1.5,6]; the value 1.5 someone might have saved would now render as s=2.5. JSON untouched; no UI slider exists for it (no top-level params).
- R2 (rim term inverted): `(1 - n.z)` → `(1 - max(dot(n, -rd), 0))` (l.~221). HEAD gave camera-facing surfaces the maximum cyan (x2) → whole picture a pale cyan wash (meanL 0.75, stdL 0.07 at s=1.5). Default-look change: YES, large — faces go deep blue, cyan only at grazing angles.
- (Glow re-weighting by step length was tried and discarded: no measurable effect.)
- Default look at idle cursor (centre): meanL 0.52 → 0.57–0.61, stdL 0.24 → 0.13 (HEAD's std was the disc edge vs dark corners, not structure); the picture is now a fractal.

IDEAS IN THE DIFF
- Idea 3 fold-count ice grade (§12.2E fold count as material): `foldCounted` (l.23–33, same geometry as `fold`, counts abs flips + 3 swaps), `foldTraps` returns it as `.z` (l.~87–112), block at l.~239: few folds = clear glacial ice (deeper blue, tight spec ×2.5), many = snow-ice (matte pale mix). Thresholds from measured distribution (p10 18.8 / p50 21.8 / p98 23.6).
- Idea 4 ridge translucency (§12.2E SDF curvature): `mapCurv` (l.138–146, 7 taps at the hit, e=0.01), block l.~248: convex ridges (κ>40..160) emit warm cyan, back-lit by the core at the origin (`dot(n, normalize(p))`). ~14% of pixels change.
- Idea 5 meltwater sheen (tactic 3, smin blend weight promoted): block l.~255 — `hBlend` from one extra pure-fractal `map` (melt=0) vs `length(p)-(1+melt)`; wet = h² only inside the hover melt zone; darker water + tight highlight. ~9% of pixels at idle cursor; zero when melt = 0.

Open items: idle-cursor melt cavity sits mid-frame by design (see BRIEFS revision). Cost: +8 maps per hit pixel; measured under concurrent load rescue-only 136–273 ms vs new 165–307 ms (min-of-4 +21%); the rescue itself raises cost vs HEAD (HEAD marched a collapsed DE). Ice grade is strong (about half the pixels change) — if it reads milky on a real GPU, lower the 0.35 snow mix at l.~244.
