# Coordinator review — pass/fail against the cards

Checked: card exists before diff; each idea findable in WGSL (`Ideas:` header + tags); `Ideas:` + `A packing:` header present; saved `params`
untouched (none of the five JSONs has a `params` block; `updatedParams` unchanged); naga + precommit green on each; no springs / ripple overlay /
extraBuffer state added; no shared overlay between files.

| Shader | Verdict | Note |
|---|---|---|
| gen-sentient-aether-flora-biosphere | PASS | stripped 3 non-contract feature tags; dead kick state noted |
| gen-sentient-cyber-chrono-void-serpent | PASS | step budget 80→96; sliders hand-verified |
| gen-sentient-liquid-neon-fractal-heart | PASS w/ flag | default look shifts (ACES + real alpha) |
| gen-symbiotic-cyber-fungal-core-reactor | PASS w/ flag | core/click behaviour changes (spring was dead) |
| gen-symbiotic-light-networks | PASS | 4 ideas (ceiling); afterglow uses C |

Not verified: any rendered look (no GPU).
