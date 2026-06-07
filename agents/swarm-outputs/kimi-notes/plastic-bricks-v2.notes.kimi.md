# plastic-bricks v2 Upgrade Notes

## Overview
Upgraded from ~86 lines to ~135 lines. Added LEGO-style stud geometry, plastic microfacet BRDF, ambient occlusion, fingerprint smudges, subsurface scattering, and ACES tone mapping.

## Algorithmist Changes
- Added `plasticBRDF()` with Blinn-Phong-style microfacet specular: `pow(ndoth, mix(4, 128, 1-roughness))`.
- Separate normals for brick body and stud top for accurate shading.
- Ambient occlusion: `studCavityAO` darkens inside stud wells, `cornerAO` darkens brick edges.
- Running bond pattern already present; expanded with assembly wave physics.

## Visualist Changes
- Glossy plastic: high specular on studs (roughness 0.15), softer on bodies (0.35).
- Fingerprint smudges via `hash22(cell * 50)` noise tinted warm gray.
- Subsurface scattering in translucent bricks (30% random chance per brick).
- Per-brick randomized tint palette with audio hue shift.
- ACES tone mapping on final composited color.

## Interactivist Changes
- Bass drives `assemblyWave` animation with brick-id-phase offsets.
- Mouse push deconstructs bricks: `mousePush * 0.4` darkens and displaces.
- Depth read scales `density` for stud-size perspective.
- Audio modulates specular intensity and hue shift.

## Alpha Strategy
`finalAlpha = plasticAlpha * plasticGloss * depth`
where `plasticAlpha = clamp(0.65 + reliefMask * 0.2 + plasticGloss * 0.15, 0.42, 0.96)`
Semantic: glossier, more relief + closer depth = more opaque.

## Naga Status
Validated with `naga` (see main report).
