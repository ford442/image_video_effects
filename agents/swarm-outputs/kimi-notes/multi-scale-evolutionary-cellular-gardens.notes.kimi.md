# multi-scale-evolutionary-cellular-gardens — Kimi Notes

## Changes
- Chromatic species separation: species1 = green/cyan, species2 = magenta/purple for visual clarity.
- Audio mutation rate integration: `mids` drive growth rate, `bass` injects competition pulses.
- Temporal color memory: previous frame tints bleed in via `dataTextureC`, creating organic trails.
- State persistence: `dataTextureA` stores S1/S2/resource for stable generational evolution.
- Mouse nurturing adds localized resource bloom.

## Wow-Factor
- Two species visibly compete in contrasting colors; winner-take-all patches form dynamically.
- Audio-driven mutation makes the garden “dance” to music — bass drops trigger speciation events.

## Risks
- State can collapse to mono-culture if competition is too high; parameter range clamps are critical.
- 4 neighbor reads + self = 5 fetches per pixel; acceptable but monitor on 4K displays.
