# Coordinator review — cursor/batch-31 (2026-11-01)

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea is marked with a `// ── Idea` comment.

| Shader | Verdict | Why |
|---|---|---|
| fireworks-depth-parade | pass | Mortar climb uses the existing layer delay. Layer-0 haze dims later layers. Three-layer order and params kept. |
| fireworks-edge-ignite | pass | Bead and char lip ride the existing tangent and edge mask. Contour launches kept. |
| fireworks-patriotic-july4 | pass | Band index now delays red, then white, then blue. Crease uses the existing stripe phase, before shells are added. |
| fireworks-portrait-burst | pass | Catchlight is the bright core the dissolve used to eat. Spark velocity gains the probe luma gradient. |
| gen-fireworks-comet-trail | pass | Bow arc is sunward of the head and wider than the jets. Older dust samples use more gravity than the head. Ion tail kept. |
| gen-fireworks-crossette | pass | Parent star and sheath fade once that arm's split time passes. A thin line remains on the arm axis. Four arms kept. |
| gen-fireworks-roman-candle | pass | Dark case sits behind the mouth. White report opens the existing apex burst. Tube cadence kept. |
| gen-fireworks-strobe-shell | pass | Live pulse ends after a Flash Rate budget. Dotted path and late embers stay. Tight white core sits inside the colored bokeh. |
| gen-fireworks-kamuro-gold | pass | Haze center drops with Fall Speed after the hang. Hang Time scales glitter size. Inner spark count unchanged. |
| gen-fireworks-horse-tail | pass | Sheen is a brightness pulse, separate from the lateral swish. One red coal per streamer sits past the gold cutoff. |
| ember-drift-dissolve | pass | Vertical advection uses stored age. Scorch is display-only. A packing is still (age, lateral, intensity, glow), not tonemapped. |
| gen-stardust-nebula | pass | Linear pillar darken replaced by exp(-tau). Cyan rim is pillar*(1-pillar), added after extinction. Motif kept. Prelude migration is floor. |

Formula check: Beer-Lambert (§12.2F) appears on one file. No shared second formula. No new spring. No extraBuffer write. Saved params on the eleven existing definitions are unchanged. Stardust gained a live `params` array copied from its existing `x-meta.upgrade.params`.

Gates: Naga 12/12, precommit 12/12, extraBuffer 0 new, dead sliders 0 new, lists regenerated. Vitest 180 files / 1532 passed (1 skipped). `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA is external.
