# Swarm Brief: gravito-phononic-accretion

**Role:** Optimizer
**Name:** Gravito-Phononic Accretion
**Category:** generative
**Description:** SPH density estimation around orbiting accretors with cubic-spline kernel, shock-wave detection, and temperature-based blackbody coloring. Bass adds mass to primaries, mids drive orbital precession, treble creates acoustic standing waves. Mouse introduces a rogue body with tidal forces. Ripples seed density perturbations.
**Current lines:** 179
**Target lines:** 229–269 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. This shader is heavily optimized AND has a mislabeled slider. Make the label honest without disturbing the fast paths:
- Make 'Lensing Strength' honest: it currently just adds tone gain. Wire it to real gravitational lensing - bend the sampling uv around each accretor by p2 * mass / dist^2 (clamped) before density reads, so mass visibly warps the background field.
- Diffusion-controlled persistence: let Material Diffusion also set the advected-density persistence via flowed * mix(0.90, 0.99, p3), so the slider controls both kernel spread and trail longevity.
- Treble relativistic jet: on treble transients, emit a thin vertical beam glow from the primary accretor (perpendicular to the orbital plane), fading over ~0.5s.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the 7-tap hex kernel, fast_exp clamps, and branchless mouse-mass zeroing - they are deliberate optimizations. dataTextureA = SIM STATE (density, temp, shock) - no clamping. Output is PREMULTIPLIED ALPHA (tone * alpha, alpha): do not add a tonemap after it or double-multiply. Keep the min(u.config.y, 50u) ripples guard.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins - persistent shader state goes in [133..255] ONLY.

## JSON Parameters / Controls

```json
{
  "id": "gravito-phononic-accretion",
  "name": "Gravito-Phononic Accretion",
  "url": "shaders/gravito-phononic-accretion.wgsl",
  "category": "generative",
  "description": "SPH density estimation around orbiting accretors with cubic-spline kernel, shock-wave detection, and temperature-based blackbody coloring. Bass adds mass to primaries, mids drive orbital precession, treble creates acoustic standing waves. Mouse introduces a rogue body with tidal forces. Ripples seed density perturbations.",
  "features": [
    "SPH-density",
    "orbital-velocity",
    "shock-detection",
    "blackbody",
    "audio-driven",
    "mouse-rogue-body",
    "ripple-perturbation",
    "temporal"
  ],
  "tags": [
    "gravitational",
    "accretion",
    "cosmic",
    "organic",
    "audio-reactive",
    "lensing",
    "blackbody",
    "HDR"
  ],
  "params": [
    {
      "id": "accretionSpeed",
      "name": "Accretion Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "How fast material collects around gravitational centers"
    },
    {
      "id": "lensing",
      "name": "Lensing Strength",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Amount of gravitational light distortion"
    },
    {
      "id": "diffusion",
      "name": "Material Diffusion",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "How much material spreads out"
    },
    {
      "id": "mouseMass",
      "name": "Mouse Gravity Power",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Temporary mass added when mouse is held"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Accretion Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Lensing Strength",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Material Diffusion",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Mouse Gravity Power",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Gravito-Phononic Accretion v3 — Optimized
//  Category: generative
//  Features: SPH-density, orbital-velocity, shock-detection, blackbody,
//            audio-driven, mouse-rogue-body, ripple-perturbation
//  Upgrades: 7-tap-hex-density-kernel, fast-exp, branchless-mouse,
//            reduced-gradient-samples, named-consts, pm-alpha
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ── 7-tap hex bokeh kernel (replaces 16-tap 4x4 SPH loop) ────────
const HEX_TAPS = array<vec2<f32>, 7>(
  vec2<f32>( 0.0,  0.0),
  vec2<f32>( 1.0,  0.0), vec2<f32>( 0.5,  0.866),
  vec2<f32>(-0.5,  0.866), vec2<f32>(-1.0,  0.0),
  vec2<f32>(-0.5, -0.866), vec2<f32>( 0.5, -0.866),
);

// ── Physics & Render Constants ───────────────────────────────────
const G1_ORBIT = vec2<f32>(0.35, 0.42);
const G2_ORBIT = vec2<f32>(0.68, 0.58);
const SOFTEN_1 = 0.06;
const SOFTEN_2 = 0.06;
const SOFTEN_3 = 0.04;
const VEL_AMP1 = 0.025;
const VEL_AMP2 = 0.020;
const VEL_AMP3 = 0.040;
const FLOW_AMP = 8.0;
const RIPPLE_DECAY = 8.0;
const RIPPLE_FREQ  = 10.0;
const RIPPLE_AGE   = 3.0;
const STAND_FREQ_X = 20.0;
const STAND_FREQ_Y = 16.0;
const STAND_AMP    = 0.12;
const TONE_GAIN    = 0.8;

fn fast_exp(x: f32) -> f32 { return exp(clamp(x, -80.0, 0.0)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (2.51 * x + 0.03);
  let b = x * (2.43 * x + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn blackbody(t: f32) -> vec3<f32> {
  let kt = clamp(t, 0.0, 1.0);
  let g = mix(0.2, 1.0, smoothstep(0.15, 0.6, kt));
  let b = mix(0.0, 1.0, smoothstep(0.3, 0.9, kt));
  return vec3<f32>(kt, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  let uv = vec2<f32>(gid.xy) / res;
  let time = u.config.x * 0.4;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  // Orbital centers with precession
  let precess = mids * 0.8;
  let g1 = vec2<f32>(
    G1_ORBIT.x + sin(time * 0.3 + precess) * 0.12,
    G1_ORBIT.y + cos(time * 0.25) * 0.09
  );
  let g2 = vec2<f32>(
    G2_ORBIT.x + cos(time * 0.35 - precess) * 0.1,
    G2_ORBIT.y + sin(time * 0.3 + precess) * 0.08
  );

  // Masses (audio + params)
  let mass1 = 0.9 + bass * 1.4 + p1 * 0.8;
  let mass2 = 0.8 + mids * 1.0 + p1 * 0.6;
  let mass3 = (0.7 + treble * 0.6) * mouseDown * (1.0 + p4 * 2.0);

  let d1 = length(uv - g1) + SOFTEN_1;
  let d2 = length(uv - g2) + SOFTEN_2;
  let d3 = length(uv - mouse) + SOFTEN_3;

  // Orbital velocity field (branchless — mouse mass zeros out when released)
  let v1 = vec2<f32>(-(uv.y - g1.y), uv.x - g1.x) * (mass1 / (d1 * d1)) * VEL_AMP1;
  let v2 = vec2<f32>(-(uv.y - g2.y), uv.x - g2.x) * (mass2 / (d2 * d2)) * VEL_AMP2;
  let v3 = vec2<f32>(-(uv.y - mouse.y), uv.x - mouse.x) * (mass3 / (d3 * d3)) * VEL_AMP3;
  let vel = v1 + v2 + v3;

  // ── Density: 7-tap hex kernel replaces 16-sample 4x4 SPH loop ──
  let h_uv = (0.045 + p3 * 0.04) * 1.5;
  let center = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;
  var density = center;
  var gradX = 0.0;
  var gradY = 0.0;
  for (var i = 1; i < 7; i = i + 1) {
    let off = HEX_TAPS[i] * h_uv;
    let sp = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));
    let samp = textureSampleLevel(dataTextureC, u_sampler, sp, 0.0).r;
    density += samp * 0.5;
    gradX   += samp * off.x;
    gradY   += samp * off.y;
  }
  density *= 0.25;
  let gradD = length(vec2<f32>(gradX, gradY)) * res.x * 0.5;

  // Flow advection (single sample)
  let flowUV = clamp(uv - vel * FLOW_AMP * (0.6 + p1), vec2<f32>(0.0), vec2<f32>(1.0));
  let flowed = textureSampleLevel(dataTextureC, u_sampler, flowUV, 0.0).r;

  // Standing acoustic waves
  let standing = sin(uv.x * STAND_FREQ_X + time * 3.0)
               * cos(uv.y * STAND_FREQ_Y - time * 2.5)
               * treble * STAND_AMP;

  // Ripple perturbations (fast_exp, same visual decay)
  var ripplePert = 0.0;
  let rCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rCount; i = i + 1u) {
    let rp = u.ripples[i];
    let rd = length(uv - rp.xy);
    let rt = time - rp.z;
    ripplePert += fast_exp(-rd * RIPPLE_DECAY)
                * sin(rt * RIPPLE_FREQ)
                * 0.03
                * smoothstep(RIPPLE_AGE, 0.0, rt);
  }

  density = mix(flowed * 0.95 + density * 0.05, density, 0.3) + standing + ripplePert;

  // Shock detection from hex-kernel gradient + velocity magnitude
  let shock = smoothstep(0.3, 1.2, gradD + length(vel) * 3.0);

  // Temperature field
  var temp = shock * 0.7
           + (mass1 / (d1 * d1 * 20.0 + 1.0)) * 0.4
           + (mass2 / (d2 * d2 * 20.0 + 1.0)) * 0.3;
  temp = clamp(temp, 0.0, 1.0);

  // State writeback for slot chaining
  textureStore(dataTextureA, gid.xy, vec4<f32>(density, temp, shock, 0.0));

  // Blackbody render
  let bb = blackbody(temp) * (1.0 + shock * 2.0);
  let scatter = smoothstep(0.02, 0.25, density) * temp * 0.6;
  let col = bb * (0.5 + density * 1.2) + vec3<f32>(0.3, 0.5, 1.0) * scatter;
  let bloom = shock * vec3<f32>(1.0, 0.9, 0.7) * 1.5;
  let tone = acesToneMap((col + bloom) * (TONE_GAIN + p2));

  let bgEmpty = smoothstep(0.15, 0.0, density);
  let alpha = clamp(density * 1.1 * temp * (1.0 - bgEmpty * 0.8) + shock * 0.5, 0.0, 1.0);

  // Premultiplied alpha for compositing
  textureStore(writeTexture, gid.xy, vec4<f32>(tone * alpha, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(density * temp * 0.7, 0.0, 0.0, 0.0));
}
```
