# Algorithmist Upgrade Notes: bubble-chamber

## Key Algorithmic Additions
1. **Curl-noise velocity field** — divergence-free turbulence layer (`curl2D`) added to the magnetic spiral base field, producing organic, incompressible fluid-like advection instead of rigid spirals.
2. **Clifford strange-attractor perturbation** — jet origins are perturbed by a time-evolving Clifford attractor (`a=1.7, b=1.3, c=1.1+time*0.02, d=1.9`), giving the particle trails living, chaotic drift.
3. **Gold-noise emission** — replaced simple pseudo-random spawn with quasi-random gold noise for better spatial distribution and temporal stability of ionization sparks.
4. **Domain-warped FBM absorption** — added `warpedFBM` chromatic drift that modulates trail persistence, creating multi-scale organic decay patterns.

## Alpha Encoding
Alpha now carries `energy * 1.5 + bloom + history.a * 0.5` where `bloom = max(0, energy - 0.7) * 3.0`. This encodes both scene presence and HDR bloom weight for downstream compositing. Depth is written as `1.0 - energy * 0.8`.

## Line Count
163 lines (target ~170 ±20%).
