# Optical / Glass / Holographic "Remaining Ten" — Audit + Idea Cards (2026-09-13)

Requested batch: "Claude batch — optical / glass / holographic remaining (10)"

```
gen-glass-mosaic-liquid-refraction
gen-ethereal-glass-flora-terrarium
gen-ethereal-quantum-hologram-bonsai
gen-ethereal-quantum-holographic-fractal-coral
gen-ethereal-quantum-medusa
gen-holographic-fracture
gen-holographic-membrane
gen-holographic-plasma-geode
gen-holographic-rainbow-surface
gen-holographic-lens-flare-matrix
```

## Pre-flight finding

Before writing any Idea Card, read all 10 headers + full WGSL. The list was stale:
**7 of 10 already carry a real, dated `Ideas:` header from prior batches**
(`gen-ethereal-glass-flora-terrarium`, `gen-ethereal-quantum-hologram-bonsai`,
`gen-ethereal-quantum-holographic-fractal-coral`, `gen-ethereal-quantum-medusa` —
2026-09-11 "Ethereal generative ten"; `gen-holographic-plasma-geode`,
`gen-holographic-rainbow-surface`, `gen-holographic-lens-flare-matrix` — 2026-09-06).
Per `docs/SHADER_UPGRADE_BATCH.md` §5.3 ("Floor present, already idea-rich → Skip.
Do not bump the `Upgraded:` date for hygiene"), these 7 were **left untouched**.

The remaining 3 were read in full and are also already idea-rich in the executed
code (glass mosaic Voronoi/Worley/Fresnel/Beer-Lambert/curl-noise; fracture's
spring-eased mouse crack network + click fronts + per-crack FFT-bin iridescence;
membrane's two-layer thin-film interference + click impulses + audio vibration)
— but none had named the techniques in an `Ideas:` header line, and none/only
partially carried the `upgraded-rgba` tag. This is row 3 of the same matrix:
**"Header / tag / `updatedParams` missing, picture already good → Metadata pass
— allowed, but do not call it an upgrade and do not date-stamp `Upgraded:`."**

## Idea Cards (documentation only — no new native ideas added)

```
SHADER: gen-glass-mosaic-liquid-refraction
IDENTITY: stained-glass Voronoi mosaic with liquid refraction over the source video
KEEP VERBATIM: all params (facet-density/bevel-width/refraction-strength/ripple-speed),
  Voronoi+Worley kernel, curl-noise heightfield, Fresnel/Beer-Lambert optics
ALREADY PRESENT (named, not added): FBM domain-warped Voronoi glass mosaic w/ Worley
  grain; IOR Fresnel-Schlick reflection + Beer-Lambert chromatic absorption;
  curl-noise liquid heightfield driving refraction + caustic sparkle
FORBID: re-adding springs/ripples, second overlay, bumping Upgraded: date
A PACKING: ACES display RGBA (unchanged)
ACTION: header/JSON tag only (`upgraded-rgba`); Upgraded: date left at 2026-06-28

SHADER: gen-holographic-fracture
IDENTITY: iridescent cracked SDF shard field, mouse cracks it, clicks fracture it further
KEEP VERBATIM: all 4 params, spring-eased extraBuffer[133..137] mouse-crack origin,
  radial SDF crack network, ripple-driven crack fronts
ALREADY PRESENT (named, not added): spring-eased mouse crack origin driving radial
  SDF fracture network; click-triggered expanding crack fronts w/ trailing spokes;
  per-crack iridescence phase keyed to FFT bins 1-8 (plasmaBuffer[1..8])
FORBID: re-adding springs/ripples (already native here), bumping Upgraded: date
A PACKING: ACES display RGBA, hue-preserving clamp before tonemap (unchanged)
ACTION: header (Ideas/A packing/Features) + JSON tag only; no prior Upgraded:
  line existed, none added (metadata pass, not a dated upgrade)

SHADER: gen-holographic-membrane
IDENTITY: thin-film interference membrane, alpha = depth translucency
KEEP VERBATIM: all 4 params, raw [height, normal.xy, alpha] A/C packing, click-impulse
  height/normal perturbation
ALREADY PRESENT (named, not added): two-layer thin-film interference with mouse
  view-angle shift + bulge/depression; click impulses perturbing height/normal with
  slope-driven specular kick; bass/mids/treble/rms-driven vibration, iridescence
  speed, and trough transparency
FORBID: re-adding springs/ripples, bumping Upgraded: date
A PACKING: raw [height, normal.x, normal.y, alpha] (unchanged) — ACES display-only
ACTION: header (Ideas/A packing) + JSON tag only (`upgraded-rgba` was in the WGSL
  Features comment already but missing from JSON — drift fixed); no Upgraded: line
```

No WGSL algorithm, param, or packing was changed on any of the 10 files.
