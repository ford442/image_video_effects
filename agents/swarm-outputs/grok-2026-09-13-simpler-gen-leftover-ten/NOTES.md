# NOTES — Grok-1 simpler generative leftover (10) — 2026-09-13

No WGSL or JSON diffs. The supplied list was already idea-complete. This file
exists so a coordinator can see what was *checked*, not what was *added*.

## Per shader

### gen-fireworks-nocturne
- Kept verbatim: 9 staggered mortars, energy/tempo/density/color-drift, mouse command.
- A packing: ACES display RGBA (C is previous display). Matches.
- Ideas in the diff: **n/a — no diff.** Pointable in file: muzzle at `launchPos`; even/odd round vs droop.
- JSON: `upgraded-rgba` already present.

### gen-fireworks-ring-shell
- Kept verbatim: ringR / thick / count / colorC; ring spark loop.
- A packing: ACES display RGBA. Matches.
- Ideas in file: Saturn tilt (`tilt = 0.48` ellipse); empty core (`onHalo` / `coreR`).
- Header uses compact `// Ideas:` (not the 7-line banner). Still a real dated card (2026-09-10).

### gen-fireworks-roman-candle
- Kept verbatim: tubes, fireRate, held mouse, click-ripple personal candles.
- A packing: ACES display RGBA. Matches.
- Ideas in file: muzzle glow at `(tubeX, tubeY)`; `seq` into `starCol`.
- Click ripples kept; no extraBuffer spring.

### gen-fireworks-smoke-bloom
- Kept verbatim: smokePuff, bloom, burstEnergy, trailDecay.
- A packing: ACES display RGBA. Matches.
- Ideas in file: `// Idea 1 — buoyancy`; burst-lit puff from local flash.

### gen-fireworks-strobe-shell
- Kept verbatim: `strobePulse`, afterglow slider as trail mix.
- A packing: ACES display RGBA. Matches.
- Ideas in file: per-spark phase (`js * TAU`); pulse can hit 0.

### gen-fireworks-willow-cascade
- Kept verbatim: willowPos, 5-sample trail, windAmt.
- A packing: ACES display RGBA. Matches.
- Ideas in file: terminal hang in `willowPos`; leeward lean from wind.

### gen-fireworks-wind-ripple
- Kept verbatim: sparkPosWind, click-ripple barrages, zoom_params.x dual role.
- A packing: ACES display RGBA. Matches.
- Ideas in file: `altitudeShear`; leeward streak `dot(uv-sp, windDir)`.

### gen-fluffy-raincloud (`gen_fluffy_raincloud.wgsl`)
- Kept verbatim: coverage / turbulence / rain / wind; vorticity solver.
- A packing: raw density, velocity.xy, moisture — **not** ACES in A. Matches C reads.
- Ideas in file: anvil deck; virga fade before ground.

### gen-fourier-epicycles
- Kept verbatim: radius∝1/n wheels; trail pack.
- A packing: bassEnv, trail.r, trail.g, alpha. Matches.
- Ideas in file: `// Idea 1 — arm segment from hub to next hub`; `// Idea 2 — pen ink`.

### gen-grid (`gen_grid.wgsl`)
- Kept verbatim: warp / density / thickness / palette; existing spring well + click warp.
- A packing: ACES display RGBA. Matches.
- Ideas in file: warp Jacobian anisotropic H/V; intersection phosphor from exact C.
- Existing pointer spring kept (already native). No new spring.

## Gates

Not re-run (zero file edits). Prior batches already gated these IDs (Naga + extraBuffer + dead sliders). Catalog IDs exist; `gen-grid` / `gen-fluffy-raincloud` are underscore-backed URLs.
