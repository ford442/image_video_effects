# Batch 55 briefs — 2026-08-21 (tracker #471–474) — GEOMETRY + FAST MOTION + PSYCHEDELIC COLOR

Batch 55 upgrades four clean single-pass effects from the ~129–130 line band
with extra geometry, two continuous-motion structures each, held-pointer
deformation, click fronts capped by live ripple count and 50, and psychedelic
color. `rainbow-vector-field` remains skipped (Pass-1). Print/wind/slit
shaders in the same size band were skipped so this four-pack has geometry to
enrich.

| # | Shader | Upgrade focus |
|---|--------|---------------|
| 471 | `kaleido-scope-grokcf1` | 16x16, facet seams, wedge conveyor, radial packets, oil-slick, iris clicks |
| 472 | `rgb-topology` | Index isolines, ridge ticks, iso-runners, rainbow hypsometry, click fronts |
| 473 | `elastic-strip` | Beveled sub-ribs, traveling plucks, thin-film color, click plucks |
| 474 | `refraction-tunnel` | Ribs/hoops/helix, analytic rainbow caustics, click rings |

## Shared contract

- Preserve source `params` byte-for-byte and add aligned `updatedParams`.
- Preserve canonical 13 bindings, 16x16x1 workgroups, depth ownership, and
  `plasmaBuffer[0].xyz` audio.
- Keep B unused and introduce no `extraBuffer` access.
- Preserve established A packing: kaleido origin `[env, springXY, vel]` /
  elsewhere trail RGBA; topology `[lineR, lineG, lineB, alpha]`; strip and
  tunnel display RGBA.
- No renderer, graph, toolchain, dependency, or public TypeScript API changes.
- Structural validation is local; visual acceptance requires a real GPU.
