# Notes — cursor/batch-31 fireworks and embers (2026-11-01)

Second pass. Each file already had a named idea set. Two more ideas were added inside that path. Saved `params` on the eleven shaders that already had them stay byte-exact. No new spring.

`gen-stardust-nebula` had slider names and defaults only under `x-meta.upgrade.params`, so the catalog shipped no sliders and the engine left `zoom_params` at 0.5. A live `params` array was added by copying those four names, defaults, min, max, and step. The WGSL already read all four.

| Shader | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| fireworks-depth-parade | three depth layers, layer delay, depth match, occlusion visibility, atmospheric desat, click barrage order, Layer Separation / Launch Speed / Depth Boost / Trail Length | ACES display RGBA; B dimmed echo | mortar rise; foreground smoke veil |
| fireworks-edge-ignite | Sobel gradient, tangent spread, sine fuse, click ascent then burst, Edge Sensitivity / Launch Power / Trail Glow / Color Boost | ACES display RGBA; B dimmed echo | fuse bead; char lip |
| fireworks-patriotic-july4 | patriotColor, j%3 tricolor sparks, stripe wave, star rays, mortar flash, Patriot Mix / Burst Power / Stripe Wave / Sparkle | ACES display RGBA; B dimmed echo | sequenced break; cloth crease |
| fireworks-portrait-burst | seven luma probes, thresh, dissolve, warmth cooling, highlight bloom, Brightness / Burst Size / Dissolve / Warmth | ACES display RGBA; B dimmed echo | catchlight pin; outward highlight bias |
| gen-fireworks-comet-trail | hex head, coma, ion tail, kink, nucleus jets, peel sparks, Comet Speed / Trail Length / Head Brightness / Color Shift | ACES display RGBA | bow shock; dust-tail sag |
| gen-fireworks-crossette | four-way fork, split delay, stagger, X flash, comet sheath, Shell Power / Split Delay / Arm Spread / Hue Shift | ACES display RGBA | broken core; axis ghost |
| gen-fireworks-roman-candle | tube row, shot cadence, starCol sequence, muzzle flash, gold fountain, gutter flicker, Fire Rate / Star Size / Tube Spread / Trail Length | ACES display RGBA | candle tube; apex report |
| gen-fireworks-strobe-shell | strobePulse, per-spark phase, dark interval, dotted path, sky veil, Flash Rate / Pulse Power / Afterglow / Color Flash | ACES display RGBA | blink budget; white-core fringe |
| gen-fireworks-kamuro-gold | hang plateau, per-glitter twinkle, dross satellites, charcoal cooling, Glitter Density / Fall Speed / Gold Mix / Hang Time | ACES display RGBA | cloud sag; fine-mesh hang |
| gen-fireworks-horse-tail | drag tail, pinch then parallel rain, tip spark-out, swish, dock knot, Tail Length / Stream Width / Gold Intensity / Fall Speed | ACES display RGBA | running sheen; tip ember |
| ember-drift-dissolve | A = (age, lateral, intensity, glow) never tonemapped, exact C loads, furnace, crackle, ash wisps, click ignition, Rise / Spark / Heat / Decay | raw ember state. ACES on writeTexture only | hot-band rise; scorch stain |
| gen-stardust-nebula | fbm5 + curl, H-alpha / OIII / SII, pillar column, starField, Cloud Density / Emission / Star Field / Gas Drift | ACES display RGBA (C unread) | Beer-Lambert pillar (§12.2F); ionization rim |

Formula use: Beer-Lambert (§12.2F) only on `gen-stardust-nebula`. No other §12.2 row. No new spring.

Floor: `#include "_prelude.wgsl"` on all twelve. `gen-stardust-nebula` had a pasted header; `migrate_to_prelude.py` swapped it before the idea edit. 16×16. Exact C where C is read. Ember A is still the raw state. `upgraded-rgba` added to ember features. Stardust features set to audio-reactive, mouse-driven, upgraded-rgba.

Gates: Naga 12/12, precommit 12/12, extraBuffer 0 new, dead sliders 0 new on these twelve, catalogs regenerated. Vitest 180 files / 1532 passed (1 skipped). `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA is external.
