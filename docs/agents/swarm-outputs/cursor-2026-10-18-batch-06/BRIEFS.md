# Cursor batch-06 — Idea Cards

Written before WGSL edits. 2026-10-18.

Spectrogram family stays together (pass 1, pass 2, and the single-pass `spectrogram-displace`). `gen-fluffy-raincloud` is `public/shaders/gen_fluffy_raincloud.wgsl`. Files that already carry ideas get a second pass; prior ideas stay.

```
SHADER: spectrogram-displace-pass1
IDENTITY: the spectrogram field — log-frequency rows, harmonic peaks, four color schemes, magnitude handed to pass 2
KEEP VERBATIM: harmonic synth (110/220/440, 1/h decay), heatmap/neon/ocean/fire, Freq Range / Time Window / Magnification / Color Scheme, mouse frequency highlight, ripple boost, writeTexture = source photo, A = (spectroColor.rgb, magnitude)
MECHANISM INTERROGATION:
  tactic 2: a windowed spectrum leaks into the next bin, and a display holds peaks
  tactic 5: the engine already writes 128 FFT bins at extraBuffer[5..132]; this field never read them
  tactic 6: C.a can be last frame's magnitude only if pass 2 stops overwriting A
ADD:
  1. Hann sidelobes — a shoulder one bin off each row, about −13 dB, so peaks are not a single clean line
  2. Peak-hold — magnitude releases from last frame's C.a; Time Window sets how long the peak hangs
  3. Live bin ink — extraBuffer[5+bin] adds into the same log row the synth already paints
FORBID: a new palette, writing displacement into A, ACES on the stored magnitude, a spring
A PACKING: raw (spectroColor.rgb, magnitude). No ACES on A. Pass 2 must not write A.
```

```
SHADER: spectrogram-displace-pass2
IDENTITY: the photo shoved by the field magnitude, tinted by the field color, bass-weighted, vignette
KEEP VERBATIM: (r−b) horizontal and (g−0.5) vertical displacement, waveDisp, low/high frequency boost, vignette, Horizontal / Vertical / Magnitude / Blend, bass boost from plasmaBuffer[0].x
MECHANISM INTERROGATION:
  tactic 2: loud bins pull the picture toward them; a spectrogram is also a raster of bin rows
  tactic 6: C is the field; a filtering sample is illegal on rgba32float, and writing display into A erases the field
ADD:
  1. Spectral shear — the photo shifts toward the louder neighbor along frequency; Vertical Displace scales it
  2. Raster bin ticks — hairlines on the 128-bin grid, brightness from the local magnitude; Blend scales them
FORBID: a second displacement formula, writing A, an IQ palette
A PACKING: does not write A. C is pass 1's field via textureLoad. Display ACES is writeTexture.
```

```
SHADER: spectrogram-displace
IDENTITY: a live FFT waterfall scrolling across the photo, with a sprung pointer band and click accents
KEEP VERBATIM: log-y bin select, extraBuffer[5..132] mix with bass/mids/treble, cosine palette, exact-C scroll, spring in [133..138], click fronts, RGB displacement, Intensity / Speed / Scale / Detail, A = ACES display history
MECHANISM INTERROGATION:
  tactic 2: a harmonic series stacks above a fundamental; bass rows ring longer than treble rows on a waterfall
  tactic 6: the scroll already mixes previous.rgb; the decay can depend on the row
ADD:
  1. Harmonic stack — narrow ticks at integer multiples of a bass fundamental, only in the fresh column
  2. Differential waterfall decay — low rows hold, high rows fade; Detail still adds persistence
FORBID: replacing the scroll, a new palette, storing raw magnitude over the display history
A PACKING: ACES display RGBA (unchanged). The scroll reads previous.rgb.
```

```
SHADER: gen-magnetic-field-lines
IDENTITY: orbiting dipoles, analytic field lines, iron-filing chains, an X-point, cyclotron helices, magnetic mirrors
KEEP VERBATIM: dipoleField, six shells of r = R sin²θ, LIC filings, reconnection null, gyro helices, mirror pile-up, Field Strength / Particle Speed / Number of Dipoles / Trail Length, mouse dipole, ACES display history in A
MECHANISM INTERROGATION:
  tactic 2: a dipole has an equatorial current sheet where Bθ flips, and field lines enter at the poles
  tactic 3: polarAngle and polarRadius are already computed per dipole and only draw the shells
ADD:
  1. Equatorial current sheet — a dark lane with a thin plasma edge where cos(θ) crosses zero, outside the core
  2. Polar cusp — a bright cap where the line dives into the pole (small r, aligned with the moment)
FORBID: a second LIC, sprite filings (that is magnetic-dipole), a new solver
A PACKING: ACES display RGBA in A (unchanged).
```

```
SHADER: gen-quantum-foam-alpha
IDENTITY: paired probability clouds, interference, mouse collapse, virtual-pair flashes, Born hits, Worley membranes
KEEP VERBATIM: Lissajous pairs, gaussian clouds, interference, collapse sharpening, vacuum fbm, the three existing ideas, Cloud Density / Uncertainty / Vacuum Energy / Collapse Strength, A = (vacuumField, totalProb, avgUncertainty, alpha)
MECHANISM INTERROGATION:
  tactic 2: an entangled pair has a worldline between the two centers; a gaussian has a visible 1σ shell
  tactic 3: p1, p2, and localSigma are computed and then only integrated into a filled blob
ADD:
  1. Pair worldline — a faint segment joining p1 and p2 while the pair exists
  2. One-sigma shell — a thin ring at radius localSigma around each center
FORBID: a new particle system, ACES on the stored vacuum field, replacing the clouds
A PACKING: raw (vacuumField, totalProb, avgUncertainty, alpha). ACES on writeTexture only.
```

```
SHADER: gen-sonic-lava-flow
IDENTITY: domain-warped molten flow over the photo, cooling skin, pahoehoe ropes, crust, heat glow
KEEP VERBATIM: curl advection, temperature ramp, cooling skin, pahoehoe ropes, Fresnel, Beer glow, Viscosity / Flow Speed / Crust Detail / Glow Intensity, A = linear color history
MECHANISM INTERROGATION:
  tactic 2: a lava channel builds levees on its margins; fast shear breaks the crust into a'a clinker
  tactic 3: flowDir, perp, temp, and shear are already computed for the ropes and the skin
ADD:
  1. Levees — crust piled on either side of a hot thread; the thread itself stays molten
  2. A'a clinker — broken rubble where shear is high; viscous flows stay pahoehoe
FORBID: a new solver, replacing the ropes, ACES on the stored history
A PACKING: linear color history in A; ACES on writeTexture only.
```

```
SHADER: gen-cybernetic-liquid-chrome-engine
IDENTITY: a raymarched chrome V8 — firing-order crank, piston crush, cam notches, exhaust blueing, heat shimmer
KEEP VERBATIM: crankState firing order, KIFS core, piston, cam notches, manifold blueing, ignition glow, Intensity / Speed / Scale / Mouse Influence, A = pre-ACES HDR history
MECHANISM INTERROGATION:
  tactic 5: a running engine shows an oil film on the bore and a ring of head bolts on the deck
  tactic 3: local cylinder coordinates are already computed for the cam notch and the manifold
ADD:
  1. Oil gallery — a dark wet streak along the bore that takes more of the existing specular
  2. Head bolts — a ring of dark dots on the deck face
FORBID: a new engine primitive, replacing the crank, an IQ palette as the chrome
A PACKING: HDR linear RGB + semantic alpha; C read back as HDR (unchanged).
```

```
SHADER: magnetic-dipole
IDENTITY: iron-filing sprites on the photo, aligned to a mouse dipole, with streaming packets and a pole-flip whip
KEEP VERBATIM: dipoleField, sprite ellipse, inertia from C.b, A = (fieldDir.xy, alignment, fieldStrength), B aux write, Charge Strength / Alignment Inertia / Filing Size / Field Density, packet dance, pole-flip, pulse rings
MECHANISM INTERROGATION:
  tactic 2: filings chain along B, and the magnet itself is a body the filings do not enter
  tactic 5: the pointer is already the dipole; it has no core
ADD:
  1. Magnet body — a disk at the mouse that occludes filings; packets brighten at its rim
  2. Chain links — a short segment along the local field joins a strong filing to its neighbor
FORBID: replacing the sprites with LIC (that is gen-magnetic-field-lines), rewiring the A channels
A PACKING: A = (fieldDir.xy, alignment, fieldStrength). B stays the aux write HEAD owns. Display ACES is writeTexture.
```

```
SHADER: gen-cybernetic-ferro-coral
IDENTITY: a raymarched ferro-coral — spiked cells, Turing bands, iridescent shell, circuit traces, an outward signal pulse
KEEP VERBATIM: cell repeat, warped spikes, Turing bands, fresnel iridescence, circuit glow, signal pulse, Density / Spike Intensity / Core Glow / Iridescence, A = ACES display history
MECHANISM INTERROGATION:
  tactic 2: a coral calyx is a cup with radial septa; the cell sphere is already the corallite
  tactic 3: q is the cell-local point and is only used for the sphere radius
ADD:
  1. Corallite cup — an annular indent on each cell sphere
  2. Septa — six radial walls inside that cup
FORBID: a new creature, replacing the Turing bands, a liquid sim
A PACKING: A/C = display history (ACES on both, as HEAD already tone-maps before the A store).
```

```
SHADER: gen-fluffy-raincloud
IDENTITY: a vorticity raincloud — anvil, mammatus, shelf roll, virga — density and moisture advected over the photo
KEEP VERBATIM: curl advection, vorticity confinement, anvil, mammatus, shelf, virga, Coverage / Turbulence / Rain / Wind, A = (density, velocity.xy, moisture), gust spring in [133..136]
MECHANISM INTERROGATION:
  tactic 2: rain punching out of a deck leaves a fallstreak hole; sun through a gap throws crepuscular shafts
  tactic 3: density, anvil, and the light direction are already computed
ADD:
  1. Fallstreak hole — a cavum in the anvil, with a brighter virga rim; Rain sets how open it is
  2. Crepuscular shafts — light through a thinner overhead column, added on the existing light direction
FORBID: a new cloud solver, repacking A, replacing virga
A PACKING: raw (density, velocity.x, velocity.y, moisture). ACES on writeTexture only.
```
