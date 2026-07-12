# Agent 1: 2D Wave Equation (Ripple Tank)

**Priority:** #1 — best multipass onboarding effect  
**Tier:** B (linear 3-pass chain)  
**Base prototype:** `public/shaders/wave-equation.wgsl` + `shader_definitions/simulation/wave-equation.json`

---

## Mission

Upgrade the legacy single-pass `wave-equation` into a **3-pass ripple tank** that separates physics from visualization. The result should feel like shining a laser through a psychedelic interference tank — rainbow phase bands, caustic sparkles, mouse and click ripples, bass-driven source pulses.

Engage all three creative pillars (`notes/CREATIVE_VISION.md`): hypnotic interference (psychedelic), smooth wave normals (beautiful), phase-hue mapping that violates intuition (strange).

---

## Deliverables

| File | Role |
|------|------|
| `ripple-tank-pass1.wgsl` | Discrete Laplacian step (5×5 kernel) |
| `ripple-tank-pass2.wgsl` | Inject mouse + ripples + audio-driven sources |
| `ripple-tank-pass3.wgsl` | Normal lighting, refraction, phase hue, caustic sparkles |
| `shader_definitions/simulation/ripple-tank.json` | Catalog entry with `multipass` block |
| `public/thumbnails/ripple-tank.png` | GPU capture thumbnail |

**Option A:** New id `ripple-tank` (recommended — keeps legacy `wave-equation` stable).  
**Option B:** In-place upgrade of `wave-equation` to multipass (higher regression risk).

---

## Physics (pass 1)

Discrete wave equation on a height field `u`:

```
u_next = 2*u - u_prev + c² * dt² * ∇²u
```

Use the existing 5×5 Laplacian from `wave-equation.wgsl` (`laplacian5x5`). Read state from `dataTextureC`, write `(height, velocity, prevHeight, phase)` to `dataTextureA`.

**Packing:**

```
.r = height u
.g = velocity (or ∂u/∂t)
.b = previous height u_prev
.a = driver phase accumulator
```

---

## Injection (pass 2)

Read `dataTextureA`, write `dataTextureB`.

- **Mouse hold:** sinusoidal driver at `u.zoom_config.yz` with frequency from `zoom_params.z`
- **Ripples:** iterate `u.ripples[0..49]` — impulse on click, expanding ring optional
- **Audio:** `plasmaBuffer[0].x` (bass) boosts source amplitude; treble modulates driver frequency
- **Boundary:** `zoom_params.w` mixes absorbing vs reflecting edges (reuse edge fade from legacy shader)

---

## Render (pass 3)

Read `dataTextureB`, write `writeTexture` + commit final state to `dataTextureA` (for frame feedback copy to C).

- Finite-difference normals → diffuse + specular
- Refraction offset on `readTexture`
- Phase → HSV rainbow (`hsv2rgb` from legacy)
- `pow(abs(laplacian), 2)` caustic sparks
- Depth-aware compositing from `readDepthTexture`

---

## Parameters (`zoom_params`)

| Channel | UI name | Range | Effect |
|---------|---------|-------|--------|
| x | Wave Speed | 0–1 | `c` in wave equation |
| y | Damping | 0–1 | velocity decay per step |
| z | Source Strength | 0–1 | mouse/ripple/audio injection |
| w | Boundary Reflect | 0–1 | edge absorption vs reflection |

All four need `mapping` fields in JSON.

---

## Multipass JSON

```json
{
  "id": "ripple-tank",
  "name": "Ripple Tank",
  "url": "shaders/ripple-tank-pass1.wgsl",
  "description": "Psychedelic 2D wave interference — click to drop ripples, drag to stir, bass pulses the tank.",
  "features": ["simulation", "multi-pass", "mouse-driven", "audio-reactive", "physics"],
  "multipass": {
    "pass": 1,
    "totalPasses": 3,
    "nextShader": "ripple-tank-pass2",
    "passes": [
      { "pass": 1, "name": "Wave step", "file": "ripple-tank-pass1.wgsl" },
      { "pass": 2, "name": "Inject sources", "file": "ripple-tank-pass2.wgsl" },
      { "pass": 3, "name": "Render", "file": "ripple-tank-pass3.wgsl" }
    ]
  }
}
```

Pass 2 JSON entry: `"nextShader": "ripple-tank-pass3"`. Pass 3: `"nextShader": null`.  
Only **one** catalog JSON (`ripple-tank.json`). Pass 2/3 WGSL only.

After editing JSON: `node scripts/buildMultipassRegistry.js`.

---

## Performance

- Workgroup: `@workgroup_size(16, 16, 1)`
- Target grid: full resolution; optional half-res sim noted in header if FPS < 45
- Run **one** Laplacian step per frame in pass 1 (not 2–4 internal substeps until graph runner)

---

## Acceptance

- [ ] Generator + orphan audit green
- [ ] 4 `zoom_params` with mappings
- [ ] Mouse + audio intentional
- [ ] Thumbnail + showcase blurb
- [ ] Header documents RGBA packing

---

## Required reading

1. `agents/WGSL_BUILTINS_GENERATIVE.md` — binding header verbatim
2. `swarm-tasks/advanced-physics/MULTIPASS_SIM_CONTRACT.md`
3. `public/shaders/wave-equation.wgsl` — port Laplacian + visualization
4. `public/shaders/sim-fluid-feedback-field-pass1.wgsl` — multipass + mouse pattern
