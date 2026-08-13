# `neon-pulse-dissolve`

- Corrected audio reads to use `plasmaBuffer[0]` instead of the reserved extra buffer.
- Added smooth advected luminous noise, a scan runner, held-pointer energy, and capped click fronts.
- Preserved A display history and the existing B diagnostic packing `(edge, bass, mid, treble)`.
