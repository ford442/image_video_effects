SHADER: gen-sierpinski-tetrahedron (2nd pass + rescue)
IDENTITY: Sierpinski tetrahedron seen as a 2D cut, multi-orbit-trap (vertex/edge/shell) jewel colouring with metallic sheen
HEAD BUG: sample plane sat at z=2.5, outside the unit tetra, and the forward chaos-game map converged everywhere → flat washed lavender disc (shell trap only). extraBuffer[133..138] spring/click state never persisted (zeroed each frame; [138] also written by every pixel).
KEEP VERBATIM: vertex/edge/shell traps, jewelColor, shelving bands, edge-current, fresnel, CA, params, A packing (minTrap, trapIdx, density, alpha)
RESCUE: inverse IFS (p = 2p − V_nearest) with escape so holes exist; plane moved through the body; shell trap weight 0.25→4 so it no longer floods.
ADD: 3. sweeping section plane — slice depth drifts (sin t·0.17) and bass shoves it, so cross-section triangles bloom/collapse
     4. punched-hole hierarchy — escaped pixels darken by the level that removed them (big voids black, fine holes dust)
     5. polished cut-face glints — diagonal specular streak sweeps the solid cut faces (mids)
FORBID: ripple rings, palettes, spring cursor
Follow-up: alpha mean low (~0.03, was 0.13) — density·recursion/10 formula unchanged; shell circles still visible as bubbles.
