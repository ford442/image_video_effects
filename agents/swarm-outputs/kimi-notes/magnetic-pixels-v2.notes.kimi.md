# magnetic-pixels v2 Upgrade Notes

## Changes
- **Lines**: 76 → 136
- **Category**: moved from `image` to `interactive-mouse` (matches directory)
- **Algorithm**: Replaced simple radial force with proper magnetic dipole field simulation using dipole_field() and vector_potential(). Added Lorentz-force displacement for pixel advection.
- **Visual**: Iron-filing aesthetic with metallic sheen, ACES tone mapping, chromatic aberration along dipole axis, HDR bloom on field concentrations.
- **Interactive**: Mouse positions dipole; bass drives field strength oscillation; depth controls pixel size perspective via depthScale.
- **Alpha**: Field alignment confidence × depth (semantic, not 1.0).

## Parameters Updated
- `strength` → `dipoleStrength`
- `radius` → `fieldRadius`
- `hardness` → `metallic`
- `chaos` → `chroma`

## Naga Status
- ✅ PASSED (`naga magnetic-pixels.wgsl`) — exit 0, SPIR-V generation successful

## Tags Added
magnetic, dipole, iron-filings, metallic, chromatic, HDR, physics
