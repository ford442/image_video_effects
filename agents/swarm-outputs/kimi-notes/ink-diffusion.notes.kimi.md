# ink-diffusion — New Shader Notes

## Overview
Temporal ink wash painting effect. Organic spread via neighbor averaging with noise turbulence.

## Algorithm
- Reads previous ink state from dataTextureC
- Averages 4-neighbor ink values with spreadRate
- Hash noise adds turbulent diffusion
- Mouse click deposits ink with smoothstep brush
- Audio bass adds random splatter
- Wet edge darkening simulates paper absorption

## Wow Factor
- Click and watch ink spread organically across paper like real sumi-e
- Audio splatter creates Jackson Pollock-style chaos

## Risks
- Requires dataTextureC ping-pong for temporal persistence
- Decay rate must balance spread — too high and ink vanishes, too low and screen saturates
- No actual reaction-diffusion (just averaging + noise)
