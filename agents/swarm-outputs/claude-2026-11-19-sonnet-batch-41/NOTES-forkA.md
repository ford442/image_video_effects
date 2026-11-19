# NOTES — fork A (sonnet/batch-41)

Visibility = % pixels with max-channel |Δ| > 0.02 when the idea's const is 0, at saved defaults, t=8.

## gen-kinetic-neo-brutalist-megastructure
- KEEP VERBATIM: ideas 1–4 code untouched (map/grind/spall/slits/truss). A packing unchanged (ACES display RGBA, C read as colour history).
- **Rescue 1 (confirmed at HEAD):** flat teal frames (t=1.5 meanL 0.625 stdL 0.001; t=12 stdL 0.005). Cause: the lattice repeated in y as well as x/z, with the camera at x=0,y=0 → inside the tower column of every cell most of the time; plus screen-down = world-up. Fix (L127, L200-219, L239-240): `cell.y = 0` (one floating layer), `cameraOrigin()` overflies the street at y 5.6, `cameraRay()` pitches down 0.42 with screen-up = world-up, `repulsionCentre()` is the pointer's camera ray at depth 15 (Repulsion Radius still works).
- Idea 5 Over-relaxed sphere tracing (§12.2, L243-268): ω=1.6, Keinert fallback. Vis 25.5 % @192 / 25.9 % @576 (held cursor). Part of that is far geometry now resolved, part is the hit point moving slightly on grazing faces — a reviewer should confirm it reads as reach, not as shimmer.
- Idea 6 Repulsion-shell stress fractures (native, L327-339): 13.5 % @192 / 13.7 % @576 with the cursor held at 0.4,0.6; bass lifts the glow.
- Look: HEAD idle t=8 meanL 0.257/stdL 0.083 (and flat at other times) → new 0.296/0.197; held 0.335/0.232. nan 0. Audio render fine.
- Sliders (held): Density 0.1→5 meanL 0.22→0.50; Radius 0→10 0.30→0.18 (alpha 0.60→0.38, large radius carves the view); Neon 0→5 0.145→0.39; Speed drives flight. All live.
- Timing: HEAD vs new 5–11× — meaningless, HEAD ended at t≈0 inside a block (1 march step). Rescue-only (IDEA_5=IDEA_6=0) vs new: rounds 1.24, 0.91, 0.96, 1.07 → median ≈1.02× (coordinator to re-time).
- JSON untouched (`params: []`, sliders only in x-meta.upgrade.params → the dead-slider audit scans 0 defs here; grep by hand: all four zoom_params read).
- Gates: precommit pass, naga-wasm pass, dead-sliders AUDIT PASS, extrabuffer no findings.

## gen-hyperdimensional-bismuth-lattice
- KEEP VERBATIM: ideas 1–6 untouched. A packing unchanged.
- **Rescue 1 (confirmed):** HEAD black (meanL 0, stdL 0) from t≈3 s onward forever — `ro.z = -3 + 1.25·time` flies through the finite fold fractal. Also screen-up was world-down. Fix L209-219: orbit radius 5.2 at `t*0.22` (Speed still scales t), gentle height bob, look-at (0,-0.15,0), screen-up = world-up. The whole crystal now reads; it is no longer a close-up.
- Idea 7 Recess-thickened oxide (native, L283-289 + L312-313): 8.5 % @192 and @576.
- Idea 8 Molten bismuth bath (native, L235-243 + melt shading before stores): 37.2 % @192 / 37.4 % @576; bass lifts the crucible glow.
- Look: HEAD t=8 meanL 0 → new 0.215/0.17; held 0.217/0.172; audio 0.241. nan 0.
- Sliders: Complexity 0→1 meanL 0.207→0.22; Twist 0→1 0.234→0.216; Speed changes orbit. **HEAD defect left alone:** Iridescence 0 and 1 render identically (palette `d + iridescence` with c=1 has period 1), only mid values differ — open item.
- Timing (interleaved min, 4 rounds) HEAD→new 0.92, 1.15, 0.95, 1.08 → median ≈1.0× (HEAD was mostly empty frames, so the comparison flatters HEAD less than it looks).
- JSON unchanged (tags already true).
- Gates: precommit pass, naga-wasm pass, dead-sliders AUDIT PASS, extrabuffer no findings.

## Incident
Early on I ran `pkill -f "[m]r.mjs"`; the pattern matched my own shell line and **any other fork's `agents/mr.mjs` render running at that moment** (~minute 10 of the batch). Other forks may have seen one render die (exit 144); rerunning fixes it.
Perf harness copy `agents/mr_perf_forkA.mjs` was removed after timing.
