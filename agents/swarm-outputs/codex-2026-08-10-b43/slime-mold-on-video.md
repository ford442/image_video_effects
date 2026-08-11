# slime-mold-on-video — Batch 43 #377

- Replaced every filtering rgba32float history read with clamped `textureLoad` state access.
- Added packed-velocity trail advection, traveling chemotactic pulse packets, and bounded click food fronts.
- Preserved A simulation packing as `(trail, food, encodedVelocity.x, encodedVelocity.y)`; B remains unused.
- Preserved Trail Follow, Trail Decay, Food Gain, and Glow exactly.
