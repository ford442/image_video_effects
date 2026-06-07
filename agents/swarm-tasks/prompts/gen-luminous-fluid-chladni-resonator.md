# Shader Upgrade Task: `gen-luminous-fluid-chladni-resonator`

## Metadata
- **Shader ID**: gen-luminous-fluid-chladni-resonator
- **Agent Role**: Visualist
- **Current Size**: 3336 bytes
- **Target Line Count**: ~133 lines
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
//  Luminous-Fluid Chladni-Resonator
//  Category: generative
//  Features: audio-reactive, multi-mode Chladni, curl-noise fluid, Voronoi ridges
//  Complexity: Medium
//  Phase B / Algorithmist
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ModeN, y=ModeM, z=FluidStrength, w=Glow
  ripples: array<vec4<f32>, 50>,
};

const PI:    f32 = 3.14159265358979323846;
const TAU:   f32 = 6.28318530717958647692;
const PHI:   f32 = 1.61803398874989484820;
const SQRT3: f32 = 1.73205080756887729352;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(3.0) - vec2<f32>(2.0) * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// FBM with rotation matrix (golden-angle rotation reduces axis bias)
fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var q = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(q);
        q = rot * q * 2.0 + vec2<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

// Curl noise (divergence-free) — for proper fluid velocity field
fn curl2D(p: vec2<f32>) -> vec2<f32> {
    let eps = 0.01;
    let nx = fbm(p + vec2<f32>(0.0, eps)) - fbm(p - vec2<f32>(0.0, eps));
    let ny = fbm(p + vec2<f32>(eps, 0.0)) - fbm(p - vec2<f32>(eps, 0.0));
    return vec2<f32>(nx, -ny) / (2.0 * eps);
}

// Voronoi F2-F1 (cellular ridges, like nodal lines on a vibrating plate)
fn voronoiRidge(p: vec2<f32>) -> f32 {
    let ip = floor(p);
    let fp = fract(p);
    var F1 = 1e9;
    var F2 = 1e9;
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let n = vec2<f32>(f32(i), f32(j));
            let cellPt = n + vec2<f32>(hash21(ip + n), hash21(ip + n + 17.0));
            let d = length(cellPt - fp);
            if (d < F1) { F2 = F1; F1 = d; }
            else if (d < F2) { F2 = d; }
        }
    }
    return F2 - F1;
}

// Multi-mode Chladni — sum of (n,m) and dual symmetric pair
fn chladni_multi(uv: vec2<f32>, n: f32, m: f32, t: f32) -> f32 {
    let a1 = sin(n * PI * uv.x) * sin(m * PI * uv.y);
    let a2 = sin(m * PI * uv.x) * sin(n * PI * uv.y);
    let b1 = sin((n + 1.0) * PI * uv.x) * sin((m + 1.0) * PI * uv.y);
    let b2 = sin((m + 1.0) * PI * uv.x) * sin((n + 1.0) * PI * uv.y);
    let pri = cos(t) * a1 + sin(t) * a2;
    let sec = cos(t * PHI) * b1 + sin(t * PHI) * b2;
    return pri + 0.4 * sec;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<i32>(i32(id.x), i32(id.y));
    if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(coord) / res;
    let t = u.config.x * 0.5;
    let bass = plasmaBuffer[0].x;

    let param_n     = u.zoom_params.x;
    let param_m     = u.zoom_params.y;
    let param_fluid = u.zoom_params.z;
    let param_glow  = u.zoom_params.w;

    // Curl-noise displacement (divergence-free — proper fluid)
    let velocity = curl2D(uv * 5.0 + vec2<f32>(t * 0.3));
    let uv_dist  = uv + velocity * param_fluid * 0.05 * (1.0 + bass * 0.5);

    // Bass-modulated mode numbers (pseudo-resonance sweep)
    let n = param_n + bass * 2.0 * sin(t);
    let m = param_m + bass * 2.0 * cos(t * PHI);

    // Multi-mode Chladni interference field
    let c_val = chladni_multi(uv_dist * 2.0 - vec2<f32>(1.0), n, m, t * 2.0);

    // Voronoi ridges weave nodal-line cellular structure into the field
    let ridge = 1.0 - smoothstep(0.0, 0.18, voronoiRidge(uv * 8.0 + velocity * 0.2));

    // Mouse acts as standing-wave damper
    let mouse_uv = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let d_mouse = distance(uv, mouse_uv);
    let damp = smoothstep(0.0, 0.2, d_mouse);

    // Beer-Lambert absorption: deeper field travel = more glow attenuation
    let depthAttn = exp(-d_mouse * 1.5);
    let final_val = abs(c_val) * damp + ridge * 0.35 * depthAttn;

    // Verlet-style temporal coherence — accumulate prior frame field for ringing
    let prior = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
    let settled = mix(prior, final_val, 0.35);

    // Nodal lines = where settled ≈ 0 → bright; antinodes = darker
    let intensity = smoothstep(0.18, 0.0, settled) * param_glow * (1.0 + bass);

    // Plasma palette mapped by intensity, modulated by ridge phase
    let p_idx = u32(clamp(intensity * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[p_idx % 256u].rgb;
    let col = palette * (intensity + ridge * 0.15);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));

    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(intensity * 0.6 + luma * 0.4 + ridge * 0.15, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    // Persist field for next-frame coherence
    textureStore(dataTextureA, coord, vec4<f32>(settled, ridge, intensity, 1.0));
}

```

## Current JSON Definition
```json
{
  "id": "gen-luminous-fluid-chladni-resonator",
  "name": "Luminous-Fluid Chladni-Resonator",
  "category": "generative",
  "url": "/shaders/gen-luminous-fluid-chladni-resonator.wgsl",
  "tags": ["chladni", "cymatics", "fluid", "resonance", "audio-reactive", "bioluminescent"],
  "features": ["audio-reactive"],
  "description": "A mesmerizing, bioluminescent liquid surface that physically organizes itself into hyper-complex, evolving Chladni resonant figures driven by low-frequency audio interference patterns.",
  "coordinate": 880,
  "params": [
    {"id": "modeN", "name": "Mode N", "default": 3.0, "min": 1.0, "max": 10.0, "step": 0.1},
    {"id": "modeM", "name": "Mode M", "default": 5.0, "min": 1.0, "max": 10.0, "step": 0.1},
    {"id": "fluidity", "name": "Fluidity", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.05},
    {"id": "glowIntensity", "name": "Glow Intensity", "default": 1.5, "min": 0.1, "max": 5.0, "step": 0.1}
  ]
}

```

---

## Agent Specialization
# Agent Role: The Visualist

## Identity
You are **The Visualist**, a shader architect focused on color science, lighting, and emotional impact. You make shaders visually stunning.

## Upgrade Toolkit

### Color Science
- SRGB → Linear workflow with proper gamma (`pow(c, 2.2)` in, `pow(c, 1/2.2)` out)
- Clamped colors → HDR with values >1.0 before tone mapping
- Static palettes → Dynamic temperature shifting
- Solid fills → Subsurface scattering glow
- Flat shading → Fresnel rim lighting

#### OkLab — Perceptually Uniform Color Space (use for smooth gradients / mixing)
```wgsl
fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
    let m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
    let s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
    let l_ = pow(l, 1.0/3.0); let m_ = pow(m, 1.0/3.0); let s_ = pow(s, 1.0/3.0);
    return vec3<f32>(0.2104542553*l_+0.7936177850*m_-0.0040720468*s_,
                     1.9779984951*l_-2.4285922050*m_+0.4505937099*s_,
                     0.0259040371*l_+0.7827717662*m_-0.8086757660*s_);
}
fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
    let l_ = c.x+0.3963377774*c.y+0.2158037573*c.z;
    let m_ = c.x-0.1055613458*c.y-0.0638541728*c.z;
    let s_ = c.x-0.0894841775*c.y-1.2914855480*c.z;
    let l = l_*l_*l_; let m = m_*m_*m_; let s = s_*s_*s_;
    return vec3<f32>(4.0767416621*l-3.3077115913*m+0.2309699292*s,
                    -1.2684380046*l+2.6097574011*m-0.3413193965*s,
                    -0.0041960863*l-0.7034186147*m+1.7076147010*s);
}
// Mix colors in OkLab (avoids the grey mud in mid-tones)
fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}
```

#### Blackbody / Color Temperature
```wgsl
// Temperature in Kelvin → approximate RGB (1000K–40000K)
fn blackbodyRGB(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) / 100.0;
    var r = 0.0; var g = 0.0; var b = 0.0;
    if (t <= 66.0) { r = 1.0; }
    else { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
    if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
    else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
    if (t >= 66.0) { b = 1.0; }
    else if (t <= 19.0) { b = 0.0; }
    else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
    return vec3<f32>(r, g, b);
}
```

#### Cosine Palette (Inigo Quilez) — fast procedural gradients
```wgsl
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}
// Example fire: palette(t, (0.5,0.5,0.5),(0.5,0.5,0.5),(1,1,0.5),(0,0.1,0.2))
// Example ice:  palette(t, (0.5,0.5,0.5),(0.5,0.5,0.5),(1,1,1),(0,0.33,0.67))
```

### Lighting Techniques
- Single light → 3-point studio lighting (key + fill + rim, different color temps)
- Diffuse only → Specular via GGX distribution + Fresnel-Schlick
- Hard shadows → Soft penumbra: `smoothstep(penumbra, 0.0, shadowDist)`
- Local lighting → Volumetric god rays (ray march toward light source)
- Flat surface → Iridescent thin-film: `sin(d * freq + hue_offset) * fresnel`

### Atmosphere
- Clear → Volumetric fog: `exp(-density * dist)` (Beer-Lambert)
- Sharp → Bokeh depth of field (hexagonal aperture SDF)
- Static → Animated caustics: FBM of sinusoids, `sin(fbm(p)*8 + t)`
- Clean → Rayleigh scattering: blue-bias sky, `pow(lambda, -4.0)` wavelength dependence
- Mie scattering for haze: `(1-g²) / pow(1+g²-2g*cosθ, 1.5)`, g≈0.76 for aerosols

### Color Grading
- Raw output → ACES tone mapped (apply last, after all HDR work)
- Static → Audio-reactive temperature (`blackbodyRGB(3000 + bass * 4000)`)
- Monochrome → Split-tone: shadows in complementary hue, highlights warm
- Natural → Iridescent thin-film: wavelength-dependent phase shift
- Flat mix → OkLab interpolation (prevents muddy mid-tone blending)

### Tonemap & Dither Stack (kimi-cli reference snippets)

Always process in this order: accumulate HDR → hue-preserve clamp → ACES tonemap → dither → premultiplied write.

#### 1. Hue-preserving HDR clamp (prevents desaturation on bright highlights)
```wgsl
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}
```
Apply after additive accumulation, before ACES. Beats `min(c, 1.0)` which desaturates to white.

#### 2. ACES filmic tonemap (drop-in, no LUT required)
```wgsl
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
```
Pair with sRGB gamma `pow(c, vec3<f32>(1.0/2.2))` on write if the display is sRGB.

#### 3. Interleaved-gradient (IGN) blue-noise dither (kills 8-bit banding)
```wgsl
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
// before textureStore:
let dither = (ign(vec2<f32>(gid.xy)) - 0.5) / 255.0;
let outRGB = aces(hdr) + vec3<f32>(dither);
```
Cheaper than a blue-noise texture lookup and visually identical at 8-bit precision.

#### Premultiplied-alpha writeback — tactic #12 (correct compositing in the slot chain)
```wgsl
let a = clamp(alpha, 0.0, 1.0);
textureStore(writeTexture, gid.xy, vec4<f32>(rgb * a, a));
```
The renderer expects premultiplied output downstream of slot 1. Straight alpha causes dark fringes after the next slot's blur/blend.

## RGBA Channel Strategy

**Alpha = bloom weight** is the most useful convention for generative shaders:
```wgsl
let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
let bloomWeight = pow(max(0.0, luma - 0.6), 2.0) * 3.0;  // only bright areas
textureStore(writeTexture, coord, vec4<f32>(color, bloomWeight));
```

Other useful alpha encodings:
- `alpha = depth` — for depth-aware compositing in the next slot
- `alpha = effectStrength` — transparent where effect is absent (compositing-friendly)
- `alpha = fresnel` — glass/water reflectance mask

**Do NOT output `vec4(color, 1.0)` unless the shader is a pure background layer.**

## Quality Checklist
- [ ] HDR values exceed 1.0 in highlights before tone mapping
- [ ] At least 2 light sources with different color temperatures
- [ ] `hue_preserve_clamp` applied before ACES to avoid highlight desaturation
- [ ] ACES tone mapping applied as the final step
- [ ] IGN dither added before `textureStore` to kill 8-bit banding
- [ ] Atmospheric depth (fog/haze/dust via Beer-Lambert or Rayleigh)
- [ ] Color gradients use OkLab mixing to avoid muddy transitions
- [ ] Alpha channel encodes bloom weight or compositing info
- [ ] Premultiplied-alpha writeback (`vec4(rgb * a, a)`) when alpha < 1

## Output Rules
- Keep the original "soul" of the shader while making it visually stunning.
- Use `@workgroup_size(16, 16, 1)` unless the shader explicitly requires a different size.
- Do NOT modify the 13-binding header or the Uniforms struct.
- **Alpha must carry semantic meaning** — bloom weight, depth, or Fresnel reflectance.

## Performance Constraint
This shader must remain efficient for 3-slot chained rendering. Avoid excessive nested loops, minimize texture samples, and prefer branchless math. If adding features, keep total line count within the target specified in the task metadata.


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 133 lines (±20%).
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
