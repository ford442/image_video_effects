# BRIEFS — fork B (gen-grok41-plasma, gen-chromodynamic-plasma-collider)

## gen-grok41-plasma (Spherical Harmonics Plasma) — 3rd pass
Existing ideas (KEEP): zonal jets; storm-eye vortex; polar hood; belt boundaries.

HEAD render (192, defaults 0.55,0.5,0.4,0, SRC=img):
| case | meanL | stdL | look |
|---|---|---|---|
| idle t=1.5 | 0.475 | 0.168 | planet left of centre, banded |
| held 0.4,0.6 | 0.481 | 0.169 | same |
| audio .8/.5/.9 | 0.474 | 0.167 | same |
| idle T0=25 | 0.408 | 0.177 | **NO PLANET — only source image** |

Rescues (mandatory, not ideas):
- R1 camera orbit: `ro` is orbited by rotTime but `rd` is not → the globe slides off frame and is behind the camera for about half of the ~84 s orbit (confirmed: no planet at t=10/25). Fix: rotate rd with the same orbit chain.
- R2 `plasmaBuffer[1..8]` per-bin FFT is out of range (COMMON rule 6) → use plasmaBuffer[0].xyz bands.
- R3 click lightning scaled by `ripple.w` (always 0) → dead; use unit strength.
- R4 `pow(theta-1.15, 2)`, `pow(sin(..),2)` negative bases → x*x.

§12.1 interrogation: tactic 1 (what makes a gas giant read physically): moons + shear instabilities; tactic 2 (existing nouns): jets, belts, storm eye, limb; tactic 3 (what the sliders drive): l2 drives jet strength; tactic 6 (what's missing at the deletion test): there is no object in the system other than the globe, and belt edges are perfectly straight lines.

Ideas (native):
1. **Moon-transit shadow** — a Galilean-moon umbra + penumbra disc crosses the disc along a tilted track, eclipsing the lit bands (dark ink dot, classic Jupiter photo).
2. **Kelvin–Helmholtz billows** — belt edges (Idea 4 zero-crossings) are curled by a longitude wave whose amplitude rises with the l2 jet shear, so edges scallop and roll instead of being straight rules.

## gen-chromodynamic-plasma-collider — 2nd pass
Existing ideas (KEEP): bunch-crossing bursts; beam steering + betatron wobble; momentum dispersion; synchrotron sideband comb; Cherenkov wake cones.

HEAD render (192, 15,5,1,0.5): idle meanL 0.261 stdL 0.055; held 0.260/0.054; audio 0.327/0.076. Tunnel, rings, magenta ring flashes all render; no NaN.
Rescue: extraBuffer[133..138] mouse spring never persists (re-uploaded zero) → it is a no-op that also writes extraBuffer racily; replace with raw mouse (same picture). Not an idea.

Ideas:
1. **Airy-disc aperture diffraction (§12.2 Airy disc)** — the beam spot threaded through each ring aperture gets the (2J1(x)/x)² diffraction sidelobes of a circular aperture instead of a plain Gaussian, so concentric faint rings surround the beam at every ring plane.
2. **Synchrotron radiation fan on the sleeve (native)** — where the warped tunnel bends, the beam radiates tangentially onto the outer wall of the bend: a warm-white stripe painted on the obsidian sleeve on the side the bend points to, strength ∝ local curvature (tunnelSlope).
