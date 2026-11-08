SHADER: fabric-step (2nd pass)
IDENTITY: Verlet cloth draped over the image, tearable
KEEP VERBATIM: sim, constraints, pin, weave, params, A packing (raw sim pos.xy, prevPos.xy)
ADD: 3. compression wrinkle ridges — stretch-only solver lets cloth buckle; squeezed regions get fine ridges across the squeeze axis
     4. Kajiya thread sheen — anisotropic highlight where deformed warp threads turn perpendicular to the key light (mids); flat cloth stays matte
     5. torn-edge fray tufts — torn pixels show short bright hashed thread strands crossing the tear
PLUMBING: shader had no plasmaBuffer read despite audio-reactive tag — bass now gusts the wind, mids the sheen.
RESCUE: idle cursor (parked at centre) pushed permanently → hole; hover now 0.15x, held 1x. Vertical constraints used x texel rest length (wrong on non-square) → restLenY.
A PACKING: unchanged
