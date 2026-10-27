# Idea Cards — Grok (`cursor/batch-13`, 2026-10-27)

Written before WGSL edits. Twelve mouse-driven force shaders: shockwaves, elastic surfaces, magnetism, gravity, ripples. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

Formula rule: a §12.2 row is used on at most one file here.

Eight pasted headers are migrated to `#include "_prelude.wgsl"` as infrastructure (`sonic-boom`, `elastic-strip`, `elastic-surface`, `magnetic-edge`, `magnetic-rgb`, `slinky-distort`, `mouse-magnetic-pixel-sand`, `quantized-ripples`). `luma-force`, `pixel-repel`, `neon-ripple-split`, and `mouse-gravity` already include the prelude. That swap is not the upgrade.

`magnetic-rgb`, `slinky-distort`, `mouse-magnetic-pixel-sand`, and `quantized-ripples` are tagged or described as display-ready but have no ACES. ACES on the display write is floor. Stored fields stay un-tonemapped where C is a sim or an echo. That is not one of the two ideas.

`sonic-boom` reads `plasmaBuffer[2/4/6]` and `elastic-strip` reads `plasmaBuffer[band+1]`. Those become phases of `plasmaBuffer[0]`. Dead-bin fixes, not ideas.

---

## sonic-boom

IDENTITY: circular Mach rings around a sprung shock center, with shock diamonds, condensation fog, Doppler chroma, and click booms.
KEEP VERBATIM: Ring Radius / Ring Width / Distortion / Chrom. Split; PHI ring stack; spring in `extraBuffer[133..137]`; click bursts; diamonds; condensation; Doppler split. A stays ACES display RGBA. C.r stays the ring tail.
MECHANISM:
- tactic 2: a real boom is an N-wave (sharp compression, long rarefaction), and it is loud behind the aircraft.
- tactic 3: `d0` is a signed distance to the primary ring and is only squared. `sVel` is computed for the spring and then thrown away.
- tactic 6: the tail stays C.r. Neither idea stores a new channel.
ADD:
  1. N-wave — the primary ring is steep outside the radius and soft inside, and that shoulder pulls instead of pushes. Inner PHI echoes stay symmetric. Distortion still sets the amplitude.
  2. Mach crescent — while the spring is moving, the stack is loud in the wake and quiet ahead. A still cursor keeps a round ring. Radius still sets the ring.
FORBID: replacing the rings with a geometric cone, a new spring, an IQ palette, storing velocity in A.
A PACKING: ACES display RGBA. C.r is the previous display red, used as the ring tail (exact load).
FORMULA: none.

## elastic-strip

IDENTITY: vertical or horizontal rubber strips that stretch toward the pointer, with bevel ribs, pluck packets, and soap-film colour from the stretch.
KEEP VERBATIM: Strip Density / Stretch Strength / Influence Radius / Direction (V/H); axis swap; damped oscillator; nested bevel; soap film; held drag; click pluck packets. A stays ACES display RGBA.
MECHANISM:
- tactic 2: a plucked strip rings at 2f and 3f, and a real rubber strip goes pale when it thins.
- tactic 3: `mouseDisplace` is the pluck point along the strip and only shifts the whole cell. `totalShift` tints the film and never bleaches it.
- tactic 6: C is the colour trail. Neither idea repacks A.
ADD:
  1. String partials — second and third harmonics of the existing oscillator, weaker by 1/n, with a node at the pointer's position along the strip. A center pluck kills the even partial.
  2. Stretch bleach — where `|totalShift|` is high the soap desaturates toward luma. Quiet strips keep the film. Strength still sets how far the strip moves.
FORBID: Poisson necking (the membrane file owns that), a new spring, an IQ palette, Schmitt state.
A PACKING: ACES display RGBA (colour trail in C).
FORMULA: none.

## elastic-surface

IDENTITY: a spring-mass membrane. Displacement and velocity live in A. Tension, a mouse push or pull, and click ripples move it. Poisson squeeze is already on the sample.
KEEP VERBATIM: Elasticity / Surface Tension / Wave Speed / Depth Influence; Verlet step; 4-neighbour Laplacian; mouse push/pull; ripple impulses; Poisson offset. A stays raw `(disp.xy, vel.xy)`.
MECHANISM:
- tactic 1: the Laplacian is tension only. A sheet also has bending stiffness, which the wide neighbour difference can see.
- tactic 2: rubber wrinkles where it is compressed. The neighbour divergence is computed and thrown away.
- tactic 6: both ideas use the disp field already stored. A is not repacked.
ADD:
  1. Plate bending — a 2-texel Laplacian. Short waves, present in the fine Laplacian and missing from the wide one, snap back. Wave Speed still scales the step.
  2. Compression wrinkles — where neighbour divergence is negative, a fine ridge runs along the displacement tangent and catches the existing specular.
FORBID: a Gray-Scott field, promoting A to display colour, an IQ palette, a spring.
A PACKING: raw `(disp.xy, vel.xy)`. ACES on the display write only.
FORMULA: none.

## luma-force

IDENTITY: the photo creeps along its own luma gradient (bright repels, dark attracts), with curl noise, a cursor vortex bent onto isolines, and a fading displacement memory.
KEEP VERBATIM: Force Magnitude / Vortex Radius / Curl Noise / Luma Weight; 5-tap gradient; curl; isoline vortex; 5-tap memory; spectral fringe. A stays raw `(mem.xy, |drive|, luma contrast)`.
MECHANISM:
- tactic 2: a contour should hold the last push. Flat regions should forget it.
- tactic 4: `(luma - 0.3)` is linear, so a clipped highlight flings as hard as a midtone.
- tactic 6: memory and contrast are already in A. Neither idea adds a channel.
ADD:
  1. Contour adhesion — memory accepts new drive slowly on a strong gradient and forgets it on flat luma. Force Magnitude still scales the drive.
  2. Soft-knee luma — the drive compresses above mid-grey so blown highlights do not throw the picture off the frame. Dark attraction is unchanged.
FORBID: a pile-up rim (pixel-repel owns divergence), a spring, an IQ palette, writing display colour into A.
A PACKING: raw `(memDisp.xy, |drive|, luma contrast)`. ACES on display only.
FORMULA: none.

## pixel-repel

IDENTITY: four orbiting superellipse lobes push the photo off the cursor, with a spectral fringe, a pile-up rim, and a drag wake.
KEEP VERBATIM: Radius / Strength / Aberration / Smoothing; four lobes; `sellipse`; 7-tap spectral fringe; divergence crest; pointer-velocity wake. A texels `(0,0)` and `(1,0)` stay the pointer state. Other texels stay ACES display RGBA.
MECHANISM:
- tactic 4: Smoothing already softens the falloff. The sample itself is still a continuous warp, so a hard repel does not move pixels.
- tactic 8: the crest brightens where pixels bunch. Where they spread, the same divergence is thrown away.
- tactic 6: no new state. Both ideas are display-side.
ADD:
  1. Pixel snap — the spectral taps quantize to a cell that grows with Strength. Smoothing blends that snap back to the continuous warp and still sets the wake.
  2. Rarefaction shadow — positive divergence darkens the photo. The existing crest still brightens the pile.
FORBID: a new solver, a spring, an IQ palette, repacking the pointer texels.
A PACKING: ACES display RGBA, except texel `(0,0)` = `(mouse, time, valid)` and texel `(1,0)` = smoothed pointer velocity.
FORMULA: none.

## neon-ripple-split

IDENTITY: a horizontal sine shear, neon on the crests, a pink seam on the zero crossings, a held gravity well, and click ripples.
KEEP VERBATIM: shader mapping x = shear, y = ripple speed, z = glow, w = frequency (the `params` labels differ and stay byte-exact); crest RGB split; seam; gravity well; bass envelope at A `(0,0)` with sentinel `-7`. Other texels stay linear pre-ACES colour.
MECHANISM:
- tactic 2: a ripple arrives as a packet. This shear fills the frame.
- tactic 8: the neon is added on top of the photo, so the tube does not spend the light under it.
- tactic 6: A.a at `(0,0)` stays the bass envelope. Neither idea stores new state.
ADD:
  1. Wave packets — a slower envelope on the existing carrier, so the sine travels in groups. Frequency still sets the carrier. A faint residual keeps the shear visible between packets.
  2. Neon spends the photo — under the seam and the crest glow the picture desaturates and darkens by the glow, then the tube is added back.
FORBID: a second shear axis, a spring, an IQ palette, deep-water dispersion (the haptic field owns it).
A PACKING: linear pre-ACES RGBA, except `(0,0)` = `(bass env, 0, 0, sentinel)`. ACES on the display write only.
FORMULA: none.

## mouse-gravity

IDENTITY: a gravitational lens on the cursor. It magnifies, inverts, swirls, stretches, fringes, and shows a Doppler photon ring. Clicks are secondary wells.
KEEP VERBATIM: Gravity Strength / Event Radius / Chrom. Aberration / Core Darkness; lens factor `1 - strength * exp(-d/r)`; frame-drag swirl; tidal stretch; Doppler ring; click pulls. Texel `(0,0)` and `(1,0)` stay the pointer state.
MECHANISM:
- tactic 2: when the lens inverts, the critical curve is an Einstein ring. The factor crosses zero and nothing is drawn there.
- tactic 6: C is the previous display everywhere except the two state texels. Light near a mass should arrive late.
- tactic 3: `distortion` is used as a UV scale and its zero is thrown away.
ADD:
  1. Einstein ring — a thin caustic of the lensed photo where the magnification factor crosses zero, and only once that curve has cleared the dark core. Strength still sets whether the image inverts.
  2. Shapiro delay — inside the well, the display mixes a little of the previous frame. The two state texels are not read as colour.
FORBID: a photon orbit at 1.5 radii (black-hole owns that), a new spring, an IQ palette, repacking the velocity texels.
A PACKING: ACES display RGBA, except the two pointer-state texels.
FORMULA: none.

## magnetic-edge

IDENTITY: photo edges are pulled anisotropically toward a sprung magnetic pointer, with spectral flux lines and click shocks.
KEEP VERBATIM: Pull Strength / Radius / Edge Low / Glow Amount; luma gradient; normal/tangent mix; spring in `extraBuffer[133..138]`; flux lines; signed click shock. A stays ACES display RGBA.
MECHANISM:
- tactic 2: filings trail a moving magnet. The spring velocity is stored and only used to offset the history sample.
- tactic 6: C.a is last frame's edge mask. When the magnet leaves, that mask is thrown away.
- tactic 3: `springVel` is a direction. The pull still uses only the edge normal.
ADD:
  1. Drag-aligned field — while the spring is moving, the pull bends toward that velocity, and only on an edge. A still magnet keeps the edge-aligned field.
  2. Remanence — where last frame's alpha was high and the magnet has left, more of the previous picture remains. Glow Amount still sets the live flux.
FORBID: a second magnet, an IQ palette, a dipole solver, rewriting the shock into an unsigned ring.
A PACKING: ACES display RGBA (exact C history).
FORMULA: none.

## magnetic-rgb

IDENTITY: red is pulled in, green swirls, blue is pushed out, and iron filings streak through the field.
KEEP VERBATIM: Strength / Radius / Swirl / Chaos; three channel offsets; bass surge; divergence alpha; filing noise. C is unread.
MECHANISM:
- tactic 2: classroom filings loop from one pole to the other. These streaks follow a monopole blend.
- tactic 3: `field` is a scalar falloff. The line spacing ignores it, so the pile is uniform.
- tactic 6: no history. Both ideas are display-side.
ADD:
  1. Dipole return — filings follow a short bar field, leaving one side of the cursor and entering the other. The RGB offsets stay attract / swirl / repel.
  2. Filing density tracks `|B|` — line spacing tightens where the field is strong and opens at the radius edge. Strength still scales the offsets.
FORBID: moving the RGB offsets onto the dipole, a spring, an IQ palette, a residue field (the sand file owns settling).
A PACKING: ACES display RGBA. C unread.
FORMULA: none.

## slinky-distort

IDENTITY: a spiral coil of the photo around the cursor, with torsion, a treble compression pulse, and a lagged echo from C.
KEEP VERBATIM: shader roles x = coils, y = amplitude, z = depth weight, w = tightness (JSON labels differ and stay byte-exact); spiral phase; radial plus tangent displacement; compression pulse; lagged echo; advanced alpha.
MECHANISM:
- tactic 2: a slinky in the hand is tight at the grip and loose at the far end, and the wire is a cylinder.
- tactic 3: `spiralPhase` colours the coil and lights the crest. It does not shade the wire. `dist` scales one frequency everywhere.
- tactic 6: the echo reads C at the lagged UV. The phase change has to be in that lagged phase too, or the echo shears off the coil.
ADD:
  1. Hand-tight wraps — coil frequency rises toward the cursor and loosens with distance. Tightness still scales the whole spring. The echo uses the same local frequency.
  2. Wire cylinder — one side of each wrap darkens. The existing crest highlight stays the bright side.
FORBID: turning this into horizontal slices, a spring in extraBuffer, an IQ palette, ACES inside the echo history.
A PACKING: linear display RGBA in A (the echo). ACES on the display write only.
FORMULA: none.

## mouse-magnetic-pixel-sand

IDENTITY: bright pixels are iron filings. The cursor attracts or repels them, ripples kick them, chains link them, and a residue settles in A.
KEEP VERBATIM: Magnet Strength / Field Range / Polarity / Grain Size; luma susceptibility; radial displacement; alternating ripple polarity; chain taps; residue decay. A stays `(residue rgb, settled)`.
MECHANISM:
- tactic 2: sand does not creep in a weak field. It sits until the pull exceeds friction.
- tactic 5: real filings are dashed chains, not a continuous smear. The chain taps average colour and never cut a gap.
- tactic 6: residue stays in A. Friction only gates the live displacement.
ADD:
  1. Static friction — the main pull and the grain jitter are zero until `|field| * falloff` clears a small threshold. Ripples can still kick a stuck grain. Strength still scales the pull above that threshold.
  2. Linked dashes — a periodic gap along the field, pitched by Grain Size, darkens between links. The gap only appears where filings are gathered.
FORBID: a dipole solver (magnetic-rgb owns the return path), a spring, an IQ palette, ACES on the stored residue.
A PACKING: raw `(residue rgb, settled)`. ACES on the display write only.
FORMULA: none.

## quantized-ripples

IDENTITY: click ripples, or a cursor ripple when nothing has been clicked, displace the photo and posterize it. Three decay shapes and a roughness grain stay.
KEEP VERBATIM: Surface Stiffness / Damping Ratio / Touch Texture / Decay Mode; `decayProfile` linear / exponential / critical; click-to-click velocity; level quantization; touch sine. A stays raw `(effectStrength, shimmer, roughness, alpha)`.
MECHANISM:
- tactic 2: a ripple on a deep surface breaks into a train. Every harmonic here shares one speed.
- tactic 4: the level count is one number for the whole frame. The crest should be the chunky part.
- tactic 6: C is unread and stays unread. Both ideas are in the wave and the posterizer.
ADD:
  1. Deep-water dispersion (§12.2D) — a second harmonic at twice the stiffness frequency travels at `1/sqrt(2)` the phase speed, so each ring becomes a short train. Stiffness still sets the fundamental.
  2. Crest posterization — the level count drops where `|interference|` peaks. Between rings the base count, still set by stiffness, remains.
FORBID: a height-field solver, a spring, an IQ palette, a shear packet (neon-ripple-split owns that), audio (the definition does not claim it).
A PACKING: raw `(effectStrength, shimmer, roughness, alpha)`. C unread. ACES on the display write only.
FORMULA: deep-water dispersion (§12.2D). Only this file.
