# gen-raptor-mini — Interactivist upgrade notes (batch 35, tracker #320)

**Files:** `public/shaders/gen-raptor-mini.wgsl` (184 → 249 lines, +65),
`shader_definitions/generative/gen-raptor-mini.json` (additive `features` only; `updatedParams` byte-exact).

## What changed

1. **Sprung mouse pack-leader (mouse ×3 params).** Raw pointer now feeds a
   critically-damped spring (persistent state in `extraBuffer[133..138]`, single-writer
   guard `gid==(0,0)` + `arrayLength>138u`, init flag + dt clamp). The smoothed cursor
   drives: (a) pursuit target direction, (b) scent/trail decay center, (c) velocity
   magnitude `velMag` which boosts turn agility (`turnBoost`) and chase intensity —
   fast flicks whip the pack around.
2. **Real audio, all three bands + guarded FFT.** Was bass-only. Now bass→rage (kept),
   mids→spring stiffness + RD feed rate + scroll speed (morph speed), treble→claw
   sparkle detail on the body. Guarded FFT bins 1/7 (`arrayLength>13u`) split color:
   low bin warms territorial red, high bin cools energy blue. No hash-based spectrum.
3. **Click strike shockwaves.** Guarded ripple loop (`min(u32(u.config.y),50u)`),
   finite age window 0–1.6 s, spatially local expanding rings, non-negative; plus a
   held-press pounce glow local to the cursor. Strikes inject into territorial
   intensity/energy AND wipe local scent-memory (see below).
4. **Emergent scent-memory feedback.** `dataTextureA` now written every frame (was
   missing entirely); previous frame read via `textureLoad(dataTextureC)`. Trail
   persistence = f(rage, pointer velocity, outside-body zone, strike reset) —
   nonlinear and history-dependent: fast mouse + heavy bass leave long ghost trails
   that decay per-channel (0.965/0.94/0.92), clicks locally erase them.
5. **Generated relief depth.** Replaced the copied `readDepthTexture` passthrough
   (contract violation) with real relief: capsule body near=1, territory boundary
   mid, open field far=0, strikes lift locally.
6. **Semantic alpha.** `reproCooldown + strike + persistence`, clamped [0.05, 0.95].

## Slider contract (all 4 stay live, index order via `u.zoom_params.xyzw`)

- x Turn Speed → dir blend base (now augmented by velocity boost)
- y Max Speed → pursuit vector + scroll rate
- z Rage Duration → body scale texture frequency (kept)
- w Glow Radius → outside-body glow falloff (kept)

## Gate

`python3 scripts/wgsl_precommit_gate.py --files …` → **PASS** (naga OK, bindgroup
compatible, no extraBuffer violations). JSON `json.load` OK.

## Perf estimate

Same core cost as before (voronoi 3×3 + 2 fbm-heavy RD evals). Added: 1 textureLoad,
1 hash for sparkle, ≤50-iteration ripple loop (early-out on age), spring math O(1).
≈ +5–8% per-pixel cost. No new loops of unbounded size.
