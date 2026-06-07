# hex-pulse v2 Upgrade Notes

## Changes
- **Lines**: 83 → 145
- **Category**: stays `interactive-mouse`
- **Algorithm**: Replaced simple radial pulse with damped wave equation on hex lattice. Added interference between cells via second harmonic. hex_cell() and hex_sdf() provide proper honeycomb geometry.
- **Visual**: Bioluminescent cell glow with audio-reactive color shifts, chromatic dispersion at cell edges, ACES tone mapping, HDR bloom on constructive interference nodes.
- **Interactive**: Bass triggers cell firing cascades via wave amplitude boost. Mouse excites local cells with exponential falloff. Depth controls wave attenuation.
- **Alpha**: cell excitation × interference_amplitude × depth (semantic).

## Parameters Updated
- `radius` → `waveDecay`
- Others renamed for clarity

## Naga Status
- ✅ PASSED (`naga hex-pulse.wgsl`) — exit 0, SPIR-V generation successful

## Tags Added
honeycomb, wave-equation, interference, bioluminescent, chromatic, HDR
