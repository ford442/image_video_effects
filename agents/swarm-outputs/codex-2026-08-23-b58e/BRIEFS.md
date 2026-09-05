# Batch 58E briefs — 2026-08-23 (tracker #491–500)

Ten interactive shaders. Each keeps source `params` exact, canonical 13
bindings, 16x16x1 workgroups, unused B, and no new extraBuffer writes.
Existing extraBuffer[133+] springs on emboss / film-burn / glitch-brush stay
and now write only from pixel (0,0). Click loops are `min(u32(u.config.y), 50u)`.

| # | Shader | Upgrade focus |
|---|--------|---------------|
| 491 | `interactive-emboss` | Bevel ridges, highlight packets, oil-slick crests, held punch |
| 492 | `interactive-film-burn` | Ember conveyors, oil-slick heat, held flare; A stays [hole,fire,smoke,alpha] |
| 493 | `interactive-fisheye` | Held meniscus pinch, thin-film rim, caustic runners; A stays [h,v,nx,ny] |
| 494 | `interactive-fresnel` | Held ring squeeze, oil-slick grout, radial packets |
| 495 | `interactive-glitch-brush` | Scan-head conveyor, oil-slick tears, C paint persist; 0,0 spring writer |
| 496 | `interactive-glitch-cubes` | Beveled grout, conveyor packets, oil-slick edges; A [rgb,height] |
| 497 | `interactive-halftone-spin` | Held shear, ink conveyors, click splats; A stays CMYK coverage |
| 498 | `interactive-kuwahara` | Wet runners, oil-slick pigment, C wetness trail |
| 499 | `interactive-magnetic-ripple` | Held field punch, oil-slick domain walls; capped live ripple loop |
| 500 | `interactive-origami` | Held pinch, crease runners, foil iridescence; exact C load |

## Shared contract

- Preserve source `params` ids/names/defaults/ranges.
- `plasmaBuffer[0].xyz` audio; optional bins 1–8.
- Exact `textureLoad` for `dataTextureC` and depth.
- Structural validation local; visual QA needs a real GPU.
