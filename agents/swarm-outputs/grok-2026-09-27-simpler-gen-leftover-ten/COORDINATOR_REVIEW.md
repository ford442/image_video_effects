# Coordinator Review — Grok simpler generative leftover (10) (2026-09-27)

Second-pass on a stale leftover list. User overrode skip-if-idea-rich. Cards in BRIEFS.md written before WGSL.

## Per file

- [x] gen-rainbow-firefly-dance — Photinus duty cycle + courtship antiphase pointable. Params added, not stolen. HDR A kept.
- [x] gen-rainbow-icosahedron-cascade — dual centroids + click pulse. Header A packing honest. `target` renamed `shellReach` (naga reserved).
- [x] gen-rainbow-smoke — vortex rings additive to radial burst; KH billows. Spring [133..136] kept. Raw A kept.
- [x] gen-orb — Lyapunov stretch + Poincaré flashes. No extra streams. Display A kept.
- [x] gen-newton-fractal — flow striations + wandering dust. A.a pack unchanged.
- [x] gen-percolation-threshold — red-bonds + mass fade. Lattice pack unchanged. No extraBuffer revival.
- [x] gen-neon-snowfall — graupel + snowbank. [133] bass_env kept.
- [x] gen-neon-lotus — nyctinasty + peltate pad. No fake C.
- [x] gen-kimi-crystal — 46° halo + pillars. 22° halo kept.
- [x] gen-kimi-nebula — PDR + EGGs. Stromgren/dust kept.

## Checklist

- [x] Idea Card exists and was written before the diff
- [x] Each numbered idea is pointable in the WGSL
- [x] KEEP VERBATIM still holds
- [x] Diff is not ≥70% header / ACES / spring / ripple boilerplate
- [x] No generic overlay shared across the batch
- [x] A packing matches how C is read
- [x] Saved `params` unchanged (firefly: params added to match existing updatedParams)
- [x] Springs/ripples only if native (existing smoke spring and snowfall bass_env kept; no new springs)
- [x] Naga + extraBuffer + dead sliders on this file

## Failures

None structural. Icosa first naga fail (`target` reserved) fixed before closeout.

## Visual QA

Cloud VM has no GPU. Real-GPU visual QA remains external. Do not claim the ideas look right from here.

## Structural gates

- Naga 10/10, precommit 10/10
- extraBuffer: 0 new [0..132] writes
- dead sliders: 0 on all 10 definition stems (including underscore aliases)
- catalog: 1386 unique definition IDs, unified 1373, generative 478
- Jest: 741 pass / 6 fail (pre-existing WASM `bridge/api.js`)
- SKIP_WASM_BUILD=1 production build: green

