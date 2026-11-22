# Notes — cursor/batch-58 (2026-11-22)

Idea Cards were written first in `BRIEFS.md`. Saved `params` on definitions that already had a top-level array were not renamed or re-defaulted. Five generative definitions only named their sliders under `x-meta`, which the app does not read. A top-level `params` array was added by copying those names, ranges, and defaults. At rest the engine had been sending `0.5` for every lane. Astrolabe, the geode, and Lichtenberg were already authored as 0–1 mixes, so their defaults match that. Prismatic Void-Weaver and the chrono-serpent were authored against the `x-meta` ranges (twist 1–20 default 5, time scale default 1, fracture depth default 2). Those sliders now load at the authored defaults.

No §12.2 formula is new in this batch. No shared spring, shockwave, or IQ palette was added. FFT-bin reads of `extraBuffer[6..13]` were replaced with `plasmaBuffer[0]`. Persistent state stays in `extraBuffer[133..138]`, single writer.

Five pasted headers were migrated to `#include "_prelude.wgsl"` (`dla-walkers`, `dla-render`, `chromatographic-diffuse`, `chromatographic-interact`, `chromatographic-phase`). That migration is not the upgrade.

## Pass files

### dla-walkers

- Kept: 64×1×1 dispatch, spawn, random step, pointer/centre pull, freeze-and-respawn, trail stamp, no `extraBuffer[`.
- Added: stick chance falls as frozen-neighbor count rises; stick peaks on a 2-to-6-fold facet set from Branch Angle; walker speed sets an 8-probe reach that pulls the step toward crystal.
- A packing: raw sim. Facet angle is now the growth direction in `.a` (still 0–1, still a hue shift in the render). No display write.

### dla-render

- Kept: frame-0 centre seed, ripple seeds, held-pointer seed, hue body, trail fade, field carried in A.
- Added: cool highlight on exposed tips; glint from the stored growth angle; age annuli. ACES on `writeTexture` only. Alpha is crystal coverage plus trail.
- A packing: raw sim. `dla-crystals` features gained `upgraded-rgba`.

### physarum-agents-diffuse

- Kept: 3×3 torus blur, `TRAIL_CAP`, persistence mix, click blooms, `.g` deposit time.
- Added: cardinal taps aligned with the trail gradient count more; a recent deposit decays less.
- A packing: raw trail. No display write.

### physarum-agents-step

- Kept: `FOOD_W`, `WANDER`, `DEP0`, `TRAIL_CAP`, the three-way steer, one deposit value per texel.
- Added: a forward cell near the trail cap forces the existing U-turn; the added trail shrinks as the texel fills, still the same value for every agent on it.
- A packing: raw trail. No display write.

### chromatographic-diffuse

- Kept: per-channel Jacobi viscosities from the split slider, temperature in `.a`.
- Added: diffusivity falls as dye mass rises; the same viscosities scale up with temperature.
- A packing: raw dye.rgb + temperature.

### chromatographic-interact

- Kept: drag toward the mean, treble on the separation.
- Added: the peak channel crowds the other two; a small unsharp against the four-neighbor mean.
- A packing: raw dye.rgb + temperature.

### chromatographic-phase

- Kept: evaporation amount from the temperature slider, cool condensation, blue vapor tint.
- Added: blue leaves faster than red; evaporation lowers the stored temperature.
- A packing: raw dye.rgb + temperature.

### sph-fluid-density

- Kept: every named constant, poly6 sum, curl, seed, aux packing, hash not moved.
- Added: a narrow kernel inside 0.35h on top of poly6; vorticity attenuated in the over-dense core.
- A packing: aux `(-1, -1, density, vorticity)`.

### sph-fluid-force

- Kept: Tait, viscosity, cohesion, confinement, XSPH, walls, drive, integrator, stamp channels.
- Added: short-range repulsion when `r < 0.5`; the stamp's speed channel rises for fast under-dense particles. Velocity is unchanged.
- A packing: the render stamp. No display write.

## Dense shaders

### gen-luminescent-chrono-fluid-astrolabe

- Kept: march, limb, rete, ecliptic, alidade, spring in `extraBuffer[133..138]`.
- Added: 1° vernier ticks on the limb face; star hash scales magnitude. Core pulse reads mids and treble from `plasmaBuffer[0]`.
- A packing: ACES display RGBA.

### gen-sonoluminescent-chrono-geode-matrix

- Kept: bubble cycle, strata, pearls, afterbounce, ember ramp, swirl-advected history.
- Added: dark rings on the cavity radius; previous-frame luma adds a red tail after the flash. Flash pulse reads `plasmaBuffer[0]`.
- A packing: HDR history in A. ACES on `writeTexture` only.

### gen-lichtenberg-storm

- Kept: `licht()`, leader, gaps, corona taps, beads, charge in C.g, spring in 133–138.
- Added: etched charge darkens the dielectric under a spent channel; sparse treble specks on the corona. Sparkle bands are bass and treble from `plasmaBuffer[0]`.
- A packing: raw `(energy, charge, shock, 1)`. ACES on display only.

### gen-prismatic-void-weaver-ouroboros

- Kept: twist, glow, gravity, audio slider, tether, jaw seam, keel grating, C history mix. No spring.
- Added: the jaw gap darkens beside the gold seam; the keel's trailing side dims. Shimmer reads `plasmaBuffer[0]`.
- A packing: ACES display RGBA.

### gen-sentient-cyber-chrono-void-serpent

- Kept: march, echoes, scale glint, isochrones, bulge, ecdysis.
- Added: `fn aces` on the display; exact `textureLoad` of last frame mixed after the tone map; a dark node at mid-band on the chrono-rings.
- A packing: ACES display RGBA. Features list audio, mouse, and upgraded-rgba.

### matrix_digital_rain

- Kept: five zoom layers, the four sliders, `rain_cell`, bass chroma, pointer vortex, ACES.
- Added: last frame's display tints the new columns; a bright head last frame holds more of the revealed color. The `extraBuffer[0]` read is gone.
- A packing: ACES display RGBA.

## Gates

Structural only. No GPU, so no visual QA.

- Ledger: eight catalog ids moved and `sph-fluid` was added. `chromatographic-fluid` did not move. Its catalog hash is the force entry (`shaders/chromatographic-force.wgsl`), and the diffuse, interact, and phase nodes are not in that chain. Those three passes are upgraded on disk; the row stays at the 2026-10-17 force/advect/render upgrade.
- Naga 15/15. Shader gates (`npm run verify:shaders:fix`): 11/11. Gate reports under `reports/` were discarded except the ledger.
- extraBuffer: no new writes to `[0..132]`.
- Dead sliders: none new on the ten definitions.
- Shader definitions for the touched JSON: valid.
- Vitest: physarum and SPH named constants still match the CPU specs; the DLA flagship still accepts the expanded group-1 shaders and `dla-walkers` stays 64×1×1 with no `extraBuffer[` in the source.
