# gen-navier-stokes-ink — New Shader Notes

## Overview
Simplified 2D Navier-Stokes fluid simulation with semi-Lagrangian advection of velocity and ink density. Mouse injects ink and creates vortices; bass drives injection intensity.

## Algorithm
- Velocity (rg) and ink density (b) stored in dataTextureC
- Semi-Lagrangian advection: backtrace by velocity, sample previous state
- Mouse force adds impulse at cursor position
- Viscosity via neighbor-averaged velocity blend
- Cheap divergence reduction: subtract 0.5 * divergence from each velocity component
- Ink source at mouse with exponential falloff, plus natural decay
- Vorticity computed as curl for visual bloom

## Visual Details
- Deep blue ink in water with turbulent eddy highlights
- High-vorticity regions bloom with cyan/white
- Chromatic dispersion on shear layers (velocity magnitude)
- ACES tone mapping for HDR ink density

## Interactivity
- Bass drives ink injection rate
- Mouse injects ink and creates velocity vortices when held
- Depth controls overall opacity
- Parameters: injection rate, viscosity, dispersion, vorticity scale

## Risks
- Single-pass pressure projection is approximate (not fully divergence-free)
- Fluid state depends on continuous temporal feedback
- Advection can cause numerical diffusion at low viscosity
- First few frames may look sparse until velocity field establishes
