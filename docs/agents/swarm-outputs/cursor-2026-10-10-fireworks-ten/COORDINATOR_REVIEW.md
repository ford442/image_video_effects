# Fireworks ten — coordinator review (2026-10-10)

Checklist per `docs/SHADER_UPGRADE_BATCH.md` §9. Structural only; visual QA is external.

| Shader | Card first | Ideas pointable | Identity kept | No shared overlay | Packing | Params exact | Gates | Result |
|---|---|---|---|---|---|---|---|---|
| gen-fireworks-fan-shell | yes | `unfoldSweep`, `guardRib` | yes | yes | ACES display | yes | pass | PASS |
| gen-fireworks-horse-tail | yes | `tailSwish`, `dockKnot` | yes | yes | ACES display | yes | pass | PASS |
| gen-fireworks-kamuro-gold | yes | `drossFission`, `charcoalCool` | yes | yes | ACES display | yes | pass | PASS |
| gen-fireworks-nocturne | yes (revised pre-edit) | `aerialDepth`, `colorChange` | yes | yes | ACES display | yes | pass | PASS |
| gen-fireworks-ring-shell | yes | `ringRoll`, `farSide` | yes | yes | ACES display | yes | pass | PASS |
| gen-fireworks-roman-candle | yes | `fountain`, `gutter` | yes | yes | ACES display | yes | pass | PASS |
| gen-fireworks-smoke-bloom | yes | `vortexRing`, `extinction` | yes | yes | ACES display | yes | pass | PASS |
| gen-fireworks-strobe-shell | yes | `strobeDots`, `skyStrobe` | yes | yes | ACES display | yes | pass | PASS |
| gen-fireworks-willow-cascade | yes | `willowTrunk`, `tipDrip` | yes | yes | ACES display | yes | pass | PASS |
| gen-fireworks-wind-ripple | yes | `gustBand`, `shockRefract` | yes | yes | ACES display | yes | pass | PASS |

No springs, click rings, or IQ palettes were added. `shockRefract` reuses the ripple barrages wind-ripple already owned.
