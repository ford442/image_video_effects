# Coordinator review — explosion / warp twelve

Formula cap: Cauchy §12.2F on hyper-space-jump-blackbody only. Schmitt §12.2B on circuit-breaker-explosion only. N-wave on chromatic-shockwave only. Core-spend on elastic-chromatic-explosion and cursor-aura-explosion only. No new spring. No new IQ palette (existing rings on cursor-aura, circuit, and warp were left in place).

| Shader | Card before edit | Ideas pointable | Keep holds | Packing | Params | Spring only if native | Verdict |
|---|---|---|---|---|---|---|---|
| cmyk-halftone-explosion | yes | K hold; `screenDot` ellipse | angles, sqrt radius, spread | ACES display | exact | no spring | pass |
| elastic-chromatic-explosion | yes | `smear`; fringe desat | lag/prism/sat kernel, existing spring | ACES display | exact (JSON labels differ; not rewired) | existing spring kept | pass |
| interactive-rgb-split-explosion | yes | `radial`; `lip` | falloff 0 ungated | ACES display | exact | no spring | pass |
| cursor-aura-explosion | yes | `dispAmt` limb; core spend | mask, ring, edges | ACES display | exact | no spring | pass |
| chronos-brush-explosion | yes | `prismAmt` on `rim`; rim thaw | Decay multiply first | raw freeze in A | exact | no spring | pass |
| circuit-breaker-explosion | yes | `drop`; latch in A.a | grid, nodes, jitter | display RGB + latch A.a | exact | no spring | pass |
| mouse-chromatic-explosion | yes | radial `0.28`; `wheel` | single sample | ACES display | exact | no spring | pass |
| chromatic-shockwave | yes | `nwave`; `crestGate` | ring stack, Beer–Lambert, existing spring | ACES display | exact | existing spring kept | pass |
| zoom-burst | yes | `spokeGap`; `t * 0.7` chroma loss | comets, ghost, existing spring | ACES display | exact | existing spring kept | pass |
| hyper-space-jump | yes | rim blue-shift; C mix | 30-tap loop, depth 0, dead sliders rewired in place | ACES display | exact | no spring | pass |
| hyper-space-jump-blackbody | yes | `cauchyScale`; cooled C | Lorentz, beaming, pre-ACES store | pre-ACES + vignette alpha | exact | no spring | pass |
| warp-drive | yes | wall at `t = 0.5`; bow/wake `doppler` | Alcubierre, stars, packets | diagnostic A | exact | no spring | pass |

- [x] BRIEFS.md has the mechanism interrogation
- [x] Formula names are in NOTES.md and the `Ideas:` lines
- [x] No §12.2 row is on more than two files
- [x] Each formula uses a quantity the file already had
- [x] No `fwidth` / `dpdx`. `pow` bases that this pass touches are guarded (`max` or a non-negative square)
