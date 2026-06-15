# Shader Upgrade Task: `crt-magnet`

## Metadata
- **Shader ID**: crt-magnet
- **Agent Role**: Optimizer
- **Current Size**: 3230 bytes
- **Target Line Count**: ~180 lines
- **Status**: pending

## Immutable Rules
The following MUST NOT be changed:
1. The 13-binding contract header (copy exactly).
2. The `Uniforms` struct definition.
3. `@workgroup_size` unless the shader already uses shared memory or explicit local_invocation_id math.
4. Do NOT install new npm packages.
5. Do NOT modify Renderer.ts, types.ts, or bind groups.

// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

---

## Current WGSL Source
```wgsl
// ═══════════════════════════════════════════════════════════════════
//  CRT Magnet - Alpha Translucency Edition
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Transform: Replaced RGB channel splitting with unified magnetic
//             displacement + spectral tint. Added spring-damper mouse
//             tracking and bass envelope attack/release.
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = p * 0.1031;
  let d = fract(pp.x * pp.y * 23.4517 + pp.y * 37.2314);
  let s = vec2<f32>(d + 0.113, d + 0.257);
  return fract(s * s * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
    mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    v = v + a * noise2(pp);
    pp = pp * 2.03;
    a = a * 0.5;
  }
  return v;
}

fn curl2(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.02;
  let n1 = fbm(p + vec2<f32>(e, 0.0) + t);
  let n2 = fbm(p - vec2<f32>(e, 0.0) + t);
  let n3 = fbm(p + vec2<f32>(0.0, e) + t);
  let n4 = fbm(p - vec2<f32>(0.0, e) + t);
  let dx = (n1 - n2) / (2.0 * e);
  let dy = (n3 - n4) / (2.0 * e);
  return vec2<f32>(dy, -dx);
}

fn barrel(uv: vec2<f32>, k: f32) -> vec2<f32> {
  let d = uv - 0.5;
  let r2 = dot(d, d);
  let f = 1.0 + k * r2 + k * k * r2 * r2;
  return 0.5 + d * f;
}

// ═══ Audio envelope (smooth attack/release) ═══
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

// ═══ Spring-damper (smooth mouse follow) ═══
fn spring(current: vec2<f32>, targetPos: vec2<f32>, velocity: ptr<function,vec2<f32>>, k: f32, damping: f32, dt: f32) -> vec2<f32> {
    let force = (targetPos - current) * k - *velocity * damping;
    *velocity = *velocity + force * dt;
    return current + *velocity * dt;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let time = u.config.x;
  let uvRaw = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let magnetStrength = u.zoom_params.x;
  let bloomIntensity = u.zoom_params.y;
  let colorShift = u.zoom_params.z;
  let distortionRadius = u.zoom_params.w;

  // ─── Audio envelope with attack/release ───
  var prevEnv = 0.0;
  if (global_id.x == 0u && global_id.y == 0u) {
      prevEnv = textureSampleLevel(dataTextureC, u_sampler, vec2<f32>(0.0), 0.0).r;
  }
  let env = bass_env(prevEnv, bass, 0.8, 0.15);

  // ─── Spring-damper smooth mouse tracking (read previous from dataTextureC) ───
  let smoothMouse = textureSampleLevel(dataTextureC, u_sampler, vec2<f32>(0.0), 0.0).gb;

  if (global_id.x == 0u && global_id.y == 0u) {
      var prevVel = textureSampleLevel(dataTextureC, u_sampler, vec2<f32>(1.0) / resolution, 0.0).rg;
      var vel = prevVel;
      let newPos = spring(smoothMouse, mousePos, &vel, 8.0, 0.85, 0.016);
      textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(env, newPos.x, newPos.y, 0.0));
      textureStore(dataTextureA, vec2<i32>(1, 0), vec4<f32>(vel.x, vel.y, 0.0, 0.0));
  }

  // SDF barrel distortion for CRT curvature
  let uv = barrel(uvRaw, 0.15);

  let aspect = resolution.x / resolution.y;
  let dVec = uv - smoothMouse;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  // FBM-perturbed magnetic falloff with temporal drift
  let fbmWarp = fbm(uv * 8.0 + time * 0.3) * 0.3 + 0.7;
  let radius = distortionRadius * 0.4 + 0.05;
  let falloff = exp(-dist * dist / (radius * radius * fbmWarp));

  // Depth-aware field attenuation
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvRaw, 0.0).r;
  let depthAtten = mix(0.7, 1.0, depth);

  // Audio-reactive pulse: bass drives magnet strength
  let audioPulse = env * 2.0;

  // Degaussing radial magnetic field
  let field = magnetStrength * falloff * depthAtten * (1.0 + audioPulse);

  // Curl-noise magnetic field lines
  let curl = curl2(uv * 6.0 + smoothMouse * 3.0, time * 0.2);

  // Divergence-free displacement: radial + curl swirl
  let radial = dVec * field * 4.0;
  let swirl = curl * field * 0.4;
  let displacement = radial + swirl;

  // Unified displacement — single UV sample
  let displacedUV = clamp(uv - displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // Spectral variation via mix(), NOT per-channel sampling
  let tint = vec3<f32>(1.0 + colorShift * 0.3, 1.0, 1.0 - colorShift * 0.3);
  let tintedColor = mix(baseColor, baseColor * tint, field * 0.5);

  // Bloom via single-UV blur kernel
  let bloomSize = 0.008 * bloomIntensity;
  var bloom = vec3<f32>(0.0);
  bloom += textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + vec2<f32>(bloomSize, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.25;
  bloom += textureSampleLevel(readTexture, u_sampler, clamp(displacedUV - vec2<f32>(bloomSize, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.25;
  bloom += textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + vec2<f32>(0.0, bloomSize), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.25;
  bloom += textureSampleLevel(readTexture, u_sampler, clamp(displacedUV - vec2<f32>(0.0, bloomSize), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.25;

  let luma = dot(tintedColor, vec3<f32>(0.299, 0.587, 0.114));
  let bloomThreshold = smoothstep(0.6, 1.0, luma);
  var finalColor = tintedColor + bloom * bloomThreshold * bloomIntensity * (2.0 + mids * 1.5) + vec3<f32>(treble * 0.05);

  // ═══ UNIQUE VISUAL IDEA: shadow-mask beam purity error + aperture grille ═══
  // A magnet near a CRT deflects the three electron beams by DIFFERENT amounts, so
  // each lands on the wrong colour phosphor stripe — the iconic rainbow purity
  // blotch. We sample R/G/B along progressively different deflections, scaled by
  // the field, so the channels fan apart into colour fringes only near the magnet.
  let beamR = clamp(uv - displacement * 1.35, vec2<f32>(0.0), vec2<f32>(1.0));
  let beamG = clamp(uv - displacement * 1.00, vec2<f32>(0.0), vec2<f32>(1.0));
  let beamB = clamp(uv - displacement * 0.70, vec2<f32>(0.0), vec2<f32>(1.0));
  let purityCol = vec3<f32>(
      textureSampleLevel(readTexture, u_sampler, beamR, 0.0).r,
      textureSampleLevel(readTexture, u_sampler, beamG, 0.0).g,
      textureSampleLevel(readTexture, u_sampler, beamB, 0.0).b
  );
  // Blend toward the purity-separated colour where the field is strong.
  finalColor = mix(finalColor, purityCol, clamp(field * 1.6, 0.0, 0.85));

  // Aperture-grille: the physical screen is vertical R/G/B phosphor stripes. Each
  // column lights only its own phosphor, so the magnet's purity error reads against
  // a real CRT substructure. A subtle effect that vanishes when the field is calm.
  let stripe = u32(global_id.x) % 3u;
  var grille = vec3<f32>(0.85);
  if (stripe == 0u) { grille = vec3<f32>(1.15, 0.8, 0.8); }
  else if (stripe == 1u) { grille = vec3<f32>(0.8, 1.15, 0.8); }
  else { grille = vec3<f32>(0.8, 0.8, 1.15); }
  let grilleAmt = clamp(field * 1.2, 0.0, 0.5);
  finalColor = finalColor * mix(vec3<f32>(1.0), grille, grilleAmt);

  // SDF vignette with smooth radial falloff
  let vigUV = uvRaw - 0.5;
  let vigR2 = dot(vigUV, vigUV);
  let vignette = 1.0 - smoothstep(0.25, 0.55, vigR2) * 0.6;

  // Alpha = field strength (magnetic field intensity)
  let alpha = clamp(field * 1.5 + env * 0.3, 0.0, 1.0);
  let outColor = finalColor * vignette;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));

  if (global_id.x != 0u || global_id.y != 0u) {
      textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(outColor, alpha));
  }
}

```

## Current JSON Definition
```json
{
  "id": "crt-magnet",
  "name": "CRT Magnet",
  "url": "shaders/crt-magnet.wgsl",
  "description": "Simulates a CRT monitor with degaussing magnetic distortion near the mouse using unified displacement fields and alpha translucency blending. Features spring-damper mouse tracking, bass-driven magnet pulse via audio envelope, curl-noise field lines, barrel distortion, and bloom.",
  "params": [
    {
      "id": "magnet_strength",
      "name": "Magnet Strength",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "bloom_intensity",
      "name": "Bloom Intensity",
      "default": 0.4,
      "min": 0,
      "max": 1
    },
    {
      "id": "color_shift",
      "name": "Color Shift",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "distortion_radius",
      "name": "Distortion Radius",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "depth-aware",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "noise",
    "curl",
    "fractal",
    "crt",
    "magnet",
    "bloom"
  ]
}

```

---

## Agent Specialization
# Agent Role: The Optimizer

## Identity
You are **The Optimizer**, a shader architect focused on performance, elegance, and pipeline integration.

## Upgrade Toolkit

### Performance Techniques
- Brute force → Early exit conditions
- Full resolution → Quarter-res blur + full-res combine
- Per-pixel pseudo-random → **Blue noise or Halton sequence** (same cost, less banding)
- Redundant texture samples → Bilinear LOD
- Nested loops → Unrolled small kernels
- Expensive trig → Precomputed or polynomial approximations:
  ```wgsl
  // Fast atan2 approximation (max error ~0.0015 rad)
  fn fast_atan2(y: f32, x: f32) -> f32 {
      let a = min(abs(x), abs(y)) / (max(abs(x), abs(y)) + 1e-6);
      let s = a * a;
      var r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
      if (abs(y) > abs(x)) { r = 1.5707963 - r; }
      if (x < 0.0) { r = 3.1415927 - r; }
      if (y < 0.0) { r = -r; }
      return r;
  }
  // Fast exp approximation
  fn fast_exp(x: f32) -> f32 { return exp(clamp(x, -80.0, 0.0)); }
  ```

#### 7-tap hex bokeh kernel (perceptually equals 19-tap circular at lower cost)
```wgsl
const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>( 0.0,  0.0),
    vec2<f32>( 1.0,  0.0), vec2<f32>( 0.5,  0.866),
    vec2<f32>(-0.5,  0.866), vec2<f32>(-1.0,  0.0),
    vec2<f32>(-0.5, -0.866), vec2<f32>( 0.5, -0.866),
);
```
Use for radial-blur, DOF, and glow shaders. Scale each tap by `radius / res` before sampling `readTexture`.

#### Anti-moiré LOD bias for procedural noise
```wgsl
let lod = clamp(log2(max(fwidth(uv).x, fwidth(uv).y) * cell_freq), 0.0, 4.0);
let p = uv * (cell_freq * exp2(-lod));
```
Kills the shimmer that plagues high-frequency procedural patterns (fractal / kaleidoscope shaders) when zoomed out. `cell_freq` is the base tile frequency.

### Workgroup Shared Memory (tiling pattern for blur/filter kernels)
```wgsl
var<workgroup> tile: array<array<vec4<f32>, 18>, 18>; // 16x16 + 1px border
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>,
        @builtin(local_invocation_id) lid: vec3<u32>) {
    // Load tile including borders, then sync
    tile[lid.y+1][lid.x+1] = textureSampleLevel(readTexture, u_sampler,
        vec2<f32>(gid.xy) / vec2<f32>(u.config.zw), 0.0);
    workgroupBarrier();
    // All accesses to tile[] now L1-cached — no global texture reads in hot loop
}
```

### Code Elegance
- Magic numbers → Named constants (see Algorithmist for PI/TAU/PHI/etc.)
- Duplicated code → Helper functions
- Long functions → Logical sections with comments
- Hard-coded params → Uniform-based tuning via `zoom_params`
- GPU-unfriendly ops → Precomputed lookups

### Pipeline Integration
- Standalone → Designed for slot chaining
- No feedback → Uses dataTextureA/B for state
- LDR only → HDR output ready for tone map
- Single pass → Multi-pass decomposition hint
- Fixed quality → Level-of-detail scaling

### Post-Process Ready
- Expose bloom threshold via alpha channel (`alpha = bloom_weight`)
- Tag as "expects pp-tone-map" if HDR
- Document slot recommendations
- Provide quality presets (low/medium/high)

## Quality Checklist
- [ ] No per-pixel branching on uniforms
- [ ] Texture samples minimized (caching used)
- [ ] Workgroup size optimized (16x16 for Pixelocity)
- [ ] Early exit for sky/background pixels
- [ ] LOD quality scaling based on frame time
- [ ] Anti-moiré LOD bias applied for high-frequency procedural patterns
- [ ] Hex bokeh kernel used in place of naive circular sampling where applicable

## Output Rules
- Keep the original "soul" of the shader while making it production-ready.
- Use `@workgroup_size(16, 16, 1)` unless the shader explicitly requires a different size.
- Do NOT modify the 13-binding header or the Uniforms struct.
- Preserve or enhance RGBA channel usage.
- Add JSON params if new tunable values are introduced (max 4 params mapped to zoom_params).

## Performance Constraint
This shader must remain efficient for 3-slot chained rendering. Avoid excessive nested loops, minimize texture samples, and prefer branchless math. If adding features, keep total line count within the target specified in the task metadata.


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 180 lines (±20%).
5. Write a brief upgrade rationale (2-3 sentences).

## Output Format
Return exactly two code blocks:
1. ```wgsl
[upgraded shader source]
```
2. ```json
[updated shader definition]
```

If the JSON does not need changes, return the original JSON unchanged.
