# Batch 70 briefs — fluid, paint, reaction, and slime

This cohort upgrades ten existing effects without changing renderer APIs,
bindings, uniforms, saved presets, graph dispatch counts, or WASM behavior.

| Effect | A/C ownership | Upgrade focus |
|---|---|---|
| `alpha-fluid-simulation-paint` | velocity.xy / pressure / dye | Exact reconstructed advection, audio viscosity, hover/held paint, chromatic fronts |
| `chromatographic-fluid` | separated dye RGB / temperature | Seven-dispatch A-only chromatography, wind, phase change, solvent splashes |
| `sim-heat-haze-field` | temperature / gradient.xy / activity | Boundary-safe convection, thermal refraction, held heat and expanding fronts |
| `sim-slime-mold-growth` | trail / nutrient / activity / deposit | Exact Physarum sensing, band-shaped growth, held food and click colonies |
| `sim-slime-mold-growth-em` | trail / E magnitude / signed B / activity | Guarded pointer charge history, EM steering, orbiting click charges |
| `slime-mold-on-video` | trail / video food / encoded drift.xy | Video chemotaxis, exact trail advection, held food and spectral tendrils |
| `gray-scott-tank` | U / V / age / seed mask | Six-dispatch reaction diffusion, hover/held paint, band-biased kinetics |
| `spec-runge-kutta-advection` | raw dye RGB / flow speed | RK4 flow, exact history reconstruction, vortex pairs and click fronts |
| `painterly-oil-bilateral` | ACES display RGB / thickness | Wet-paint memory, anisotropic brushwork, bilateral focus and impasto |
| `cyber-ripples-coupled` | velocity.xy / vorticity / density | Retained Batch 67 fluid core plus Naga literal repair and aligned metadata |

## Cohort contract

- Bindings 0–12, canonical uniforms, 16×16×1 workgroups, output guards.
- Every C read is an exact bounded `textureLoad`; manual reconstruction is used
  where continuous advection needs interpolation.
- A is the only feedback storage target. GraphRunner copies A→C between graph
  nodes; B remains layout-only.
- Bass, mids, and treble come from `plasmaBuffer[0].xyz` and affect distinct
  motion, chemistry, pigment, or lighting behavior.
- Pointer hover remains active, held input is stronger, and click loops are
  capped, timestamp-guarded, finite, and aspect-correct.
- Raw simulation state is never tone-mapped. Display output uses canonical ACES
  and effect-derived semantic alpha.
- Persistent scalar state is absent except for guarded EM/Cyber pointer state
  at `extraBuffer[133..138]` written only by invocation `(0,0)`.
