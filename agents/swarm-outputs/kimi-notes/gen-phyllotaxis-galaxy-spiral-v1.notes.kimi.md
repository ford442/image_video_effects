# gen-phyllotaxis-galaxy-spiral v1 Notes

## Concept
Golden-angle (~137.5°) phyllotaxis spiral where each floret is a star/galaxy point.
Vogel's formula (θ = n × 137.5°, r = c√n) arranges 350 stars with Hubble palette.
Lin-Shu density wave theory perturbs spiral arms for galactic realism.

## Algorithm
- Per-pixel loop over 350 Vogel-spiral stars
- Each star rendered as Gaussian blob with size based on apparent depth
- Density waves perturb radius for arm structure
- 3D rotation of galactic disk + mouse-driven viewpoint offset

## Visual Design
- Hubble palette: blue young stars, yellow main sequence, red old stars
- Supernova candidates (rare pink stars) flare on treble
- Chromatic aberration on bright regions
- ACES tone mapping for HDR star brightness

## Audio Reactivity
- Bass: drives spiral arm density wave amplitude
- Mids: rotates galactic disk
- Treble: triggers supernova flare events on rare stars

## Interactivity
- Mouse drags 3D viewpoint through galactic disk (when clicked)
- Zoom params control star spread and size

## Alpha Semantics
Alpha = star brightness accumulation × depth_fade × (1.0 - dust_extinction)
Dust lanes and distant stars are more transparent.

## Params
1. spread (p1): Star spread / Vogel constant c
2. size (p2): Base star size multiplier
3. rotation (p3): Disk rotation speed offset
4. density (p4): Wave density strength (not currently wired — future)

## Performance
350 stars × 32 segments ≈ 11k iterations per pixel. Acceptable on modern GPU.

## Validation
- naga: PASS
