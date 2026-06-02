# mycelium-network — New Generative Shader Notes

## Overview
Underground fungal network with traveling nutrient pulses.

## Algorithm
- Cell-based: each cell has central trunk + 2-4 branches
- Nutrient pulses travel along trunk and branches via fract(time)
- Tip glow at branch endpoints
- Spore clouds at random cell centers
- Branch angles controlled by parameter

## Wow Factor
- Nutrient pulses look like electrical signals traveling through neurons
- Organic branching feels alive

## Risks
- Branch loop up to 4 per cell
- Pulse animation uses fract() — discontinuous resets
- No connection between cells (each is isolated)
