# Photo / print / grade eight — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `pp-bloom` | intensity / anamorphic / threshold / quality taps; soft-knee extract; additive composite | `extractBright` scales RGB by luma contribution (hue-preserving); extra 1D horizontal streak loop | ACES display RGBA (was blur-in-A) |
| `pp-tone-map` | four named curves; exposure / contrast / saturation | `algorithm * 3` mixes neighboring curves; `applyContrastHue` | display RGBA, no second ACES |
| `analog-film-degrade` | grain / fade / scratch / vignette; sepia+desat | per-channel grain; weave + hairline (no `floor(time)`); `textureLoad` C print-through | ACES display RGBA |
| `color-blindness` | three matrices; severity; mouse-X split | `mixMat` along Type; unused `w` hatches confusion axis | display RGBA |
| `crumpled-paper` | FBM ridges; mouse iron; AO / sheen / wear | fibre along crease tangent; C.a height memory | display RGB + height in A.a |
| `retro-gameboy` | 4-shade palette; block quantize; grid; shadow | round LCD `lcd` mask; `dataTextureA` so C ghost is this shader | ACES display RGBA |
| `conv-bilateral-dream` | spatial/color sigma; mouse well; bilateral loop | luma+depth range; write A | ACES display RGBA |
| `tilt-shift` | Scheimpflug band; golden spiral; toy sat | hex radius weight on samples; highlight bloom in CoC | ACES display RGBA |

No springs. No extraBuffer writes. Saved `params` unchanged; `updatedParams` aligned by index.
