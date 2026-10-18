# Coordinator review — cursor batch-05

2026-10-18. Cards were in `BRIEFS.md` before the WGSL.

| Shader | Verdict | Why |
|---|---|---|
| fabric-of-reality | pass | Shear, catenary, and weave/fray are each pointable. Jacobi, pin, and position packing kept. Render recomputes strain because B is write-only. |
| digital-glitch-pass1 | pass | Carry and Schmitt tear use the existing field. Byte corruptors and A packing kept. |
| digital-glitch-pass2 | pass | Chroma delay and block quant use Error Propagation and Bit Manipulation. Does not write A. |
| pyramid-downsample-pass1 | pass | Bilateral weight and low-band settle sit on the existing tile blur. |
| pyramid-bandprocess-pass2 | pass | Anti-halo and gradient fringe sit on the residual. A write removed so the blur survives. |
| pyramid-composite-pass3 | pass | Magnified sample and rim split sit on the existing circle. |
| gen-magnetic-dipole-field | pass | Filings and the null are added to the dipole that was already there. |
| gen-ethereal-chrono-fluid-symbiote | pass | Step occlusion and chrono shells use the march and Chrono Warp. |
| gen-stable-fluids-jos-stam | pass | MacCormack is a correction on the dye backtrace. No-slip uses Viscosity. Solver kept. |
| fire_smoke_volumetric | pass | Lift, soot cap, and red fringe use the flame and the advected density. Smoke packing kept. |

Checklist: cards exist; each idea is named in the WGSL; saved params were not re-defaulted; no spring was added to a shader that did not already have one; A packing matches the notes.
