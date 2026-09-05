# Shader Notes

| Shader | A/C state packing | Key repair |
|---|---|---|
| fractal-clockwork | display RGBA | Four named controls; existing slots 133–138 retained |
| fractal-ember-lattice | displacement xy, seed, reform | Removed filtered/state-as-color feedback |
| fractured-monolith | display RGBA | Real three-band audio, normalized orbit, ACES/alpha/depth |
| galactic geode core | display RGBA | Plasma audio replaces resolution fields; ACES/alpha/depth |
| ghost-flame | temperature, fuel, velocity x, age | Exact neighbor/advection loads; envelopes moved to 133–134 |
| glacial cavern | display RGBA | Four named controls and explicit packing metadata |
| glass mosaic | display RGBA | Exact history, A writeback, ACES and semantic alpha |
| ferrofluid engine | display RGBA | Exact advected history, treble droplets, ACES/alpha |
| gravitational strain | potential, ray speed, emission, alpha | Exact state smoothing and ACES output |
| phononic accretion | temporal display RGBA | Exact history, semantic A alpha, generated depth |

Only Clockwork and Ghost Flame use `extraBuffer`; every accessed slot lies in
the permitted range `[133..138]`. No target writes `dataTextureB` or C.
