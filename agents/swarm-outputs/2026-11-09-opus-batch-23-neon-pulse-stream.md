# neon-pulse-stream — opus/batch-23
Keep: five-tube bundle, Fresnel rims, packets, pointer attractor, click fronts, afterglow.
Rescue: per-tube band read plasmaBuffer[1..8], which is never uploaded, so band was always 0. Tubes now take a quadratic-Bezier weighting of bass/mid/treble across the bundle.
- gas-column banding: standing bright/dark bands along each core, nudged forward by passing packets.
- comet-tail packets: sharp head plus an exponential tail behind the direction of travel.
- junction arcs: where cores overlap (coreSum - coreMax), a white-hot arc flickers at 24 Hz; bass boosts it.
