# gen-prismatic-quantum-glass-chrysalis-engine (2nd pass, rescue)
Bug at HEAD: fully black. The camera pitch was mouse.y*PI, so the idle cursor (0.5) put the camera on the pole: cross(cw, up)=0, NaN rays. Fixed by pitching (0.5-mouse.y)*1.3 and yawing (mouse.x-0.5)*2PI. The image was also upside down, so uv.y is flipped. Plasma and cyan core glows were trimmed (x0.45 / 2.0→0.6) because they washed to white once the shell was visible.
Ideas: helical emergence fissure (bass widens it); dichroic aurora backdrop (its hue split follows Chromatic Dispersion, and it gives the miss region some alpha); crack-junction sparks (Voronoi F2-F1 junctions blink on treble).
Stats (256px, t=3, defaults 1.5,1,0.5,0.2): before meanL 0, meanA 1 (NaN) → after meanL 0.40, meanA 0.24.
