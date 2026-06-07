# cinematic-flare v2 Upgrade Notes

## Changes
- **Lines**: 81 → 149
- **Category**: stays `lighting-effects`
- **Algorithm**: Added physically-based Cooke triplet ghost reflections (3 lens element surfaces with configurable coefficients), 6-blade aperture diffraction starburst, atmospheric scatter halo, anamorphic streaks sampled along light-to-pixel axis.
- **Visual**: Rainbow chromatic aberration on ghost reflections, starburst diffraction spikes, ACES tone mapping, film grain, warm gold atmospheric tint from mids.
- **Interactive**: Bass drives flare intensity, mouse positions the light source (fallback to center), depth controls atmospheric haze bloom via haze factor.
- **Alpha**: flare intensity × atmospheric_transmission × depth (semantic).

## Parameters
- Unchanged names; `threshold` default unchanged.

## Naga Status
- ✅ PASSED (`naga cinematic-flare.wgsl`) — exit 0, SPIR-V generation successful

## Tags Added
cooke-triplet, diffraction, film-grain
