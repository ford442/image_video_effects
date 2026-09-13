# Coordinator Review — Grok-1 simpler generative leftover (10) (2026-09-13)

Verdict: **10 skip (already upgraded) / 0 metadata-pass / 0 new creative upgrades.**
This batch is not a 10-shader Idea Card upgrade — the supplied list was stale.
See BRIEFS.md for the audit and NOTES.md for the (empty) diff.

## Per-file checklist

| ID | Idea Card before diff | Ideas pointable in WGSL | KEEP VERBATIM held | Diff ≥70% boilerplate? | No generic overlay | A packing matches C read | Saved params unchanged | Springs/ripples native-only | Naga/extraBuffer/dead-sliders |
|---|---|---|---|---|---|---|---|---|---|
| `gen-fireworks-nocturne` | n/a — untouched | yes (muzzle; even/odd droop) | yes | n/a | n/a | yes | yes | no new spring | not re-run (untouched) |
| `gen-fireworks-ring-shell` | n/a — untouched | yes (Saturn tilt; empty core) | yes | n/a | n/a | yes | yes | n/a | not re-run |
| `gen-fireworks-roman-candle` | n/a — untouched | yes (muzzle; starCol sequence) | yes | n/a | n/a | yes | yes | click ripples kept | not re-run |
| `gen-fireworks-smoke-bloom` | n/a — untouched | yes (buoyancy; burst-lit puff) | yes | n/a | n/a | yes | yes | n/a | not re-run |
| `gen-fireworks-strobe-shell` | n/a — untouched | yes (per-spark phase; pulse→0) | yes | n/a | n/a | yes | yes | n/a | not re-run |
| `gen-fireworks-willow-cascade` | n/a — untouched | yes (terminal hang; leeward lean) | yes | n/a | n/a | yes | yes | n/a | not re-run |
| `gen-fireworks-wind-ripple` | n/a — untouched | yes (altitude shear; leeward streak) | yes | n/a | n/a | yes | yes | click barrages kept | not re-run |
| `gen-fluffy-raincloud` | n/a — untouched | yes (anvil; virga) | yes | n/a | n/a | yes (raw ρ/vel/moisture) | yes | n/a | not re-run |
| `gen-fourier-epicycles` | n/a — untouched | yes (arm segments; pen ink) | yes | n/a | n/a | yes (bassEnv/trail) | yes | n/a | not re-run |
| `gen-grid` | n/a — untouched | yes (Jacobian lattice; C phosphor) | yes | n/a | n/a | yes | yes | existing well kept | not re-run |

## On counting this as throughput

`docs/SHADER_UPGRADE_BATCH.md` §9 fails a file whose diff is ≥70% header
boilerplate **when it's presented as an upgrade**. These 10 have **no diff**.
Do not count them toward "shaders upgraded today."

## Recommendation

The requested 10-ID list is exhausted (fireworks taxonomy + atmospheric six +
kinetic ten A/B already own every ID). If more simpler-generative throughput
is wanted, a genuinely leftover classic math/CA/field ten exists — see
BRIEFS.md "Not started here." Did not substitute those IDs into this batch.
Also still available globally: `crt-clear-zone`, liquid-small, blackbody
Phase-C. Still skipped: tropism-rich `mycelium-network`, physarum
`extraBuffer[0..]` agents, `gen-percolation-threshold` (FFT-zone writes).
