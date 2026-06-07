# gen-dla-copper-deposition v1 Notes

## Concept
Procedural approximation of Diffusion-Limited Aggregation (DLA) copper electrodeposition.
True DLA is an iterative particle process; this shader approximates the visual result
using domain-warped fBm noise with directional bias toward seed crystals.

## Algorithm
- Domain-warped fBm creates walker-trail-like patterns
- Polar coordinates toward seed point generate dendrite arms
- Angular periodicity (5-13 arms) with radial noise creates branching
- Electrolyte depletion field computed from deposit density
- Spark discharge at dendrite tips using hashed thresholds

## Visual Design
- Palette: fresh copper → bronze → oxidized patina (blue-green)
- HDR specular highlights on dendrite tips
- ACES tone mapping for metallic luminance range

## Audio Reactivity
- Bass: spawns denser walker clusters (more noise octaves/frequency)
- Mids: increases stick probability, denser branching
- Treble: spark discharge at growth tips

## Interactivity
- Mouse acts as electrostatic attractor (when clicked)
- Ripples array provides seed nucleation sites

## Alpha Semantics
Alpha = deposit density × (1.0 - electrolyte_depletion)
Denser deposits are more opaque; depleted regions fade.

## Params
1. scale (p1): Growth scale / noise frequency
2. arms (p2): Number of dendrite arms
3. oxidation (p3): Patina strength (not currently wired — future)
4. spark (p4): Spark intensity (not currently wired — future)

## Validation
- naga: PASS
