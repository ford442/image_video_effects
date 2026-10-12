# Fireworks ten — 2026-10-10

Idea cards written before WGSL edits. All ten are second-pass files: the September ideas stay and each shader gains two more native ideas. Saved params stay byte-exact. Pasted binding headers were swapped for `#include "_prelude.wgsl"` first (infrastructure, not counted).

## gen-fireworks-fan-shell

IDENTITY: mortar shells that open into a flat upward fan of drag-physics sparks with peacock eyes.
KEEP VERBATIM: fan angle / power / density / hue-cycle roles, drag `sparkPos`, shell wind + flutter, peacock eye, two-row palmette, mouse fan.
ADD:
1. Unfolding sweep — rays ignite one after another across the fan (direction alternates per shell), like a hand fan opening.
2. Guard-stick ribs — the two outermost rays are heavy gold ribs with a short continuous streak, framing the fan.
FORBID: springs, click rings, circular peony bursts.
A PACKING: ACES display RGBA.
SYMBOLS: `unfoldSweep`, `guardRib`

## gen-fireworks-horse-tail

IDENTITY: brocade bursts that pinch and fall as long parallel gold streamers.
KEEP VERBATIM: tail length / stream width / gold / fall roles, `tailPos` drag fall, brocade pinch, tip spark-out, silver dust, mouse cascade.
ADD:
1. Tail swish — a transverse wave travels down each streamer, larger toward the tip, like a horse flicking its tail.
2. Dock knot — a slow-fading gold knot at the burst point where all streamers hang from.
FORBID: palette rainbow, ring bursts, springs.
A PACKING: ACES display RGBA.
SYMBOLS: `tailSwish`, `dockKnot`

## gen-fireworks-kamuro-gold

IDENTITY: dense gold glitter cloud that hangs, twinkles, then drifts down.
KEEP VERBATIM: density / fall / gold mix / hang roles, `kamuroPos` plateau, per-glitter twinkle, HDR core, haze, split-tone.
ADD:
1. Dross fission — at each twinkle peak the glitter spits three tiny satellite sparks (flitter chemistry).
2. Charcoal cooling — after the plateau, glitter cools along a blackbody ramp to dull red and shrinks.
FORBID: rainbow palettes, streamers, ring structure.
A PACKING: ACES display RGBA.
SYMBOLS: `drossFission`, `charcoalCool`

## gen-fireworks-nocturne

IDENTITY: night field of staggered mortar shells (round and drooping habits) with embers and crackle.
KEEP VERBATIM: energy / tempo / density / color-drift roles, jewel palette, muzzle flash, round/droop habits, crackle, embers, mouse shell, feedback smoke.
ADD:
1. Aerial perspective — each shell gets its own distance: far shells open smaller, dimmer and hazier blue, so the field has depth.
2. Color-changing stars — at a per-shell age the burst stars jump to a second jewel colour.
FORBID: wind shear (wind-ripple), smoke puffs (smoke-bloom).
A PACKING: ACES display RGBA.
SYMBOLS: `aerialDepth`, `colorChange`
NOTE: card revised before editing. The first draft had a river reflection under the launch line, but `baseY = -0.82` is outside the visible ±0.5 band, so the reflection would never be on screen.

## gen-fireworks-ring-shell

IDENTITY: tilted halo rings with an empty core.
KEEP VERBATIM: ring radius / thickness / count / color roles, Saturn tilt factor, empty-core gate, secondary halo, mouse halo.
ADD:
1. Per-shell roll — each ring is rotated by its own roll angle, so rings face different ways.
2. Far-side dimming — the back half of the inclined ring is dimmer and smaller, front half hotter (and nearer in depth).
FORBID: filling the core, springs, peony sparks.
A PACKING: ACES display RGBA.
SYMBOLS: `ringRoll`, `farSide`

## gen-fireworks-roman-candle

IDENTITY: tubes firing a sequence of single coloured stars upward.
KEEP VERBATIM: fire rate / star size / tube spread / trail roles, tube cadence, colour sequence, muzzle flash, apex burst, held + click candles.
ADD:
1. Interstitial fountain — between star ejections the tube spits a short cone of gold comp sparks.
2. Burnout gutter — late in flight each star flickers and shrinks before it dies.
FORBID: big peony bursts, springs, wind.
A PACKING: ACES display RGBA.
SYMBOLS: `fountain`, `gutter`

## gen-fireworks-smoke-bloom

IDENTITY: peony shells that leave flash-lit, rising smoke puffs and a feedback bloom.
KEEP VERBATIM: smoke density / bloom / energy / decay roles, `smokePuff`, buoyancy, burst-lit smoke, secondaries, C bloom.
ADD:
1. Vortex-ring cap — as the puff rises it hollows into a toroidal smoke ring.
2. Smoke extinction — sparks seen through the puff are dimmed and reddened by its density.
FORBID: wind streaks, springs.
A PACKING: ACES display RGBA.
SYMBOLS: `vortexRing`, `extinction`

## gen-fireworks-strobe-shell

IDENTITY: shells whose stars blink on and off with real dark intervals.
KEEP VERBATIM: flash rate / pulse power / afterglow / colour roles, `strobePulse`, per-spark phase, embers, mouse strobe.
ADD:
1. Stroboscopic dotted path — faint dots at the last few flash positions of each star, the persistence-of-vision dotted line.
2. Sky strobe — the shell's own pulse lights a wide veil of sky around it.
FORBID: continuous trails, smoke, springs.
A PACKING: ACES display RGBA.
SYMBOLS: `strobeDots`, `skyStrobe`

## gen-fireworks-willow-cascade

IDENTITY: slow gold willow curtains that droop and hang.
KEEP VERBATIM: trail / droop / wind / warmth roles, `willowPos` terminal hang, leeward lean, streaks, advected C trails.
ADD:
1. Willow trunk — the ascent comet leaves a lingering gold trunk under the crown, completing the tree.
2. Tip drips — beads detach from strand tips and fall faster than the strand.
FORBID: rainbow, ring shells, springs.
A PACKING: ACES display RGBA (HDR-clamped accumulate before ACES, as HEAD).
SYMBOLS: `willowTrunk`, `tipDrip`

## gen-fireworks-wind-ripple

IDENTITY: wind-blown shells plus click ripple barrages.
KEEP VERBATIM: wind energy / ripple sensitivity / trail / drift roles, altitude shear, leeward streaks, comet lines, advected C trails, ripple barrages.
ADD:
1. Gust bands — travelling gusts along the wind direction push sparks harder as they pass.
2. Shock refraction — ripple fronts bend the view of sparks behind them.
FORBID: springs, smoke puffs.
A PACKING: ACES display RGBA (HDR-clamped accumulate before ACES, as HEAD).
SYMBOLS: `gustBand`, `shockRefract`
