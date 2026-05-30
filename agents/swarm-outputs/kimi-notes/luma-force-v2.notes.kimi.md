# luma-force v2 Upgrade Notes

## Changes
- **Lines**: 77 → 141
- **Category**: stays `interactive-mouse`
- **Algorithm**: Added physics-based particle advection with luma-gradient forces (bright repels, dark attracts). curl_noise() provides divergence-free flow field. Mouse creates local vortex.
- **Visual**: Spectral chromatic aberration based on velocity, HDR glow on high-velocity regions, ACES tone mapping.
- **Interactive**: Bass drives force magnitude, mouse vortex with configurable radius, depth controls parallax between force layers via depthParallax.
- **Alpha**: velocity magnitude × luma_contrast × depth (semantic).

## Parameters Updated
- `strength` → `forceMag`
- `mode` removed (now always gradient-based)
- `radius` stays
- `curlWeight` replaces `mode`
- `lumaWeight` stays

## Naga Status
- ✅ PASSED (`naga luma-force.wgsl`) — exit 0, SPIR-V generation successful

## Tags Added
particle-advection, curl-noise, spectral, HDR, physics, vortex
