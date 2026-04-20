# Agent 3C: True-Fluid Engineer
## Task Specification - Phase C, Agent 3

**Role:** Incompressible Navier-Stokes Specialist
**Priority:** HIGH (elevates fluid shaders from "advection" to "real CFD")
**Target:** Create 2 mouse-responsive fluid shaders with full pressure projection and vorticity confinement
**Estimated Duration:** 4-5 days

---

## Mission

Every fluid shader in the library today (`navier-stokes-dye`, `sim-fluid-feedback-field`, `hyper-tensor-fluid`, `hybrid-particle-fluid`) advects a velocity field without enforcing incompressibility. As a result, dye piles up and the sim eventually goes unstable or diffuses into a flat gray wash. Phase C introduces Jos Stam's "Stable Fluids" pipeline in full: **advect → apply force → divergence → Jacobi pressure solve → subtract pressure gradient → advect dye**. Adding **vorticity confinement** (Fedkiw-Stam-Jensen) restores the small-scale curly detail that low-order advection schemes smear away.

Both shaders feel profoundly different from the library's current fluid shaders: dye actually *rotates* instead of just smearing, edges of splatted color spiral into beautiful vortices, and the mouse feels like stirring real paint in water.

---

## Shader Concepts

### 1. `stable-fluid-painter` (7-pass: advect-vel, force-splat, divergence, jacobi×4, project, advect-dye, render)

**Concept:** A full incompressible 2D fluid with mouse as a directional paint-and-push brush. The mouse's velocity vector is injected as force; the input image is dropped in as dye on first frame and then swirled indefinitely.

**Complexity:** Very High
**Primary Techniques:**
- **Semi-Lagrangian advection** (backtrace + bilinear fetch)
- **Jacobi iteration** for `∇²p = ∇·v` (ping-pong across 20-40 iterations per frame via multi-pass or a for-loop)
- Pressure-gradient subtraction to enforce `∇·v = 0`
- Mouse velocity decoded from ripple history

**RGBA32FLOAT packing (stable-fluid):**
```
dataTextureA.r = vx
dataTextureA.g = vy
dataTextureA.b = divergence ∇·v  (pass 3)
dataTextureA.a = pressure p      (updated in Jacobi passes)
dataTextureB.rgb = dye color (HDR, can exceed 1.0)
dataTextureB.a   = dye age (for optional decay)
```

**Binding usage:**
- `readTexture` (1): initial dye source image
- `writeTexture` (2): final rendered output
- `dataTextureA` (7): velocity/divergence/pressure state
- `dataTextureB` (8): dye state (HDR)
- `dataTextureC` (9): previous frame's velocity (needed because advection reads prior state)
- `extraBuffer` (10): rolling 16-entry mouse history used to derive a smooth velocity vector

```wgsl
// Pass 1: semi-Lagrangian velocity advection
let v  = textureLoad(dataTextureC, pix, 0).xy;
let back = vec2<f32>(pix) - v * u.zoom_params.x;   // dt = params.x
let v_adv = bilinear_velocity(back);               // helper samples dataTextureC
textureStore(dataTextureA, pix, vec4<f32>(v_adv, 0.0, 0.0));
```

```wgsl
// Pass 2: mouse force injection
// Decode mouse velocity from the last two ripple entries
let n = i32(u.config.y) % 50;
let r0 = u.ripples[n];
let r1 = u.ripples[(n + 49) % 50];
let mouse_vel = (r0.xy - r1.xy) / max(r0.z - r1.z, 0.016);
let mp = r0.xy * u.config.zw;
let d  = distance(vec2<f32>(pix), mp);
let kernel = exp(-d*d / (u.zoom_params.y * 500.0));
var v = textureLoad(dataTextureA, pix, 0);
v.x += mouse_vel.x * kernel * u.zoom_config.w * 40.0;
v.y += mouse_vel.y * kernel * u.zoom_config.w * 40.0;
textureStore(dataTextureA, pix, v);
```

```wgsl
// Pass 3: compute divergence
let vL = textureLoad(dataTextureA, pix + vec2<i32>(-1,0), 0).xy;
let vR = textureLoad(dataTextureA, pix + vec2<i32>( 1,0), 0).xy;
let vB = textureLoad(dataTextureA, pix + vec2<i32>(0,-1), 0).xy;
let vT = textureLoad(dataTextureA, pix + vec2<i32>(0, 1), 0).xy;
let divergence = 0.5 * ((vR.x - vL.x) + (vT.y - vB.y));
var s = textureLoad(dataTextureA, pix, 0);
s.z = divergence;
s.w = 0.0;   // zero pressure before Jacobi
textureStore(dataTextureA, pix, s);
```

```wgsl
// Pass 4..7: 4 Jacobi iterations, reading `.a` and writing next `.a`
// Alternate read/write between dataTextureA and dataTextureB.a to ping-pong
let pL = textureLoad(src_tex, pix + vec2<i32>(-1,0), 0).w;
let pR = textureLoad(src_tex, pix + vec2<i32>( 1,0), 0).w;
let pB = textureLoad(src_tex, pix + vec2<i32>(0,-1), 0).w;
let pT = textureLoad(src_tex, pix + vec2<i32>(0, 1), 0).w;
let div = textureLoad(dataTextureA, pix, 0).z;
let p_new = 0.25 * (pL + pR + pB + pT - div);
```

```wgsl
// Pass 8: project (subtract pressure gradient)
let pL = textureLoad(dataTextureA, pix + vec2<i32>(-1,0), 0).w;
let pR = textureLoad(dataTextureA, pix + vec2<i32>( 1,0), 0).w;
let pB = textureLoad(dataTextureA, pix + vec2<i32>(0,-1), 0).w;
let pT = textureLoad(dataTextureA, pix + vec2<i32>(0, 1), 0).w;
var v = textureLoad(dataTextureA, pix, 0);
v.x -= 0.5 * (pR - pL);
v.y -= 0.5 * (pT - pB);
textureStore(dataTextureA, pix, v);
```

```wgsl
// Pass 9: advect dye by the now-divergence-free velocity
let v = textureLoad(dataTextureA, pix, 0).xy;
let back = vec2<f32>(pix) - v * u.zoom_params.x;
let dye = bilinear_dye(back);
let injected = select(vec3<f32>(0.0), textureLoad(readTexture, pix, 0).rgb, u.zoom_config.w > 0.5) * u.zoom_params.z;
textureStore(dataTextureB, pix, vec4<f32>(dye + injected, 1.0));
```

**Visual:** The image shatters into pigment and swirls under your cursor; mouse drags pull sheets of color that twist into real vortices instead of smearing; stopping the mouse lets the paint settle into beautiful Kelvin-Helmholtz instability waves.

**Params:**
- x: Timestep (advection strength, 0 = frozen, 1 = wild)
- y: Brush size (force kernel σ in pixels)
- z: Dye injection rate (0 = no new dye, 1 = continuous flood)
- w: Pressure solve iterations mapped 0-1 → 10-40 (precision vs. speed tradeoff)

**RGB-from-RGBA strategy:** Source alpha controls **how easily dye is displaced** — fully-opaque source is a "fixed pigment" that advects slowly, transparent regions are "water" that advects fast. Output alpha fixed at 1.

---

### 2. `vorticity-smoke` (4-pass: advect-vel, curl, confinement-force, advect-density)

**Concept:** A compressible smoke-like fluid with **vorticity confinement** that artificially re-injects small-scale curl that numerical diffusion destroyed. The result is wispy, tendril-y smoke that lingers and dances instead of diffusing into a cloud. Mouse clicks release puffs; mouse drags are wind.

**Complexity:** High
**Primary Techniques:**
- Backtrace advection
- **Curl computation**: `ω = ∂vy/∂x − ∂vx/∂y`
- **Vorticity confinement force**: `f = ε·h·(N × ω_z)` where `N = ∇|ω|/|∇|ω||`
- Density advection with temperature-driven buoyancy

**RGBA32FLOAT packing (vorticity field):**
```
dataTextureA.r = vx
dataTextureA.g = vy
dataTextureA.b = curl ω_z
dataTextureA.a = density ρ (also acts as "smoke amount")
```

**Binding usage:**
- `readTexture` (1): optional source that seeds color of smoke puffs
- `writeTexture` (2): composited smoke + backdrop
- `dataTextureA` (7): full vorticity state (as above)
- `dataTextureB` (8): colored density (HDR RGB trail)
- `dataTextureC` (9): previous frame's state for advection

```wgsl
// Pass 2: curl
let vT = textureLoad(dataTextureA, pix + vec2<i32>(0, 1), 0).xy;
let vB = textureLoad(dataTextureA, pix + vec2<i32>(0,-1), 0).xy;
let vL = textureLoad(dataTextureA, pix + vec2<i32>(-1,0), 0).xy;
let vR = textureLoad(dataTextureA, pix + vec2<i32>( 1,0), 0).xy;
let curl = 0.5 * ((vR.y - vL.y) - (vT.x - vB.x));
var s = textureLoad(dataTextureA, pix, 0); s.z = curl;
textureStore(dataTextureA, pix, s);
```

```wgsl
// Pass 3: vorticity confinement force
let wL = abs(textureLoad(dataTextureA, pix + vec2<i32>(-1, 0), 0).z);
let wR = abs(textureLoad(dataTextureA, pix + vec2<i32>( 1, 0), 0).z);
let wB = abs(textureLoad(dataTextureA, pix + vec2<i32>( 0,-1), 0).z);
let wT = abs(textureLoad(dataTextureA, pix + vec2<i32>( 0, 1), 0).z);
let grad_w = vec2<f32>(wR - wL, wT - wB);
let N = normalize(grad_w + 1e-6);
let curl_here = textureLoad(dataTextureA, pix, 0).z;
let force = u.zoom_params.x * vec2<f32>(N.y * curl_here, -N.x * curl_here);

// Add mouse drag force
let mv = mouse_velocity_from_ripples();
let d  = distance(vec2<f32>(pix), mouse_pix());
let f_mouse = mv * exp(-d*d / (u.zoom_params.y * 800.0)) * u.zoom_config.w;

var state = textureLoad(dataTextureA, pix, 0);
state.x += (force.x + f_mouse.x) * u.zoom_params.w;
state.y += (force.y + f_mouse.y) * u.zoom_params.w + state.a * 0.01; // buoyancy
textureStore(dataTextureA, pix, state);
```

**Visual:** Smoke that actually *curls* instead of diffusing — release a puff and watch vortex rings travel across the screen, wakes form behind mouse drags, Kelvin-Helmholtz braids appear at shear layers. With colored puffs (sampled from the image), the result is a stained-glass fire-dance.

**Params:**
- x: Confinement ε (0 = pure advection/blurry, 1 = hyper-detailed tendrils)
- y: Brush size
- z: Density decay rate (how fast smoke fades)
- w: Force amplifier

**RGB-from-RGBA strategy:** Source image alpha = "fuel availability" — puffs sampled from high-alpha regions burn longer. Output RGB composites density×color over the backdrop; alpha always 1.

---

## Deliverables

| File | Lines | Notes |
|------|-------|-------|
| `public/shaders/stable-fluid-painter-advect.wgsl` | ~60 | Semi-Lagrangian |
| `public/shaders/stable-fluid-painter-force.wgsl` | ~60 | Mouse splat + inject |
| `public/shaders/stable-fluid-painter-divergence.wgsl` | ~40 | `∇·v` |
| `public/shaders/stable-fluid-painter-jacobi.wgsl` | ~50 | Parameterized iteration |
| `public/shaders/stable-fluid-painter-project.wgsl` | ~50 | Subtract gradient |
| `public/shaders/stable-fluid-painter-dye.wgsl` | ~60 | Advect + inject dye |
| `shader_definitions/simulation/stable-fluid-painter.json` | ~140 | 7-pass chain (jacobi listed 4-20 times) |
| `public/shaders/vorticity-smoke-curl.wgsl` | ~50 | `ω_z` |
| `public/shaders/vorticity-smoke-confine.wgsl` | ~70 | Confinement + mouse |
| `public/shaders/vorticity-smoke-advect.wgsl` | ~60 | Density advection |
| `shader_definitions/simulation/vorticity-smoke.json` | ~100 | |

---

## Validation Checklist

- [ ] Stable-fluid-painter: after pressure solve, measured divergence < 1e-3 RMS.
- [ ] Jacobi iteration count scalable via `u.zoom_params.w` (UI slider).
- [ ] Vorticity-smoke: curl magnitude sustained over 3+ seconds (confinement working).
- [ ] No NaN or Inf after 10 minutes of idle simulation.
- [ ] Mouse velocity decoded correctly from ripples (logs match cursor motion).
- [ ] Both shaders use only the 13-binding contract.
