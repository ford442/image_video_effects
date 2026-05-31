# interactive-glitch-cubes — Kimi Notes

## Changes Made
- Added audio reactivity: bass drives extrusion, mids temporal blend, treble edge glow/sparkle.
- Added chromatic edge glow: R/B channels offset near cube boundaries.
- Added temporal cube memory via `dataTextureC` blend for settling physics.
- Fixed hardcoded alpha=1.0 to dynamic depth-aware alpha.
- Added `dataTextureA` write with height and color data.

## Wow Factor
- Cubes pulse with bass for reactive extrusion.
- Chromatic edges make each cube look like a tiny prism.
- Temporal settling gives physics-like cube stabilization.

## Risks for Claude Polish
- `hash` function used for sparkle but not defined; added inline.
- Temporal blend (0.05 + mids*0.02) may be too subtle for visible settling.
- Audio-driven gridSize may cause flickering at high bass.
