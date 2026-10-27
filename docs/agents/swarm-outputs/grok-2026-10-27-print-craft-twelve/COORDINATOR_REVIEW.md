# Coordinator review — print-craft twelve (2026-10-27)

Cards were written before the idea edits. Each numbered idea is named in the shader. Saved params were not renamed or re-defaulted.

| Shader | Verdict | Ideas in the diff | Formula | Packing |
|---|---|---|---|---|
| impasto-swirl | pass | knife ridge; lip bead | none | linear RGB + thickness in A.a |
| paper-cutout | pass | deckle; paper tooth | §12.2C granulation | ACES display RGBA |
| cmyk-halftone-interactive | pass | midtone dot gain; ink trap | none | CMYK coverage |
| foil-impression | pass | brushed catchlight; foil skip | none | ACES display RGBA |
| poly-art | pass | detail-sized cells; lit bevel | none | ACES display RGBA |
| cross-stitch | pass | knot; Aida holes | none | ACES display RGBA |
| knitted-fabric | pass | purl rows; lint | none | ACES display RGBA; masks in B |
| interactive-halftone-spin | pass | rosette hole; wet tack | none | CMYK coverage |
| dynamic-halftone | pass | pointer stretch; edge swell | none | ACES RGBA, premultiplied |
| charcoal-rub | pass | photo pigment; burnish | none | raw mask in A.r |
| sequin-flip | pass | stitch hole; edge-on glint | none | ACES display RGBA |
| stipple-engraving | pass | elliptical stipple; burr | none | ACES display RGBA |

`impasto-swirl` also replaces an unrelated stipple body with the oil-paint swirl the catalog describes. That restoration is called out in the card. The two ideas sit on the restored body.

Formula use: paper granulation once, on `paper-cutout` only. No row is shared.

Checklist: cards exist; ideas are commented in the main path; kernels and param roles kept; no shared spring or IQ stamp; A packing matches the C read; Naga 12/12; prelude tracker matches; extraBuffer clean; dead sliders 0 new on these 12.
