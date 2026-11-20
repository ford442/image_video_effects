# NOTES fork E — cosmic-flow, gen-raptor-mini-flow (both first pass)

Measured on SwiftShader (`agents/mr.mjs`, synthetic image + depth, 320² unless stated). **No real-GPU visual QA.** HEAD = origin/main 673d780a (+ coordinator's header-only prelude migration of raptor).

## cosmic-flow (`public/shaders/cosmic-flow.wgsl`, `shader_definitions/artistic/cosmic-flow.json`)
- **ADD**
  1. Dust lanes with 1/λ reddening — Beer–Lambert (§12.2F): `τ = 0.95·|cos(phase·1.7 − flowTime·3.1)|⁷·smoothstep(0.30,0.65,field)`, `T = exp(−τ·(0.85,1,1.22))`; multiplies source + stars fully, nebula emission ×½ (`mix(1, T, 0.5)`); `(1−T.g)·0.2` into alpha. `// ── Idea 1` at the `density` line.
  2. Point-spread stars with Airy core + 4-point diffraction spikes (§12.2F Airy): jittered centre per cell, `airyCore(r·14)` (Taylor J1 clamped/faded at the first zero 3.83), cross spikes (longer on the rare `bigStar` seeds), cell-edge fade; composited AFTER the history blend and attenuated by `dustT`. `// ── Idea 2` at the star block + final `writeTexture`.
- **KEEP VERBATIM**: fbm/curl/q/r/field, braidA/B/filament/knots/density, `cosinePalette` + `color_shift`, 4 param roles, depth-curl chromatic taps, pointer lens, click vortices, `historyOffset`/`historyWeight` blend, ACES, alpha structure, star cell size / seed gate / treble gate / twinkle exponent / `(0.5+filament)`.
- **A packing**: HDR pre-tonemap RGB + semantic alpha (unchanged). **Change to say out loud:** the star layer is no longer stored in A (HEAD stored it, then advected it into smears); `writeTexture = ACES(live + starLight)`, `A = min(live, 8)`.
- **Rescues**: R1 twinkle phase/rate from an independent hash (HEAD: all stars in unison, dark ~85 % of the cycle). R2 star-grid curl warp 0.025 → 0.007 (needed for a point profile; documented under Idea 2).
- **Diff vs HEAD** (20 frames, t = 4, SRC=img): defaults 26.7 % px >12/255 (48.5 % >4/255), mean luma 0.648 → 0.622; hi-params + mouse + audio 29.3 % / 56.2 %. The lanes are the bulk; stars are sub-percent of pixels. NaN 0.
- **Timing** (5 interleaved rounds, 40 frames, min-of-drained / p25 / median of per-round ratios): **0.96× / 1.06× / 1.08×** — no trim needed (+1 hash, 2 exps, 1 pow, 1 cos).
- **Gates**: precommit 1/1, naga-wasm 1/1, dead-sliders PASS (all 4 sliders read by hand too), extraBuffer PASS.
- **Not verified**: real-GPU look; star spikes at ≥1080p (SwiftShader check at 960² only; spikes are 2–3 px at ~11 px cells); dust-lane strength vs the user's photos.

## gen-raptor-mini-flow (`public/shaders/gen-raptor-mini-flow.wgsl`, `shader_definitions/advanced-hybrid/gen-raptor-mini-flow.json`)
- **ADD**
  1. Streamlined body — structure-tensor orientation → anisotropic kernel (§12.2A): body SDF in the heading frame `hFrame = (f·h, f·h⊥)`, `length(hFrame.x/s, hFrame.y·s) − r` with `s = min(1 + 0.8·coherency, max(1, 0.48/r))` (area-preserving, never exceeds its cell). `// ── Idea 1`.
  2. Pursuit wake — soft inverse-square (§12.2F): in the trail branch, `rise·taper·exp(−y²/(w²+0.002))/(1+(a/a0)²)` with `a = max(−hFrame.x, 0)`, length `(0.12+0.26·maxSpeed)·(1+0.6·coherency)` beyond the rear (cap 0.49 cell), tint `0.7·flowHue + 0.3`, lifted by `rage`; also feeds alpha. `// ── Idea 2`.
- **KEEP VERBATIM**: structure tensor + 3×3 smoothing, `coherency`, 4 param roles, `dir` blend, lattice `st = uv·20`, `rng`, `bodyRadius` + rage growth, scale-ring texture, flow-angle hue, green glow / dark trail background, depth passthrough.
- **A packing**: ACES display RGBA (HEAD wrote no A; C is never read — A written for the contract).
- **Rescues** (open decisions for the user marked ★): ★R1 raptors travelled **away** from the cursor / along −dir (cross-correlation: dx = −3 px at HEAD with the mouse to the right; **+3 px after**, predicted 3.2) — flipped `st += dir·…` to `st −= dir·…`. R2 dominant eigenvector via `½·atan2(2Jxy, Jxx−Jyy)`: identical to HEAD where defined (20 000 random tensors, 0 mismatches), no `normalize(0)` where `Jxy = 0, Jxx < Jyy`. R3 `safeNorm` on `normalize(mouse−uv)` / `normalize(uv)` (the exact centre pixel has `uv = 0`). R2/R3 are **not reproducible on SwiftShader** (it returns finite for `normalize(0)`; NaN 0 at HEAD) — fixed defensively. R4 floor: ACES display RGB, A written, alpha kept as coverage. ★ACES brightens the mids (mean luma at t = 0, defaults: 0.151 → 0.187; glow green 0.4 → 0.54) — HEAD authored in LDR, so this is a look change from the floor, not from the ideas.
- **Diff vs HEAD**: t = 0 defaults 67.8 % px >12/255 (94.2 % >4/255) — mostly the ACES lift + the wake halo; t = 4 defaults 79.8 % (motion reversed, so the lattice differs); hi params 98.5 %. NaN 0.
- **Timing** (5 rounds): **1.04× / 1.07× / 1.05×** (the 108-sample tensor dominates).
- **Gates**: precommit 1/1, naga-wasm 1/1, dead-sliders PASS (turn, speed, rage, flow all read), extraBuffer PASS.
- **Not verified**: real-GPU look; the wake is only a few px long at ≤ 480 px (cells are 1/20 of the height), clearly visible only on large renders; behaviour on drivers where `normalize(0)` is NaN.
