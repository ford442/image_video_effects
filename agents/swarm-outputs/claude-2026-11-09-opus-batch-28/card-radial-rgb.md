# radial-rgb (2nd pass)
Existing: radial chromatic (R/B k1), mustache k3.
1. **Held-pointer decentred optical axis** — while held, lens centre (distortion, fringes, half the vignette) moves to the pointer; idle = frame centre.
2. **Tangential astigmatism smear** — 3-tap blur along the circumferential direction, ∝ r²·dispersion, bass widens.
3. **Cat's-eye mechanical vignette** — almond-shaped off-axis pupil clipping (30% mix), stronger with |k1|.
Rescue: smoothVignette's softEdge factor blacked out the frame centre (centre pixel 0). Dead `mouseDir` removed.
