SHADER: gen-hyper-rainbow-vortex
IDENTITY: multi-layer neon rainbow spiral vortex around a mouse-steered Rankine core, with hot singularity glow and counter-rotating arms.
KEEP VERBATIM: 4 spiralArm/interference layers, neonRainbow + hsv2rgb palettes, Rankine swirl (coreR = 0.2+bass*0.1, omega = 2+mids*3), mouse secondary vortex, click energy fronts, param roles (intensity / speed / scale / colorShift), A/C = raw HDR display RGBA history.
EXISTING IDEAS (2026-09-06):
  1. Rankine core / irrotational seam glow at r = a
  2. Counter-arm braid beads where spiral1 x spiral2 cross
ADD:
  3. Differential-rotation feedback advection — C history is textureLoad'ed at the back-rotated pixel using the Rankine angular velocity (rigid Omega inside the core, Omega*a^2/r^2 outside), so the core smears as a rigid disc and the outer flow shears into trailing streaks; native because it is the vortex's own velocity field driving its own history.
  4. Cyclostrophic pressure-deficit condensation funnel — Rankine pressure deficit q (2-(r/a)^2 inside, (a/r)^2 outside) condenses a swirl-striated violet-white haze where q passes a bass/intensity dew point, and the same q carves the depth funnel; native because the pressure well is implied by exactly the Rankine profile already in the file.
FORBID: spring cursor in extraBuffer, new ripple overlay, IQ cosine palette, conveyors, replacing the spiral layers or palettes.
A PACKING: raw HDR display RGBA history (pre-ACES), alpha = vortex energy coverage (unchanged).

## Notes
- Kept verbatim: all 4 spiral layers, palettes, Rankine swirl constants, mouse secondary vortex, click fronts, core glow/bands/pulse, Ideas 1-2, chromatic offset, ACES, alpha formula, param roles. Saved `params` byte-exact.
- A packing: raw HDR display RGBA history (pre-ACES) in A, read back from C via exact textureLoad (now at pixel + back-rotated pixel); alpha = vortex energy.
- Idea locations (public/shaders/gen-hyper-rainbow-vortex.wgsl): Idea 1 L187, Idea 2 L190, Idea 3 L223-233 (advected C fetch, 65% mix with in-place history), Idea 4 L193-201 (condensation haze) + L249 (depth funnel).
- Floor fixes: guarded aspect division (max(res.y,1)); header normalized to `Upgraded: 2026-09-13` with all four ideas; JSON features add "mouse-driven" (pointer steers vortex center + secondary vortex), description refreshed. Audio already plasmaBuffer[0].xyz; no extraBuffer use; no dataTextureC writes. All four sliders live (speed also scales advection step; scale sets funnel striae count; intensity lowers dew point).
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 pass, 0 extraBuffer violations. No real-GPU visual QA.
