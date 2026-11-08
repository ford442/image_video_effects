SHADER: gen_orb / gen-orb (2nd pass)
IDENTITY: Lorenz attractor, 8–14 RK4 streams drawn as glowing trails, ACES, C-trail persistence
KEEP VERBATIM: RK4 integrator, stream seeding/warm-up, hue scheme, sparks/eyes/Poincaré/Lyapunov ideas, params, trail feedback
RESCUES (HEAD was a flat white wash, meanL 0.81 at JSON defaults):
  - projection scale 0.0015 squeezed the whole attractor into ~0.03 of screen → now 0.06, centred on z=25 and stood upright (z up, classic butterfly)
  - 1/d² glow tails summed over 5600 samples → bounded Lorentzian s²/(d²+s²) for glow and halo
  - "line" glow used |d0−d1| (lights whole hyperbola bands) → true point-to-segment distance
  - eye ring radius rescaled to the new projection
ADD: 1. Lorenz-map peak beads — flash at each successive z maximum (dz/dt + → −), the z_n→z_{n+1} sequence Lorenz plotted; bass brightens
     2. convection temperature tint — z is the roll model's temperature deviation; crests tinted ember, troughs cold (35% mix over the hue)
A PACKING: unchanged (ACES display RGBA)
Stats @128px defaults: before meanL 0.809 std 0.071 (wash) → after meanL 0.030 std 0.049 (dark field, line art); bass=1: meanL 0.073. ~3 s/frame SwiftShader (unchanged cost).
