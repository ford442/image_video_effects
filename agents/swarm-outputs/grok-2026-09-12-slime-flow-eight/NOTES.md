# Slime / flow leftover eight — notes

Per shader: kept verbatim, packing, which ideas are in the diff.

## sim-slime-mold-growth
KEEP: trail/diffused/activity/deposit; Sensor Angle / Trail Decay / Particle Count / Randomness; mouse food; click rings; L/C/R sensor loop.
A packing: raw (trail, diffused, activity, deposit). ACES display only.
Ideas in diff: photo-luma food (`photoLuma` dark deposit); vein anastomosis (`corridorH`/`corridorV`/`anastomosis`).
No new springs.

## sim-slime-mold-growth-em
KEEP: trail/E-mag/signed B/activity; Sensor Angle / Trail Decay / EM Influence / Ripple Charge dual-use; extraBuffer[133..138] pointer history; click opposite charges.
A packing: raw (trail, E mag, signed B, activity).
Ideas in diff: field-line deposit (`alongE` / `fieldLineDeposit`); opposite-polarity wipe (`secE` / `wipe`).
No new extraBuffer slots.

## slime-mold-on-video
KEEP: trail/food/drift packing; Trail Follow / Trail Decay / Food Gain / Glow; mouse food; click fronts; chem packets.
A packing: raw (trail, food, drift.x, drift.y).
Ideas in diff: food anastomosis (`islandBridge`); streamer veins (`alongDrift` / `streamer` / `vein`).
No new springs.

## luma-flow-field
KEEP: HDR trail RGB + coverage A; Flow Scale / Trail Decay / Curl Strength / Audio Sensitivity; isoFlow; mouse vortex; click fronts.
A packing: HDR display-history RGBA.
Ideas in diff: LIC tap (`licPx` / `licHist`); stagnation hold (`stagnate`).
No new springs.

## wave-equation-rgba-fluid
KEEP: height/vel/pressure/dye; Wave Speed / Wave Damping / Fluid Viscosity / Source Strength; mouse oscillator + held dye; click injects; Jacobi pressure.
A packing: raw (height, velocity, pressure, dye). ACES display only.
Ideas in diff: breaking-wave foam (`breaking` downhill steep slope); dye stretch (`stretch` along fluidVel).
FLOOR: C samples → exact `stateAt` / reconstructed `stateLinear`; plasmaBuffer; ACES. No new springs.

## spec-runge-kutta-advection
KEEP: RK4 backtrace; Time Step / Diffusion / Vortex Strength / Temporal Feedback; vortex pair; curl vis.
A packing: HDR dye RGB + |vel| in A.
Ideas in diff: strain-rate filaments (`strain` / `filament`); second RK4 LIC tap (`licPos` / `licDye`).
No new springs.

## sim-heat-haze-field
KEEP: Temperature Intensity / Convection Speed / Distortion Strength / Heat Source Count; temp/grad/disp packing; mouse heat; click rings.
A packing: raw (temp, grad.x, grad.y, displacement mag).
Ideas in diff: thermal plumes (`plume` from cell below); schlieren streaks (`isoT` / `schliere`).
No new springs.

## lichtenberg-fractal
KEEP: Branch Complexity / Decay Speed / Glow Intensity / Depth Attraction; charge/age; mouse ignition; click origins; curl alignment.
A packing: raw (charge, age, curl bias, scorch). ACES display only.
Ideas in diff: streamer tips (`tip` high-charge empty neighbors); residual scorch (`scorch` in A, darkens photo).
FLOOR: C samples → exact `stateAt`; ACES; semantic alpha. No new springs.
