# gen-belousov-zhabotinsky — New Shader Notes

## Overview
Belousov-Zhabotinsky chemical oscillator simulated via reaction-diffusion with activator-inhibitor dynamics. Produces spiral waves and target patterns that morph over time.

## Algorithm
- State stored in dataTextureC.rg (activator a, inhibitor b)
- Laplacian computed from 4-neighbor samples
- FitzHugh-Nagumo style update: a' = a + ε(Da∇²a + a(1-a²) - b + feed), b' = b + ε(Db∇²b + 0.5(a-b))
- Spiral initial condition seeded when state is near zero
- Mouse down injects activator at cursor position

## Visual Details
- Chemical palette: blue → violet → red → orange oxidation states
- Wave fronts get HDR warm bloom
- Spiral tips highlighted with cool blue chromatic accent
- ACES tone mapping for HDR control

## Interactivity
- Bass drives reaction rate ε (faster oscillation)
- Mouse seeds new spiral centers with activator injection
- Depth controls overall opacity and diffusion weighting
- Parameters control Da, Db, feed rate, and base epsilon

## Risks
- Reaction-diffusion depends on temporal continuity; first frame auto-seeds
- Single-pass pressure-free projection is approximate
- Pattern may settle into steady state if parameters too low
