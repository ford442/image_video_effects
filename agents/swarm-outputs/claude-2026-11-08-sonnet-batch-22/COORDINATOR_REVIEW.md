# sonnet/batch-22 — coordinator review (glass creature & relic ten, second pass)

Base origin/main a3ccd30a. Commit 1 = header-only prelude swap for 4 files (no `Upgraded:` bump). Commit 2 = ideas/rescues/JSON/lists/ledger/notes.
Gates: precommit gate 10/10, `audit:extrabuffer` PASS, `audit:dead-sliders` 0 new (6 definitions scanned; the rest have x-meta only — sliders grepped by hand by the forks), Vitest 202 files / 1805 passed (1 skipped), `npm run build` OK, `verify:toolchain-foundation` 11/13.
The 2 failing gates are PRE-EXISTING on origin/main and not touched by this branch: `verify:naga-wasm:all` (`gen-prismatic-quantum-loom.wgsl:118` swizzle assignment `rd.xy += …`, not in knownFailures) and `verify:prelude-migration` (`4d-projection-dream-weavers`, `acoustic-string-theory` already include the prelude but are still listed pending in `src/contracts/prelude_migration.json`).
Real-GPU visual QA: external. All renders and timings here are minirender/SwiftShader.

## Per file

| Shader | Verdict | New ideas (in the WGSL) | §12.2 rows | Rescues (default look changes) |
|---|---|---|---|---|
| gen-ethereal-quantum-glass-nautilus | pass | Beer–Lambert shell absorption; conchiolin flame stripes; analytic siphon plume | Beer–Lambert (F) | uv/mouse flipped; finite shell with spiral aperture (HEAD was an unbounded dune slab); camera 26°→42°; jet at the real mouth. meanL 0.605→0.236 |
| gen-radiant-chrono-glass-nautilus | pass | escapement recoil ring-down; ratchet-toothed septa; cameral liquid level + meniscus | none | winding term made periodic (integer arm count, slider 1–9 arms, default 5) — torn seam gone; uv + gravity well flipped |
| gen-symbiotic-chrono-mycelium-engine | pass | golden-angle fruiting buds; streaming pulses on the chrono lag; twisted three-strand cord | Golden-angle (E), Additive domain twist (E) | uv flipped (gear was lit from below) |
| gen-resonant-quantum-obsidian-scarab-engine | pass | joint-fluid curvature; carapace flex with the core breath | SDF curvature (E) | upside-down camera (`rd.y`) — core moves with the pointer now |
| gen-radiant-quantum-crystalline-forge | pass | hammer-strike heat front; albite twin flash | Fold count (E) | R1 blank after 5 s (camera flew into/through the solid); R2 `twin = f32(i&1)` always 1 |
| gen-kryonic-quantum-aether-fractal-core | pass, flagged | fold-count ice grade; ridge translucency; meltwater sheen | Fold count (E), SDF curvature (E) | fold scale `s = 1 + scale` (fed 0.5 gave a contracting fold → smooth disc); rim term fixed. Biggest default-look change in the batch |
| gen-celestial-glass-tornado | pass | helical glass flutes; step-count AO | Step-count AO (E) | funnel upside-down; flat-yellow body (pole in `1/(1+d*50)`); dead extraBuffer spring → A texels (0,0),(1,0) |
| gen-vitreous-chrono-chandelier | pass | pendulum-projected floor foci; cleavage shards (wires Shatter Threshold); hub lamp | Soft inverse-square (F) | upside-down camera; chime spacing from fed 0.5; floor web only where floor is first surface; swing re-strike |
| gen-chromatic-singularity-loom | pass | relativistic Doppler beaming + gravitational redshift; chord-length emission profile on the threads | none | infall trail (0.035 rad/frame, nearest loads) → 0.014 + bilinear from exact loads, 3 px cap |
| gen-sentient-holographic-neuro-lace-matrix | pass | scan-lit lace with trailing wake; saltatory conduction with refractory tail | none | `time * audio` phase jumps in beads/vortex loops → constant rate |

## Coordinator decisions
- **Cut:** tornado idea "refracted sky through the wall" (Snell). Measured 164 of 23,746 funnel px at a mean 0.75/255 — not findable in the picture. Its helper (direction-cell `starAt`) was reverted; the background stars are HEAD's per-pixel hash again. Chromatic Split is still consumed by the glint split, so no dead slider.
- **Row tally (§12.4):** Fold count 2 (forge, kryonic), SDF curvature 2 (scarab, kryonic), every other row 1. No Cauchy added (already on the tornado). No two files share both formulae.
- **Boilerplate:** diffs are idea + rescue code; the plumbing swap is its own commit.

## Open items
- Timings (SwiftShader, load avg 7–10 from other sessions on the box, 2 back-to-back rounds, ms): kryonic 50→156–202 and forge 41–49→93–124 are mostly the rescues (HEAD marched a contracted disc / empty space); fork B measured the kryonic ideas alone at ≈+21%. Chandelier 52–59→80–101 (scene now filled, HEAD half black). Radiant nautilus 37–41→45–65. Mycelium 50–59→62–63. Scarab, tornado, loom, neuro-lace, ethereal (0.4–0.5× HEAD) ≈ flat or faster. Re-time on a real GPU.
- Kryonic and scarab JSONs have no top-level `params` (x-meta only): the app feeds 0.5×4, so the authored x-meta defaults are never seen. Not changed. Kryonic `s = 1 + scale` is a mapping change (authored range [0.5,5] now means 1.5–6); no UI slider exists for it.
- Neuro-lace camera flies backwards relative to its view (`ro.z` decreases, `rd.z=+1`); stills cannot show it, left alone.
- Loom: a few sawtooth patches remain at 576 px near thread corners with a moved cursor. Ethereal: thin dark gaps where rays graze whorl grooves; siphuncle SDF still never contributes.
- Tornado A-texel spring needs a real-GPU check where A is rgba16float. Chandelier JSON `features` gained raymarched/audio-reactive/mouse-driven/upgraded-rgba to match its header.
