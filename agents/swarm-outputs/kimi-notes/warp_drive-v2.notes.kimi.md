# warp_drive v2 Upgrade Notes

## Swarm Synthesis
- **Algorithmist**: Added Alcubierre warp metric approximation — radial compression ahead (`t > 0.5` positive offset) and expansion behind (negative offset). Length contraction modeled via `alcubierre` term in offset calculation. Doppler beaming with per-sample color shift based on direction.
- **Visualist**: Star streaks with relativistic Doppler shift (blue ahead, red behind), HDR bloom on contracted stars, ACES tone mapping, chromatic aberration on high-velocity regions.
- **Interactivist**: Bass drives warp factor (1→10), mouse steers the ship direction (center drifts), depth controls star density perspective (12-40 stars).
- **Optimizer**: Fixed loop count based on blur_quality param, branchless `select()` for Doppler direction, precomputed common terms.

## Alpha Semantics
`finalAlpha = warp_intensity * doppler_magnitude * depth + src_alpha * 0.2 + starburst * 0.3`
Alpha carries warp intensity, Doppler shift magnitude, and depth.

## Line Count
129 lines

## Changes from v1
- Replaced simple radial blur with Alcubierre metric approximation
- Added relativistic Doppler shift per sample
- Added star field generation via hash22
- Added chromatic aberration on velocity regions
- Added ACES tone mapping
- Alpha now semantic (was clamped src_alpha blend)

## Validation
naga: PASS
