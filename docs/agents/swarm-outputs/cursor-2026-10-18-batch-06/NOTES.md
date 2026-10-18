# Cursor batch-06 — notes

2026-10-18. Cards in `BRIEFS.md` were written before the WGSL edits.

## spectrogram-displace-pass1

Kept the harmonic synth, the four color schemes, the mouse frequency highlight, the ripple boost, and the source photo on `writeTexture`. Slider roles unchanged.

Added in `main`: Hann sidelobes (a shoulder one bin off the row), live FFT ink from `extraBuffer[5+bin]` on the same inverted-y row, and peak-hold against `C.a` with Time Window as the release.

A packing: raw `(spectroColor.rgb, magnitude)`. No ACES on A. Header no longer claims displacement channels.

## spectrogram-displace-pass2

Kept the `(r−b)` / `(g−0.5)` displacement, the sine wave offset, the low/high frequency boosts, the vignette, and the bass boost. All four sliders still scale those roles.

Added spectral shear from the vertical magnitude gradient (Vertical Displace) and 128-bin raster ticks (Spectrogram Blend). Field reads are `textureLoad`. Does not write A, so pass 1's magnitude survives into the next frame. Display is ACES on `writeTexture`.

## spectrogram-displace

Kept the log-y FFT mix, the cosine palette, the exact-C scroll, the spring in `[133..138]`, the click fronts, and the RGB displacement. A stays ACES display history.

Added a six-partial harmonic stack on the fresh column (bass sets the fundamental, Detail tightens the ticks) and row-dependent waterfall decay (low rows hold, high rows fade, Detail still lengthens the hold). The spring's own `decay` local was left alone.

## gen-magnetic-field-lines

Kept the dipole shells, LIC filings, reconnection X-point, cyclotron helices, magnetic-mirror pile-up, and the mouse dipole.

Added, inside the existing per-dipole loop: an equatorial current sheet (dark lane plus a thin plasma edge where `cos θ` crosses zero) and a polar cusp cap along the moment. A stays ACES display RGBA.

## gen-quantum-foam-alpha

Kept the Lissajous pairs, gaussian clouds, interference, mouse collapse, virtual-pair flashes, Born hits, and Worley membranes. A stays `(vacuumField, totalProb, avgUncertainty, alpha)`.

Added a worldline between each pair's two centers and a one-sigma shell around each center. Both feed the existing color accumulator. ACES stays on `writeTexture` only.

The dead-slider scanner skips this definition (its param block is not in the shape that scanner reads). All four `zoom_params` are read in `main`.

## gen-sonic-lava-flow

Kept curl advection, the temperature ramp, cooling skin, pahoehoe ropes, Fresnel, and the Beer glow. A stays linear color history.

Added channel levees (crust on either side of a hot thread; Crust Detail scales them) and a'a clinker where shear is high and viscosity is low. Viscous flows stay pahoehoe.

Same scanner skip as the foam shader. `zoom_params` x/y/z/w are viscosity, flow speed, crust, and glow.

## gen-cybernetic-liquid-chrome-engine

Kept the firing-order crank, piston crush, cam notches, exhaust blueing, and ignition shimmer. A stays pre-ACES HDR.

Added an oil streak along the bore (darker, taking more of the existing specular) and a ring of head bolts on the deck. Both use the cylinder-local point the cam notch already computes.

## magnetic-dipole

Kept the sprite ellipse, inertia from `C.b`, A packing `(fieldDir.xy, alignment, fieldStrength)`, the B aux write, the packet dance, the pole-flip whip, and the pulse rings.

Added a magnet disk at the mouse (filings are masked out; packets brighten on the rim; Charge Strength sets the radius) and a short chain segment along the local field for strong filings. Field Density still sets the spacing.

## gen-cybernetic-ferro-coral

Kept the cell repeat, warped spikes, Turing bands, fresnel iridescence, circuit traces, and the outward signal pulse. The existing negative `pow` on the pulse was rewritten as a square so the base cannot be negative. A is ACES display history, which is what the store already did; the header now says so.

Added a corallite cup (annular indent on the cell sphere) and six septa inside it. Spike Intensity scales both. The shade uses the same cell size as the SDF (Density min is 0.1).

## gen-fluffy-raincloud

File is `public/shaders/gen_fluffy_raincloud.wgsl`. Kept curl advection, vorticity confinement, the anvil, mammatus, the shelf roll, virga, and raw `(density, velocity.xy, moisture)`.

Added a fallstreak hole in the anvil (Rain opens it; the rim feeds extra virga) and crepuscular shafts along the existing light direction through a thinner overhead column.

## Floor

Seven pasted headers migrated to `#include "_prelude.wgsl"` (`spectrogram-displace`, both passes, `gen-quantum-foam-alpha`, `gen-sonic-lava-flow`, `magnetic-dipole`, `gen-cybernetic-ferro-coral`). Saved `params` were not renamed or re-defaulted. `x-meta.upgrade.params` added on the two spectrogram passes.

## Gates

Naga 10/10. Precommit 10/10. extraBuffer: 0 new violations. Dead sliders: the eight definitions the scanner reads are clean; foam and lava are skipped by the scanner and read all four sliders in WGSL. Catalogs regenerated, duplicate check clean. Jest 159 suites, 1332 passed, 1 skipped. `SKIP_WASM_BUILD=1` build compiled. Real-GPU visual QA is external.
