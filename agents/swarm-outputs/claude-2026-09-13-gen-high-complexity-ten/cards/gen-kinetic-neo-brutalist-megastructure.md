# Idea Card — gen-kinetic-neo-brutalist-megastructure

```
SHADER: gen-kinetic-neo-brutalist-megastructure
IDENTITY: an endless raymarched grid of swaying concrete blocks (four compound massing types) flown through by a forward camera, lit with GGX concrete, cyan neon server-core buildings pulsing to bass, a mouse repulsion field, fog and colour-history feedback.
KEEP VERBATIM: 4.0 domain repetition, four btype massing compositions (box / slotted box / smin cap / smin side mass), hash-driven height/roughness/neon, GGX+Schlick+Smith shading, neon pulse term, volumetricFog, 100-step march to 50, mouse repulsion push, C colour feedback mix, CA offset, ACES, slider roles (x Block Density, y Repulsion Radius, z Neon Intensity, w Travel Speed), saved updatedParams.
EXISTING IDEAS: none named (June stack was plumbing chunks only).
ADD:
  1. Grinding interlock — the secondary masses (slot cutter, cap slab, side mass) slide along their joint on a per-building phase so blocks visibly grind in and out of each other, with a hot friction seam where the two masses meet; bass nudges the stroke. Native because the description is "colossal blocks that grind and interlock" and these compound SDFs are the interlocks.
  2. Server-core slits — neon buildings get board-form horizontal slits on their vertical faces through which the hidden cyan core shows, with rack LEDs blinking along each slit on continuous per-LED phases (treble-lifted). Native because the description promises "server cores hidden within" and the neon flag already marks them.
FORBID: spring cursor, click ripples, IQ palettes, conveyors, holographic scanlines, replacing the massing types or the camera flight, extraBuffer, dataTextureB.
A PACKING: ACES display RGBA (unchanged); C read via exact textureLoad as colour history. Floor fix: alpha was the material id (0..11) — replaced with coverage/neon semantic alpha; depth now from hit distance.
```
