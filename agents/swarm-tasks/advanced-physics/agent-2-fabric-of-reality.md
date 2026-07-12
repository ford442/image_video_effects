# Agent 2: Fabric of Reality (Mass-Spring Cloth + Tear)

**Priority:** #2  
**Tier:** B prototype → Tier C for production solver  
**Existing prototype:** none — greenfield

---

## Mission

A mass-spring cloth grid that drapes, tears under strain, and responds to mouse as a repulsive force well. Visual: wireframe weave with psychedelic **temporal weaving** (phase-shifted strand colors), tear sparks, optional self-healing when `zoom_params.w` > 0.5.

Strange: cloth that remembers where it was torn; beautiful: silk-like specular on strands; psychedelic: gravity wells that bend the grid in non-Euclidean-looking ways.

---

## Architecture

### Particle grid

Regular 2D grid of particles stored in `dataTextureA`:

```
.rg = current position (normalized 0–1 screen space or sim space)
.ba = previous position (Verlet)
```

Read previous frame from `dataTextureC`.

### Constraints (Tier B — simplified)

**Single pass** per frame: one Jacobi-like relaxation iteration over structural + shear springs (4 neighbors). Full 3–5 iteration solver → **Tier C blocked** until graph runner.

Compute neighbor offsets from grid index (`gid.xy`). Rest length from initial grid spacing.

### Tear mask

When strain `|L - L0| / L0 > threshold` (`zoom_params.y`):

- Set tear flag in `dataTextureB.g` (0 = intact, 1 = broken)
- Optionally spawn debris into `extraBuffer` (first 256 entries: pos.xy, vel.xy)

### Render (pass 2 or 3)

`dataTextureB`: `.r` strain glow, `.g` tear, `.b` weave phase, `.a` debris age  
Draw strand lines by sampling neighbor particles; highlight tears in chromatic aberration.

---

## Mouse

- Repulsive force from `u.zoom_config.yz` when `u.zoom_config.w > 0.5`
- Ripple history: recent clicks add impulse at `u.ripples[i].xy`
- Optional: audio mids (`plasmaBuffer[0].y`) modulate stiffness

---

## Parameters

| Channel | UI name | Effect |
|---------|---------|--------|
| x | Stiffness | spring constant |
| y | Tear Threshold | strain before break |
| z | Gravity | downward bias |
| w | Self-Heal | broken springs reconnect slowly |

---

## Multipass layout (Tier B)

```
Pass 1: fabric-step.wgsl     — Verlet + 1 constraint iteration → dataTextureA
Pass 2: fabric-tear.wgsl   — strain check, tear flags → dataTextureB
Pass 3: fabric-render.wgsl — wireframe + tear VFX → writeTexture
```

Catalog id: `fabric-of-reality`

---

## Tier C upgrades (do not implement yet)

- 5× constraint iterations per frame without 5 WGSL files
- Debris particles with collision
- Material memory (strain history in `.a` channel decaying over time)
- Gravity wells from multiple ripple slots

---

## Acceptance

- [ ] `fabric-of-reality.json` + 3 WGSL passes
- [ ] 4 zoom_params with mappings
- [ ] Mouse force intentional
- [ ] Thumbnail + blurb
- [ ] Packing documented in each pass header

---

## Required reading

1. `agents/WGSL_BUILTINS_GENERATIVE.md`
2. `swarm-tasks/advanced-physics/MULTIPASS_SIM_CONTRACT.md`
3. `docs/plans/PLAN-ADVANCED-EFFECTS.md` § Fabric of Reality
4. `public/shaders/sim-fluid-feedback-field-pass1.wgsl` — mouse Gaussian impulse pattern
