# gen-barnsley-fern — Kimi Notes

## Changes
- Inverse IFS Monte-Carlo rendering: each pixel evaluates 2-5 random inverse paths through the Barnsley fern transform system. Points in the attractor stay bounded; exterior points escape quickly.
- Natural fern palette by height: deep forest green at stem, transitioning through emerald and lime to yellow-green frond tips.
- Mouse attracts frond tips via exponential pull weighted by `tipFactor` (higher y = stronger attraction).
- Depth controls inverse path count (more paths = sharper detail) via `readDepthTexture`.
- Bass morphs palette warmth and temporal feedback mix strength.
- Chromatic aberration on fern edges: R channel boosted, B channel attenuated at high-density boundaries.
- ACES tone mapping for HDR sunlight filtering.
- Temporal feedback via `dataTextureC` for organic ghosting.
- Semantic alpha: `density * photosynthetic_activity * depth` where photosynthetic activity is derived from green channel.

## Wow-Factor
- Inverse IFS rendering produces a mathematically exact Barnsley fern attractor without point splatting or atomic operations.
- Mouse interaction feels like wind tugging at individual fronds.

## Risks
- Inverse IFS is a Monte Carlo estimate; very low `depth` values can make the fern appear slightly noisy with only 2 paths.
- f1 inverse (stem) is singular and falls back to f2 when |x| > 0.18, which is a minor approximation.
