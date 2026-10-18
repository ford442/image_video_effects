# Fireworks ten — notes (2026-10-10)

Cards: `BRIEFS.md`. Every file was migrated from a pasted binding header to `#include "_prelude.wgsl"` first (header-only, not counted). Saved `params` and `updatedParams` are byte-identical; each definition's `description` gained one sentence naming the new ideas. A packing is ACES display RGBA in all ten (C is read back as colour history, unchanged from HEAD).

| Shader | Kept verbatim | New ideas in the diff (grep) |
|---|---|---|
| gen-fireworks-fan-shell | drag `sparkPos`, shell wind, flutter, peacock eye, palmette, mouse fan | `unfoldSweep` (per-ray ignition delay, direction alternates per shell); `guardRib` (outermost rays, gold 6-sample streak, low drag) |
| gen-fireworks-horse-tail | `tailPos`, brocade pinch, tip spark-out, silver dust, mouse cascade | `tailSwish` (wave down each streamer, ∝ tf²); `dockKnot` (slow gold knot at the burst, scaled by Gold Intensity) |
| gen-fireworks-kamuro-gold | `kamuroPos` plateau, per-glitter twinkle, HDR core, haze, split-tone | `drossFission` (3 satellites at twinkle peaks); `charcoalCool` (post-plateau blackbody fade + shrink) |
| gen-fireworks-nocturne | jewel palette, muzzle flash, round/droop habits, crackle, embers, mouse shell | `aerialDepth` (per-shell scale, dim, haze tint on sparks + embers); `colorChange` (hue jump + brief white flash at a per-shell age) |
| gen-fireworks-ring-shell | Saturn tilt 0.48, empty-core gate, secondary halo, mouse halo | `ringRoll` (per-shell rotation of the tilted ellipse); `farSide` (back half dimmer/smaller, less depth heat) |
| gen-fireworks-roman-candle | tube cadence, colour sequence, muzzle flash, apex burst, held + click candles | `fountain` (gold comp spray between shots during the firing window); `gutter` (late flicker + shrink) |
| gen-fireworks-smoke-bloom | `smokePuff`, buoyancy, burst-lit smoke, secondaries, C bloom | `vortexRing` (puff hollows into side-on torus); `extinction` (shell sparks dimmed/reddened by their puff) |
| gen-fireworks-strobe-shell | `strobePulse`, per-spark phase, embers, mouse strobe | `strobeDots` (dots at the last 3 flash peaks); `skyStrobe` (wide pulse-lit veil) |
| gen-fireworks-willow-cascade | `willowPos` terminal hang, leeward lean, streaks, advected C trails | `willowTrunk` (lingering gold ascent column, follows lean); `tipDrip` (beads detach after hang and fall faster) |
| gen-fireworks-wind-ripple | altitude shear, leeward streaks, comet lines, ripple barrages, advected C trails | `gustBand` (travelling gust multiplier on shell wind); `shockRefract` (ripple fronts displace the sampled uv) |

Nocturne card changed before editing: the river reflection was dropped because the launch line (`y = -0.82`) is off screen.

Observation, not changed: in all ten, mortar launch Y (≈ -0.78 to -0.82) sits outside the ±0.5 visible band and burst centres sit near the edge. That is HEAD behaviour across the fireworks family; check framing on a real GPU.

Gates: Naga 10/10 (`wgsl_precommit_gate.py`), `audit:extrabuffer` PASS, `audit:dead-sliders` 0 new, catalogs regenerated, Jest 133/133 suites, `SKIP_WASM_BUILD=1 npm run build` OK. No real-GPU look check.
