# gen-depth-refracted-liquid-stained-glass — Kimi Notes

## Changes Made
- Fixed invalid WGSL float modulus (`%` on floats) at original line 63; replaced with fract-based polar folding.
- Added temporal caustic flicker on facets via slow facet spin (`a += time * 0.2`).
- Added chromatic edge dispersion per depth edge (R/B offset by `treble`/`bass`).
- Added audio-driven refraction strength (`ref_str *= (1 + bass * 0.3)`).

## Wow Factor
- Facets slowly rotate for living stained glass effect.
- Chromatic edges refract differently by wavelength near facet boundaries.
- Audio drives refraction intensity for reactive liquid feel.

## Risks for Claude Polish
- Fixed modulus may change original polar folding behavior; verify visual match.
- `dataTextureC` tint blend may accumulate into uniform color over time.
- Edge factor only active near `angleStep` boundaries; verify with high facet counts.
