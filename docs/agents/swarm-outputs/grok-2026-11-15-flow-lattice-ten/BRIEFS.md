# Idea Cards — Grok (flow-lattice ten, 2026-11-15)

Written before the WGSL edits. Ten shaders around 108–122 lines. Each card adds **two or three** ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, ripple stamp, or new IQ palette.

Formula rule: a §12.2 row is newly applied on at most one file here.

- Fresnel–Schlick (§12.2F) is new on `sphere-projection` only.
- Fold-count material (§12.2E) is new on `gen-aetheric-tachyon-lattice` only.
- No Cauchy, thin-film, cos⁴, step-count AO, grain, or halation.

Prelude migration on `pixel-wind-chimes`, `hypnotic-spiral`, `cellular-automata-3d`, `ion-stream`, `sphere-projection`, and `psychedelic-noise-flow` is infrastructure (`migrate_to_prelude.py`). It is not an idea and does not by itself bump `Upgraded:`.

```
SHADER: quantum-field-visualizer
IDENTITY (one sentence): two Gaussian wave packets through a two-slit barrier, phase as hue and |ψ|² as brightness, collapsing only while the pointer is held.
KEEP VERBATIM: slits at x = ±0.12, barrier wall with gaps at y = ±0.12, real/imag pair, phase hue, held-only collapse disk, photo mix, params Observation Field / Fluctuation Speed / Energy Level / Uncertainty
MECHANISM INTERROGATION:
  tactic 2: a finite slit diffracts; the interference sits inside a single-slit lobe, and a traveling crest leaves a wake behind it
  tactic 3: k0 is only the carrier; it never sets an angular envelope. C is written and never read
  tactic 6: C is display colour. One step upstream of the +x travel is the wake
ADD:
  1. Finite-slit diffraction envelope — sinc² of k0·y multiplies |ψ|² before the collapse, so the fringes sit in a lobe. Energy already is k0, so higher energy tightens the lobe
  2. Upstream probability wake — exact C, a few pixels toward −x, mixed by the enveloped density, so crests leave a short trail
FORBID on this file: a new palette, a spring, replacing the two packets with a raymarched field
A PACKING: ACES display RGBA (unchanged). C is that display
```

```
SHADER: pixel-wind-chimes
IDENTITY (one sentence): the photo cut into vertical strips that hang from the top and swing in the wind, pushed aside by the pointer.
KEEP VERBATIM: strip count, sway, wind speed, gap, five-neighbor search, rigid rotation about the top, closest-Z winner, hinge specular, params Strip Count / Sway Amount / Wind Speed / Gap Size
MECHANISM INTERROGATION:
  tactic 2: a chime hangs from a cord, and the free end moves farther than the hinge
  tactic 3: the winning strip's angle and local y are computed and then discarded
  tactic 6: C is display colour and unread. A step along the swing is motion blur at the free end
ADD:
  1. Suspension cord — a hanger line and a short string in the gap above each strip, hidden where the tube covers them
  2. Free-end swing smear — exact C offset by angular velocity times distance from the hinge, so the bottom streaks and the pivot stays sharp. Wind Speed already sets that velocity
FORBID on this file: a spring, click shockwaves, an IQ palette, a particle clapper system
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: interactive-pcb-traces
IDENTITY (one sentence): a green board of Manhattan pad-to-edge routes, vias, signal packets, pointer injection, and click fronts, with a phosphor afterglow.
KEEP VERBATIM: cell hash, horizontal-first elbow, branch stub, via ring and drill, packet phase along the route, hover / held / click injection, copper and solder colours, history glow, params Grid Scale / Pulse Speed / Glow / Background
MECHANISM INTERROGATION:
  tactic 2: a trace flares into the pad (teardrop) and the 90° corner is mitered
  tactic 3: pad distance and the elbow point are computed and the copper stays a constant width with a sharp corner
  tactic 6: C stays the phosphor mix already in the file
ADD:
  1. Pad teardrop — the existing trace widens along the pad leg as it meets the via
  2. Elbow chamfer — a short 45° segment replaces the sharp corner; the branch meets the chamfer midpoint. The route is still the same Manhattan net
FORBID on this file: a new spring, silkscreen text, a second board palette, replacing Manhattan with curved traces
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: hypnotic-spiral
IDENTITY (one sentence): a breathing multi-arm spiral, warped by the pointer, reversed while held, with click twist and the photo riding the arm tangent.
KEEP VERBATIM: arms, rotation speed, color cycle, warp, log/Archimedean radius mix, secondary arm, click twist, tangent photo ride, params Arms / Rotation Speed / Color Cycle / Warp
MECHANISM INTERROGATION:
  tactic 2: a coil has a lit leading edge and a dark trailing edge
  tactic 3: the arm phase is only a sine; its cosine is the side of the crest
  tactic 6: C is display and unread. A step against the spin is the afterimage
ADD:
  1. Leading-edge bevel — the cosine of the existing arm phase lights one side of the crest and darkens the other
  2. Spin afterimage — exact C, a short step against the rotation tangent, amount from Rotation Speed, gated by the arm mask
FORBID on this file: a new spring, a second palette, replacing the spiral with a tunnel
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: cellular-automata-3d
IDENTITY (one sentence): a raymarched cube of 3D cellular automata, birth and survival from a 26-neighbor count, with a sprung camera, click birth shocks, and a persisted glow.
KEEP VERBATIM: born 4–6 / survive 5–7 with shock, 72-step march, existing spring in extraBuffer[133..138], click shock, hash hue, history persistence, params Evolution Speed / Initial Density / Color Cycling / Camera Rotation
MECHANISM INTERROGATION:
  tactic 2: a blob has a bright shell and a dim core, and a cell that just flipped on flashes
  tactic 3: the neighbor sum is collapsed to a boolean; the lattice coordinate is only a hash key
  tactic 6: C stays display persistence. Do not pack the neighbor count into A
ADD:
  1. Shell glow — fewer live neighbors emit more, so the surface of a cluster is brighter than the packed interior
  2. Birth flash — a cell that is born this epoch (not a survivor) adds a white spike
  3. Voxel edge — the same 14³ lattice darkens where a cube face is, so the volume reads as cells
FORBID on this file: a new rule family, a new spring, an IQ palette replacing the hash hue, Gray-Scott
A PACKING: ACES display RGBA (unchanged). C is that display
```

```
SHADER: gen-aetheric-tachyon-lattice
IDENTITY (one sentence): a raymarched KIFS lattice of three orthogonal tubes, with a tachyon sine running along them and a held pointer warp.
KEEP VERBATIM: six abs-and-rotate folds, tube distances on xy/xz/yz, tachyon product of sines, cyan/magenta/blue bands, held ray warp, bass on emission, params Fold Count / Tachyon Speed / Lattice Thickness
MECHANISM INTERROGATION:
  tactic 2: a lattice glows at the joints, and deeper folds look more worked
  tactic 3: each abs() sign is thrown away; the three tube distances collapse to a min
  tactic 6: C is not read. A was zeros. It becomes ACES display RGBA
ADD:
  1. Fold-count material — reflections already taken heat the emission and dull the diffuse (§12.2E)
  2. Junction nodes — where the two nearest tubes are both close, a white-hot vertex
FORBID on this file: a new primitive, a liquid solver, a spring, an oil-slick, a fourth slider
A PACKING: ACES display RGBA. C is not read. The old zero store in A was unused. B stays the zero clear this file already wrote
```

```
SHADER: ion-stream
IDENTITY (one sentence): helical ion lanes in a curl flow, split by charge around the cursor magnet, with packets, click fronts, and a display wake.
KEEP VERBATIM: value-noise curl, magnetic bend, lane helix, charge split, cyclotron tightening, packets, click fronts, exact-C wake, params Stream Speed / Curl Strength / Stream Density / Ion Color
MECHANISM INTERROGATION:
  tactic 2: a beam's radius breathes along its length (sausage), and ions pile up where the field is strongest
  tactic 3: fieldB is a bend and a cyclotron factor; it does not bunch the packets
  tactic 6: C stays the display wake already mixed in
ADD:
  1. Sausage pinch — the existing helix amplitude and core width breathe along y, rate from Stream Speed, depth from Stream Density
  2. Magnet pile-up — packets tighten and the glow rises with the existing fieldB, so the beam stalls at the cursor
FORBID on this file: a new charge model, a spring, a second curl, replacing the lanes with particles
A PACKING: ACES display RGBA. C is that display. Floor adds ACES; the September tag claimed it and the shader clamped instead
```

```
SHADER: sphere-projection
IDENTITY (one sentence): an equirectangular photo on a ray-traced sphere, with meridians, parallels, pointer spin, held zoom, and click shells.
KEEP VERBATIM: sphere quadratic, yaw/pitch from the pointer, held zoom, Lambert from Lighting and Ambient, meridians and parallels, click shells, rainbow slick, history mix, params Sphere Zoom / Spin Speed / Lighting / Ambient Light
MECHANISM INTERROGATION:
  tactic 2: a globe is bright at the limb and throws a specular highlight from the key light
  tactic 3: the hit normal and the ray are computed for the map and then used only as Lambert
  tactic 6: C stays the display mix already in the file
ADD:
  1. Limb Fresnel — grazing ndotv adds a cool rim (§12.2F). Lighting's Lambert term is unchanged
  2. Directional glint — a tight Blinn highlight from the existing lightDir, scaled by Lighting so that slider still means the key
FORBID on this file: a new spring, a second palette on top of the slick, replacing the sphere with a cube
A PACKING: ACES display RGBA. C is that display. Floor adds ACES; the August tag claimed it and the shader stored linear colour
```

```
SHADER: gen-hypnotic-vortex-tunnel
IDENTITY (one sentence): nested spinning hoops down a log-z vortex, contra-rotating by layer, with seam walls, a sheared horizon, and an accretion rim.
KEEP VERBATIM: nRings layers, contra-spin, log z, seam walls, horizon shear, accretion disk, iris, outer fade, params Rings / Rotation Speed / Zoom / Distortion
MECHANISM INTERROGATION:
  tactic 2: hoops have gaps between them, and forward flight leaves a radial streak
  tactic 3: the ring sine is a soft mask with no gap; z's time term is a speed that never becomes motion blur
  tactic 6: C is display and unread. A step inward along the existing view ray is the flight
ADD:
  1. Hoop gap — the existing ring sine is mixed toward a steeper body so each hoop has a dark gap
  2. Inward flight streak — exact C, a short step toward the bore, amount from the z speed already in zBase (0.5·(1+bass)), held off inside the iris
FORBID on this file: a kaleidoscope fold, a spring, cos⁴ (that was a different tunnel), a new palette
A PACKING: ACES display RGBA (unchanged). C is that display
```

```
SHADER: psychedelic-noise-flow
IDENTITY (one sentence): the photo pulled apart by three noise currents, with a filament, a held vortex, and click fronts.
KEEP VERBATIM: gradient noise, per-channel domain warp, Color Shift mix of the offsets, filament sine, spectral add, held vortex, click fronts, params Flow Speed / Noise Scale / Distortion / Color Shift
MECHANISM INTERROGATION:
  tactic 2: dye follows the filament, and a current leaves a trail
  tactic 3: the filament is a scalar on top of a displacement that ignores its direction
  tactic 6: C is display and unread. A step back along the displacement is the trail
ADD:
  1. Filament-aligned smear — a finite difference of the existing n_r gives a tangent; the photo offset gains a slide along that tangent, stronger where the filament is bright
  2. Current trail — exact C, upstream of the red displacement, length from Flow Speed, mix from Distortion
FORBID on this file: a new spring, replacing the noise with a fluid solver, an IQ palette as the picture
A PACKING: ACES display RGBA. C is that display. Floor adds ACES; the May tag claimed it and the shader stored the raw sum
```
