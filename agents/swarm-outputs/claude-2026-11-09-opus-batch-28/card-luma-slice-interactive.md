# luma-slice-interactive (2nd pass)
Existing: luma parallax layers; cut-face bevel + cast shadow.
1. Ragged tear seams — per-3px-column hashed seam height (±0.175 slice), scaled by intensity.
2. Velocity smear — 4-tap streak back along d(offset)/dt (1/20 s finite difference), clamped 0.04.
Rescues: none needed (HEAD renders correctly).
