# Agent 5C: Atomic-Feedback Conjurer
## Task Specification - Phase C, Agent 5

**Role:** Hybrid-Technique Creator (atomics, complex fields, aggregation, iso-lines)
**Priority:** HIGH (four showcase shaders that close out Phase C)
**Target:** Create 4 mouse-responsive shaders combining atomic voting, agent aggregation, iso-extraction, and complex wavefunction evolution
**Estimated Duration:** 5-6 days

---

## Mission

This agent ships four "crown-jewel" shaders that each introduce a distinct technique the library has **never** hosted:

1. **Hough Cathedral** — atomic voting in parameter space → detected lines emit godrays.
2. **DLA Crystal Garden** — multi-agent aggregation with atomic write-once flags.
3. **Metaball Lava Lamp** — marching-squares iso-line extraction.
4. **Schrödinger Conductor** — complex-valued wavefunction evolution (quantum psychedelia).

Each is visually spectacular and together they prove that the 13-binding contract is expressive enough for almost any modern compute-shader technique.

---

## Shader Concepts

### 1. `hough-cathedral` (3-pass: edge-detect, vote, render)

**Concept:** Detect straight lines in the image via the **Hough transform**. Each edge pixel "votes" into a (ρ, θ) accumulator using atomicAdd. Strong bins correspond to real lines. The mouse selects an (ρ, θ) region to "resonate" — rays glow along every line that matches, turning the image into a stained-glass cathedral of intersecting light beams.

**Complexity:** High
**Primary Techniques:**
- Sobel edge detection
- **Atomic voting** into a 2D parameter-space accumulator (ρ, θ)
- Ray-casting from mouse-selected (ρ, θ) bin

**RGBA32FLOAT packing (Hough bin):**
```
dataTextureA (ρ × θ accumulator, atomic u32 reinterpret)
  .r = vote count (stored via bitcast<f32>(atomic u32) trick, or use int texture if supported)
  .g = θ (precomputed for render pass)
  .b = ρ
  .a = age (decays over time)
```
(If atomics on `rgba32float` storage textures aren't supported on the target device, use `extraBuffer` as an `array<atomic<u32>>` accumulator sized ρ_bins × θ_bins. This is the safer path and documented below.)

**Binding usage:**
- `readTexture` (1): image
- `writeTexture` (2): cathedral composite
- `dataTextureA` (7): edge-map + orientation
- `dataTextureB` (8): visualized accumulator (for rendering)
- `extraBuffer` (10): `array<atomic<u32>>` of size 180 × 200 = 36,000 bins

```wgsl
// Pass 1: Sobel edge magnitude + orientation
let Gx = sobel_x(pix);
let Gy = sobel_y(pix);
let mag = length(vec2<f32>(Gx, Gy));
let ang = atan2(Gy, Gx);
textureStore(dataTextureA, pix, vec4<f32>(mag, ang, f32(Gx), f32(Gy)));
```

```wgsl
// Pass 2: every pixel above a threshold votes for its (ρ, θ) line
let edge = textureLoad(dataTextureA, pix, 0);
if (edge.r > u.zoom_params.x) {
    let theta = edge.g;
    let rho = f32(pix.x) * cos(theta) + f32(pix.y) * sin(theta);
    // Bin indices
    let theta_bin = u32((theta + 3.14159) / 6.2831853 * 180.0);
    let rho_max = length(vec2<f32>(u.config.z, u.config.w));
    let rho_bin = u32((rho + rho_max) / (2.0 * rho_max) * 200.0);
    let idx = theta_bin * 200u + rho_bin;
    atomicAdd(&extraBuffer_as_atomic[idx], 1u);
}
```

```wgsl
// Pass 3: render — for each pixel, compute "is it on a line that the mouse selected?"
let mouse_theta = u.zoom_config.y * 3.14159;
let mouse_rho_norm = u.zoom_config.z * 2.0 - 1.0;
let rho_max = length(vec2<f32>(u.config.z, u.config.w));
let mouse_rho = mouse_rho_norm * rho_max;

// Check: does this pixel lie close to the line (mouse_rho, mouse_theta)?
let pixel_rho = f32(pix.x) * cos(mouse_theta) + f32(pix.y) * sin(mouse_theta);
let line_dist = abs(pixel_rho - mouse_rho);
let glow = exp(-line_dist * line_dist / (u.zoom_params.y * 10.0)) * u.zoom_config.w;

// Plus, sample the accumulator near the mouse and light up any neighbor that is strong
var neighborhood_strength = 0.0;
for (var dt = -3; dt <= 3; dt++) {
    let theta_bin = i32((mouse_theta + 3.14159) / 6.2831853 * 180.0) + dt;
    let rho_bin = i32((mouse_rho + rho_max) / (2.0 * rho_max) * 200.0);
    let idx = u32(theta_bin) * 200u + u32(rho_bin);
    let count = f32(atomicLoad(&extraBuffer_as_atomic[idx]));
    neighborhood_strength += count;
}
let final_color = src_image + palette(mouse_theta) * glow * u.zoom_params.z
                              + vec3<f32>(neighborhood_strength * 0.001 * u.zoom_params.w);
```

**Visual:** Urban photos blossom into cathedral light: every vertical edge shoots a spear of colored light skyward, every horizontal edge flows horizontal godrays. The mouse acts like an organist pulling stops — selecting a (ρ,θ) region highlights all the lines in that family.

**Params:**
- x: Edge vote threshold
- y: Line-proximity sharpness
- z: Godray intensity
- w: Accumulator decay (new: needs a pre-pass to multiply all bins by `1 - w*dt`)

**RGB-from-RGBA strategy:** Source alpha scales vote weight. Output RGB.

---

### 2. `dla-crystal-garden` (2-pass: walker-update, render)

**Concept:** Diffusion-Limited Aggregation. Thousands of Brownian walkers stored in `extraBuffer` wander across the canvas. When a walker touches an occupied pixel, it *sticks* (written atomically to `dataTextureA.a`). Mouse clicks drop a new seed; drags release fresh walkers. Over time, crystalline dendrites grow from each seed.

**Complexity:** High
**Primary Techniques:**
- **Stateful particle array** in `extraBuffer` (pos + rng-state)
- **Atomic write-once** to mark occupied pixels
- Deterministic per-walker PRNG (PCG) seeded by walker index and frame

**RGBA32FLOAT packing:**
```
dataTextureA.r = age of this aggregated pixel
dataTextureA.g = crystal branch direction (angle)
dataTextureA.b = HDR glow intensity
dataTextureA.a = occupied flag (0 or 1)
extraBuffer     = array<vec4<f32>>: (x, y, rng_state, seed_id) per walker
```

**Binding usage:**
- `readTexture` (1): optional background image that colors the crystals
- `writeTexture` (2): rendered crystal garden
- `dataTextureA` (7): occupancy + age + color
- `extraBuffer` (10): walker state (up to 8192 walkers = 32 KB)

```wgsl
// Walker update kernel: @workgroup_size(64,1,1), global_id.x = walker index
@compute @workgroup_size(64, 1, 1)
fn walker_step(@builtin(global_invocation_id) gid: vec3<u32>) {
    let w = extraBuffer[gid.x];          // (x, y, rng, seed_id)
    var rng = bitcast<u32>(w.z);

    // Respawn walker near mouse if mouse is pressed
    if (u.zoom_config.w > 0.5 && pcg_float(&rng) < 0.001) {
        let mp = u.zoom_config.yz * u.config.zw;
        extraBuffer[gid.x] = vec4<f32>(mp.x + (pcg_float(&rng) - 0.5) * 40.0,
                                       mp.y + (pcg_float(&rng) - 0.5) * 40.0,
                                       bitcast<f32>(rng), w.w);
        return;
    }

    // Brownian step
    var nx = w.x + (pcg_float(&rng) - 0.5) * 2.0;
    var ny = w.y + (pcg_float(&rng) - 0.5) * 2.0;

    // Check 4-neighborhood for aggregation
    let pix = vec2<i32>(i32(nx), i32(ny));
    var should_stick = false;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        let nb = textureLoad(dataTextureA, pix + vec2<i32>(dx,dy), 0);
        if (nb.a > 0.5) { should_stick = true; break; }
      }
    }
    if (should_stick) {
        let age_here = u.config.x;
        let branch_dir = atan2(ny - w.y, nx - w.x);
        // Write crystal pixel (not atomic, but only one walker writes per step — safe enough for v1)
        textureStore(dataTextureA, pix, vec4<f32>(age_here, branch_dir, 1.0, 1.0));
        // Respawn walker at seed
        extraBuffer[gid.x] = vec4<f32>(u.ripples[i32(w.w)].x * u.config.z,
                                       u.ripples[i32(w.w)].y * u.config.w,
                                       bitcast<f32>(rng), w.w);
    } else {
        extraBuffer[gid.x] = vec4<f32>(nx, ny, bitcast<f32>(rng), w.w);
    }
}
```

**Visual:** Snowflake-like crystal fractals grow outward from each click, tendrils reaching toward walkers. Click repeatedly in different places → each seed grows its own flower that eventually meets its neighbors. With a backdrop image, each crystal takes on the color of the pixels it grows into.

**Params:**
- x: Walker step size
- y: Stick probability (0 = never, 1 = always when near)
- z: Glow decay over age
- w: Walker respawn rate

**RGB-from-RGBA strategy:** Colors sampled from input RGB at the aggregation point; alpha from input = stickiness modulator (transparent pixels are "anti-stick" — crystals grow around holes).

---

### 3. `metaball-lava-lamp` (2-pass: field, extract)

**Concept:** Classic lava-lamp metaballs with a **marching-squares** iso-line extractor. Mouse = one of the metaballs (drags the lamp around). The other metaballs drift with perlin-noise velocities. Pass 2 extracts both the solid iso-band and a crisp contour line — producing a look that's half 70s poster, half topographic map.

**Complexity:** Medium-High
**Primary Techniques:**
- **Metaball scalar field**: `f(x) = Σ r²/|x - cᵢ|²`
- **Marching-squares** lookup table (16 cases → bitmask → segment endpoints)
- Contour line rendered as an anti-aliased stroke

**RGBA32FLOAT packing:**
```
dataTextureA.r = scalar field value
dataTextureA.g = ∂f/∂x
dataTextureA.b = ∂f/∂y
dataTextureA.a = iso-band membership (smoothstep)
extraBuffer = 12 metaballs × (pos, radius, hue) = 48 floats
```

**Binding usage:**
- `readTexture` (1): backdrop
- `writeTexture` (2): final render
- `dataTextureA` (7): field + gradient
- `extraBuffer` (10): metaball positions + velocities

```wgsl
// Pass 1: sum up metaball contributions
var f = 0.0;
var grad = vec2<f32>(0.0);
let p = vec2<f32>(pix);
for (var i = 0u; i < 12u; i++) {
    let ball = extraBuffer_balls[i];  // .xy=pos, .z=r, .w=hue
    let d  = p - ball.xy;
    let d2 = max(dot(d, d), 1.0);
    let r2 = ball.z * ball.z;
    f += r2 / d2;
    grad -= 2.0 * r2 * d / (d2 * d2);
}
// Replace last metaball with mouse every frame
if (u.zoom_config.w > 0.5) {
    let mp = u.zoom_config.yz * u.config.zw;
    let dm = p - mp; let dm2 = max(dot(dm,dm), 1.0);
    f += u.zoom_params.x * 10000.0 / dm2;
}

let iso = u.zoom_params.y * 0.01 + 0.005;
let membership = smoothstep(iso, iso * 1.2, f);
textureStore(dataTextureA, pix, vec4<f32>(f, grad, membership));
```

```wgsl
// Pass 2: marching squares — classify the 4 corners of each cell
let v00 = textureLoad(dataTextureA, pix + vec2<i32>(0,0), 0).r;
let v10 = textureLoad(dataTextureA, pix + vec2<i32>(1,0), 0).r;
let v01 = textureLoad(dataTextureA, pix + vec2<i32>(0,1), 0).r;
let v11 = textureLoad(dataTextureA, pix + vec2<i32>(1,1), 0).r;
let iso = u.zoom_params.y * 0.01 + 0.005;
let code = u32(v00 > iso) | (u32(v10 > iso) << 1u) | (u32(v11 > iso) << 2u) | (u32(v01 > iso) << 3u);

// Distance to iso-segment inside this cell (using gradient approximation)
let segment_dist = iso_segment_distance(code, vec2<f32>(fract_pix), vec4<f32>(v00,v10,v11,v01), iso);
let line_glow = exp(-segment_dist * segment_dist * u.zoom_params.z * 200.0);

// Composite
let fill = membership_from_dataA * palette(hue_from_nearest_ball);
let out  = mix(backdrop, fill + line_glow * vec3<f32>(2.0, 0.5, 0.9), u.zoom_params.w);
```

**Visual:** Living lava-lamp forms with a crisp contour line stroked around every blob. The mouse is always the brightest, most attractive metaball; others lazily drift and merge with it. Switching backdrop images produces different color palettes for the fills.

**Params:**
- x: Mouse ball strength
- y: Iso-level (thick vs. thin forms)
- z: Contour line crispness
- w: Backdrop vs. metaball opacity

**RGB-from-RGBA strategy:** Input alpha darkens the backdrop showthrough, so transparent regions let the metaballs shine brighter. Output RGB.

---

### 4. `schrodinger-conductor` (2-pass: evolve, render)

**Concept:** Solve the 2D time-dependent Schrödinger equation `iℏ ∂ψ/∂t = −(ℏ²/2m)∇²ψ + V(x,y)ψ`. The wavefunction ψ is a **complex-valued field** stored as (Re, Im) in `rgba32float`. Mouse clicks drop Gaussian wave packets with momentum equal to the mouse's velocity. The rendered image shows `|ψ|²` (probability density) with phase-colored rainbow.

**Complexity:** Very High
**Primary Techniques:**
- **Split-step** operator: Laplacian via 5-tap, potential via mouse-painted well
- Complex-number arithmetic in `rgba32float` (Re, Im)
- Phase rendering: `color = palette(arg(ψ))` with intensity `|ψ|²`

**RGBA32FLOAT packing (Complex field):**
```
dataTextureA.r = Re(ψ)
dataTextureA.g = Im(ψ)
dataTextureA.b = Re(V) potential (painted by mouse hold)
dataTextureA.a = |ψ|² (cached)
```

**Binding usage:**
- `readTexture` (1): optional — used to seed the initial potential from image luminance
- `writeTexture` (2): rendered |ψ|²
- `dataTextureA` (7): current complex field
- `dataTextureB` (8): next-step complex field (ping-pong)

```wgsl
// Pass 1: evolve one timestep
let psi  = textureLoad(dataTextureA, pix, 0).xy;
let psiN = textureLoad(dataTextureA, pix + vec2<i32>( 0,-1), 0).xy;
let psiS = textureLoad(dataTextureA, pix + vec2<i32>( 0, 1), 0).xy;
let psiE = textureLoad(dataTextureA, pix + vec2<i32>( 1, 0), 0).xy;
let psiW = textureLoad(dataTextureA, pix + vec2<i32>(-1, 0), 0).xy;
let lap = psiN + psiS + psiE + psiW - 4.0 * psi;

// i·(∂ψ/∂t) = -0.5·∇²ψ + V·ψ  →  ∂ψ/∂t = i(0.5·∇²ψ - V·ψ)
// Multiplying by i: (a + ib)·i = -b + ia
let V = textureLoad(dataTextureA, pix, 0).z;
let kinetic = 0.5 * lap;
let potential = vec2<f32>(psi.x * V, psi.y * V);
let rhs = kinetic - potential;
let i_rhs = vec2<f32>(-rhs.y, rhs.x);
let dt = u.zoom_params.x * 0.3;
var new_psi = psi + dt * i_rhs;

// Mouse: inject wave packet with momentum
if (u.zoom_config.w > 0.5) {
    let mp = u.zoom_config.yz * u.config.zw;
    let d = vec2<f32>(pix) - mp;
    let mv = mouse_velocity_from_ripples();
    let env = exp(-dot(d,d) / (u.zoom_params.y * 500.0));
    // Plane wave with mouse-momentum k
    let phase = dot(d, mv) * u.zoom_params.w;
    new_psi.x += env * cos(phase) * 0.5;
    new_psi.y += env * sin(phase) * 0.5;
}

// Normalization (crude): prevent explosion
let prob = dot(new_psi, new_psi);
new_psi *= 1.0 / (1.0 + prob * 0.0001);

textureStore(dataTextureB, pix, vec4<f32>(new_psi.x, new_psi.y, V, prob));
```

```wgsl
// Pass 2: render |ψ|² with phase hue
let s = textureLoad(dataTextureA, pix, 0);
let mag = sqrt(s.w);
let phase = atan2(s.y, s.x);
let hue = (phase / 6.2831853) + 0.5;
let col = hsv_to_rgb(vec3<f32>(hue, 0.85, 1.0)) * pow(mag, 0.7) * u.zoom_params.z;
```

**Visual:** A living quantum field. Clicking drops a wave packet with momentum in the drag direction — it propagates, interferes with reflections, tunnels through low-potential regions, forms standing waves. Long-press paints a potential well and the wavefunction pools into it like water into a gravity dimple. The phase-colored render makes every fringe glow with rainbow interference.

**Params:**
- x: Timestep dt
- y: Wave-packet width σ
- z: Render brightness (|ψ| to display gain)
- w: Momentum amplification (how fast dropped packets travel)

**RGB-from-RGBA strategy:** Input image luminance seeds the initial potential V on first frame — bright = low potential, dark = high potential. Alpha shapes a soft "absorbing boundary" that prevents reflections from the screen edge. Output RGB.

---

## Deliverables

| File | Lines | Notes |
|------|-------|-------|
| `public/shaders/hough-cathedral-sobel.wgsl` | ~60 | Edge + orientation |
| `public/shaders/hough-cathedral-vote.wgsl` | ~60 | atomicAdd into extraBuffer |
| `public/shaders/hough-cathedral-render.wgsl` | ~80 | Mouse-selected beam rendering |
| `shader_definitions/advanced-hybrid/hough-cathedral.json` | ~100 | |
| `public/shaders/dla-crystal-garden-walker.wgsl` | ~100 | Walker step, @workgroup_size(64,1,1) |
| `public/shaders/dla-crystal-garden-render.wgsl` | ~60 | Age + glow composite |
| `shader_definitions/advanced-hybrid/dla-crystal-garden.json` | ~90 | |
| `public/shaders/metaball-lava-lamp-field.wgsl` | ~80 | Scalar field sum |
| `public/shaders/metaball-lava-lamp-extract.wgsl` | ~100 | Marching squares |
| `shader_definitions/advanced-hybrid/metaball-lava-lamp.json` | ~90 | |
| `public/shaders/schrodinger-conductor-evolve.wgsl` | ~100 | Complex evolution |
| `public/shaders/schrodinger-conductor-render.wgsl` | ~60 | Phase-colored density |
| `shader_definitions/advanced-hybrid/schrodinger-conductor.json` | ~90 | |

---

## Validation Checklist

- [ ] Hough vote counts scale linearly with edge density in a test image.
- [ ] DLA walkers: after 1000 frames with a single seed, crystal should span ≥40% of screen.
- [ ] Marching-squares lookup: all 16 case codes produce a valid iso-line segment.
- [ ] Schrödinger: plane-wave packet preserves probability within ±5% over 100 steps.
- [ ] All four shaders honor the 13-binding contract.
- [ ] `schrodinger-conductor` is the library's first **complex-valued field** shader; document in SHADER_AUDIT.md.
