# Crackle palm through echo chamber — notes (2026-10-11)

Cards: `BRIEFS.md`, written before the WGSL edits. `gen-evolutionary-cellular-gardens` was skipped: ledger event 2026-10-09 / header `Upgraded: 2026-10-10` (chrono-ferro ten). `gen-feedback-echo-chamber` was on that October 9 list but its ledger history is empty, so it is in this batch.

Every file was migrated from a pasted binding header to `#include "_prelude.wgsl"` first (header-only, not counted). Saved `params` and `updatedParams` are byte-identical; each definition's `description` gained one sentence naming the new ideas.

| Shader | Kept verbatim | New ideas in the diff | A packing |
|---|---|---|---|
| gen-fireworks-crackle-palm | crackle on primary sparks; opposite leaflets; held command shell | `rib` rachis filament; frond-tip pistil | ACES display RGBA |
| gen-fireworks-crossette | parent star, four-way fork, X flash, held mouse crossette | parent comet sheath; per-arm split stagger | ACES display RGBA |
| gen-fluffy-raincloud | curl advection, anvil, virga, gust spring `[133..136]`, click gusts | mammatus pouches; shelf-cloud roll | raw density, velocity.xy, moisture |
| gen-fourier-epicycles | arm glow, pen ink into C trail pack, mouse gravity, held shock | phase tick; cusp ink | bassEnv, trail.r, trail.g, alpha |
| gen-fractal-clockwork | tooth sparks, mesh, escapement, ruby jewels, spring orbit `[133..138]`, click torque | oil weep; hairspring | ACES display RGBA |
| gen-fractal-ember-lattice | junctions, core heat, heat crawl, cooling / re-ignition, mouse shatter | oxide scale; pop-off sparks | raw A.rg displacement, A.b seed, A.a reform |
| gen-fractured-monolith | shard tint, fracture glints, seam pool, rising pulse, mouse orbit | spall chips (mat 3); crack dust in the seam glow | ACES display RGBA |
| gen-ghost-flame | wick, chemiluminescence, puff pinch-off, schlieren, mouse heat, click bursts, envelope `[133..134]` | inner cone; soot streak | raw temperature, fuel, vx, age |
| gen-feedback-echo-chamber | harmonic 2x ladder, nodal field, gravity well, held shock, click ripples, bass env `[133]` | early wall reflections; comb-filter notches | ACES display RGBA |

No new spring was added. Existing pointer, held, and click-ripple behavior was left in place. Display RGB is ACES; raw sim fields are not.

Regenerating the shader lists also dropped legacy top-level `updatedParams` from three list entries whose definitions already keep that block under `x-meta` (`gen-aether-forged-nacreous-labyrinth`, `gen-chromodynamic-glass-labyrinth`, `neon-ripple-split`). That is what the schema test checks.

Gates: Naga 9/9 (`wgsl_precommit_gate.py`), extraBuffer 0 new violations, dead sliders 0 new, catalog drift 0, Jest 152 suites (schema test green after the list regenerate), `SKIP_WASM_BUILD=1` build. Real-GPU visual QA: external.
