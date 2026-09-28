# Chaos / chem generative ten — notes

Cards were written in `BRIEFS.md` before WGSL. Saved `params` were not edited. No new springs.

## Second pass (prior ideas kept)

- **gen-3d-sierpinski-chaos** — kept attractor die, corner flares, iteration-age hue, opposite-face chroma. Added midpoint cavity and edge filament in the hit shade. A stays ACES display RGBA.
- **gen-belousov-zhabotinsky** — kept refractory tail and pacemaker gradient. Added phase hue and annihilation cusp on the display color only. A stays raw `(newA, newB, waveFront, alpha)`. B detail unchanged.
- **gen-buddhabrot-aura** — kept Nebulabrot channels and anti-Buddhabrot dust. Added running min-distance spine and `atan2(z)` escape tint. A stays ACES display RGBA.
- **gen-cellular-automata-tapestry** — kept kill-rate isochrones and anisotropy. Added spot nucleus (`lapB < 0`) and depleted-A halo on the display. A stays raw `(nextA, nextB, 0, 1)`. Dropped the mix of `C.rgb` into the picture (C is chemical state) and the `plasmaBuffer[1..255]` LUT. `u.config.y` is no longer dt.
- **gen-chromatic-acid-drip** — kept coffee-ring meniscus and gravity-biased fall. Added a neck above each blob and a down-gravity lag of R ahead of B ahead of G. A stays HDR; ACES only on `writeTexture`.

## First card

- **gen-alpha-aurora** — curtain rays from the curl’s vertical component; greener hem on the bottom of each Gaussian. Bass envelope moved from `extraBuffer[0]` to `[133]`. A is pre-ACES display.
- **gen-bioelectric-pulse** — trailing half of each sine ring darkened; rising half cyan, falling half magenta. `dataTextureC` is `textureLoad`. A stores the unmapped trail. Kick envelope stays at `[133..134]`.
- **gen-brutalist-monument** — board-form lines and tie holes on concrete only; vertical stains stronger when the sun is high. New display store in A. No spring.
- **gen-alien-flora-ecosystem** — species 1 stains the cap (mat 3), species 2 the stem (mat 2); toxin ring at the cell edge. Not the gill/spore ideas from `gen-alien-flora`. New display store in A. No spring.
- **gen-chronos-labyrinth** — nosing lip on staircase treads; second `structureDist` sample at `shift_time - 0.28`, biased outward by 0.06. Existing spring and rift-echo packing kept.

## Gates

Naga 10/10. Precommit gate 10/10. extraBuffer audit: 0 new violations. Dead sliders: 0 on these ten. Catalog 1,373. Jest: 741 passed, 6 failed, 1 skipped. The 6 failures are `Cannot find module './bridge/api.js'` from `src/wasm/wasm_bridge.ts` (pre-existing). `SKIP_WASM_BUILD=1 npm run build` compiled. Real-GPU visual QA was not run.
