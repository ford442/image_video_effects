SHADER: gen-neon-stellated-octahedron
IDENTITY: neon star tetrahedron (stellated octahedron) — two interpenetrating tetrahedra, rainbow edges, facet-plane glow, intersection ridge, vertex spike glow, 6-fold kaleidoscope, mouse yaw/pitch.
KEEP VERBATIM: stellatedOctaSDF (edges/faces/ridge), neon(), rotX/rotY, kaleidoscope fold, edge/facet/ridge/spike colour terms, slider mappings, 4% feedback from C.
ADD (2 native ideas):
  1. Tomographic section through the true solid compound (each tetra = intersection of its 4 face half-spaces): slice plane sweeps along the view axis (tip triangles -> hexagram), the shared regular-octahedron core (max(tA,tB)) is lit apart from the 8 stellation spikes, tetra A warm / tetra B cool with thickness shading; click ripples dent the slice plane locally, mouse-held locks the slice at the central hexagram.
  2. Kepler cube hull: the 8 star tips are the vertices of a cube — its 12-edge frame is drawn faintly, with corner beacons coloured by bipartite parity (sign of x*y*z: tetra A tip vs tetra B tip), treble-pulsed.
FLOOR FIXES: slice plane was fixed at z=1.5 outside the star (vertex radius <= 1.56), so edge/ridge terms were effectively dead -> sweeping slice makes them visible; dataTextureA held pre-ACES HDR -> now the same final ACES RGBA as writeTexture; C load coords clamped; plasmaBuffer audio clamped 0..1; click ripples + mouse-held added (were missing); header + uniform slider comments. JSON unchanged (features/params already compliant; snake_case param ids kept).
FORBID: extraBuffer use, dataTextureB writes, renaming param ids, replacing the polyhedron motif.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live
