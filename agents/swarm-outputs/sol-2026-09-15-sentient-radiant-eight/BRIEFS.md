# Idea Cards — Sentient / Radiant cosmic entities (2026-09-15)

Coordinator: Flash. Batch: 8. Reserve: `USER.md` Sentient / Radiant entities eight.

Floor (every file): `plasmaBuffer` XYZ = plasma/audio (not `config.y` / fake C); mouse = `vec2(mx, 1-my)` in UV; ACES + display A; semantic depth; canonical `params` mirroring `updatedParams` (saved defaults/min/max/step/mapping exact). No new springs. No extraBuffer. No B writes. No generic spring/ripple/IQ overlay.

## 1. gen-sentient-aether-plasma-nebula-moth
- **Wing venation ridges** — `pow(1 - d, 3)` ridges along `wp.x`/`wp.y` (wing-space) on the FBM membrane; moth wing, not glass overlay.
- **Trailing-edge scale-dust** — `smoothstep` along the wing trailing edge (`wp.x` toward the posterior) adds iridescent scale specks, not click-ripple.

## 2. gen-sentient-bismuth-hypercrystal
- **Hopper terraces** — periodic `abs(fract(foldPos.y * n) - 0.5)` stair treads on the Menger cuboid (crystal growth, not IQ fog).
- **Stair-riser rainbow film** — extra thin-film iridescence keyed to terrace risers (hopper rainbow, not a second palette).

## 3. gen-sentient-cyber-aurora-void-owl
- **Feather barb ridges** — `abs(sin(p.x * k))` grooves on lattice feather cubes (barbules, not a second lattice).
- **Concentric iris rings** — `abs(length(eyeUV) - r)` rings in the eye shader (iris, not bloom).
- Floor: stop using `u.config.y` as audio; stop dividing mouse by resolution; fix head-look so it rotates around the head (don't overwrite `headPos.x` as a look angle).

## 4. gen-sentient-quantum-chrono-leviathan-moth
- **Voronoi vein ridges** — `pow(1 - cell.x, 3)` raised veins on the wing membrane (moth venation, not extra FBM).
- **Antennae** — two thin capsules from the head, same as nebula-moth (the body is a moth, it needs antennae).
- Floor: `plasmaBuffer` not `config.y`.

## 5. gen-radiant-chrono-glass-nautilus
- **Chamber septa** — thin walls at logarithmic spiral compartment boundaries (chambered nautilus, not a second shell).
- **Nacre iridescence** — thin-film along the shell surface keyed to chamber index (mother-of-pearl, not ACES).

## 6. gen-radiant-cyber-chrono-void-stag
- **Antler velvet / pearling** — small spheres along antler branches (velvet buds, not extra antler SDF).
- **Hoof-trail pulses** — brightness keyed to `fract(trailT)` so steps flash (gait, not click-ripple `.w`).
- Floor: `plasmaBuffer`; mouse UV (`u.mouse.xy`, not `/ config.zw`).

## 7. gen-radiant-quantum-crystalline-forge
- **Recalescence on fold crests** — emission on KIFS fold edges (`abs(foldPos)` crests glow as cooling metal).
- **Hopper terraces** — `abs(fract(foldPos.y * n) - 0.5)` stair treads on the forge crystal (same growth language as bismuth, different SDF).
- Floor: **delete** `applyGenerativePrimaryControls` (it steals Density into zoom and Mouse Influence into `zoom_params.w`). Wire Density/Chroma/Fog/Mouse Influence in the existing path. Keep saved param bytes.

## 8. gen-radiant-quantum-plasma-kraken-core
- **Sucker discs** — `capsule`/`sphere` discs along each tentacle (cephalopod anatomy, not extra tentacles).
- **Chromatophore pulses** — `sin(t + i)` color flashes on tentacle skin (chromatophores, not `config.y`).
- Floor: `plasmaBuffer`; use `zoom_params` raw (JSON 0–5); do not re-clamp 0–1 (that would change saved meanings).
