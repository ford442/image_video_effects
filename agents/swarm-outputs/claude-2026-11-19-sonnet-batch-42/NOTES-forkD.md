# NOTES — fork D (gen-liquid-neon-topography, gen-nebula-light-trail-swarm)

## gen-liquid-neon-topography (second pass)
- KEEP VERBATIM: held — Ideas 1–4 untouched; Ideas line appended, Upgraded `2026-10-10, 2026-11-19`. A packing unchanged (ACES display RGBA, C read as colour history).
- **Rescue 1 (confirmed at HEAD):** image was upside-down — terrain filled the TOP of the frame, sky the bottom (uv.y from storage y-down vs world-up camera). Flipped uv.y in main(). HEAD/new idle meanL 0.381→0.396.
- **Idea 5 hypsometric tint bands (native)** — `// ── Idea 5` in the hit branch: stepped elevation tint per contour interval (teal low → magenta high), interval = the Idea 1 contour spacing so Contour Detail drives both. Visibility @192: 42.9 % px, meanΔ 0.019.
- **Idea 6 neon oil-slick thin film (§12.2 thin-film iridescence)** — on the pool (`reflCol`) and on wet valley floors (`wet = smoothstep(0.85,0.45,h/ridgeScale)`). The pool alone measured 0.0 % at defaults (pool level is almost never hit with Ridge Height 1) — so the film also coats the low ground; final 10.0 % px @192.
- 576 visibility measurement for idea 5/6 started but not read back (box load); 192 numbers only.
- frameMs ratio (perf.sh, 4 rounds, interleaved): 1.05 / 1.07 / 1.55 / 1.16 → median ≈1.11 (load-noisy).
- Gates: precommit pass, naga-wasm pass, dead-sliders AUDIT PASS, extrabuffer no finding. nan 0.
- Open: terrain is heavily speckled/aliased at 192 at HEAD and after (fbm ridges + 0.7 history); not touched. Per-slider sweep not run. Mouse Y is still inverted (cursor low → camera up), left as HEAD.

## gen-nebula-light-trail-swarm (second pass)
- KEEP VERBATIM: held (Strömgren + recombination). Upgraded `2026-09-14, 2026-11-19`. HEAD rendered correctly (no rescue). Pre-existing: C is read back post-ACES then ACES'd again (ACES→C→ACES), documented HEAD packing — not changed.
- **Idea 3 Airy diffraction rings (§12.2 Airy disc)** — per photon head, (2·J1(x)/x) with small-x/large-x J1 approximations; shown as |amplitude| (stretched exposure) so rings read. Glow Radius sets ring scale. Visibility @192: 27.8 % px, meanΔ 0.017 (first try at intensity² was 0.5 % → strengthened).
- **Idea 4 bow-shock arcs (native)** — parabolic shock front ahead of each head, H-alpha/[S II] colour, brightness ∝ valueNoise gas at the head, bass-boosted. 4.8 % px @192 (it is local to heads); clearly visible at 576.
- Both inside `if (hr < 0.25)` (no visual change, verified 0.0 % Δ).
- JSON: features + `airy-diffraction`, `bow-shock`.
- idle meanL 0.270→0.291, audio+held 0.437→0.454.
- frameMs: 0.93 / 1.44 / 1.60 / 1.13 → median ≈1.29 (very noisy, other forks running) — coordinator should re-time alone.
- Gates: precommit pass, naga-wasm pass, dead-sliders PASS. nan 0. No click-ripple render (harness has no injection).

### light-trail trim (after coordinator re-time 1.37×)
- Hoisted the per-pixel `gas` fBm above the particle loop; the bow shock now reads pixel `gas` instead of a 20× per-head valueNoise. Hoisted the Airy scale out of the loop. Near-head gate is now `dot(hv,hv) < 0.0256` (r 0.16, Airy fade radius shrunk to match) before any sqrt.
- Visibility @192 after trim: Idea 3 17.8 % px (was 27.8), Idea 4 4.7 % (local to heads). nan 0, idle meanL 0.285.
- perf.sh rounds: 0.95, 1.01, 1.02, 1.12 → median ≈1.01. precommit + naga-wasm pass.
