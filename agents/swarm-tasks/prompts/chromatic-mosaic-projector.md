# Shader Upgrade Task: `chromatic-mosaic-projector`

## Metadata
- **Shader ID**: chromatic-mosaic-projector
- **Agent Role**: Visualist
- **Current Size**: 3242 bytes
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
  var pp = p * vec2<f32>(0.1031, 0.1030);
  let a = dot(pp, vec2<f32>(127.1, 311.7));
  let b = dot(pp + 1.0, vec2<f32>(269.5, 183.3));
  let c = sin(vec2<f32>(a, b));
  return fract(c * 43758.5453 + pp);
}

fn hash12(p: vec2<f32>) -> f32 {
  let a = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(a) * 43758.5453);
}

fn voronoi(uv: vec2<f32>, cellSize: f32, distort: f32, time: f32) -> vec3<f32> {
  let scaled = uv * cellSize;
  let cellId = floor(scaled);
  let fracPos = fract(scaled);

  var minDist = 1.0;
  var nearCell = cellId;

  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = cellId + vec2<f32>(f32(x), f32(y));
      let h = hash22(neighbor);
      let anim = vec2<f32>(
        sin(time * 0.8 + h.x * 6.28) * distort,
        cos(time * 0.6 + h.y * 6.28) * distort
      );
      let point = h + anim + vec2<f32>(f32(x), f32(y)) - fracPos;
      let d = length(point);
      if (d < minDist) {
        minDist = d;
        nearCell = neighbor;
      }
    }
  }
  return vec3<f32>(minDist, nearCell.x, nearCell.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters (mids → chromatic split, treble → cell boundary distortion)
  let cellSizeBase = mix(8.0, 80.0, u.zoom_params.x);
  let cellSize = cellSizeBase * (1.0 + bass * 0.2);
  let chromaticStrength = u.zoom_params.y * 0.06 * (1.0 + mids * 1.5);
  let voronoiDistort = u.zoom_params.z * 0.4 * (1.0 + treble * 0.8);
  let projectionAngle = (u.zoom_params.w - 0.5) * 1.0;

  let voro = voronoi(uv, cellSize, voronoiDistort, time);
  let cellHash = hash12(vec2<f32>(voro.y, voro.z));
  let cellCenter = (vec2<f32>(voro.y, voro.z) + 0.5) / cellSize;

  // Mouse gravity well
  let mouse = u.zoom_config.yz;
  let toMouse = (mouse - uv) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(toMouse);
  let gravity = 0.2;
  let warp = select(vec2<f32>(0.0), normalize(toMouse) * gravity / (1.0 + mouseDist * 3.0), mouseDist > 0.0001);
  let warpedUV = uv + warp * 0.02;

  // Direction from cell center with projection angle bias
  let dirVec = (cellCenter - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dirVec);
  var dir = select(vec2<f32>(1.0, 0.0), normalize(dirVec), dist > 0.0001);
  let angleRot = projectionAngle + cellHash * 0.5;
  let ca = cos(angleRot);
  let sa = sin(angleRot);
  dir = vec2<f32>(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca);

  // Per-cell chromatic shift based on cell hash
  let cellChroma = chromaticStrength * (0.5 + cellHash);
  let baseOffset = dir * dist * 0.08;
  let rOff = baseOffset + dir * cellChroma * (1.0 + bass * 0.5);
  let gOff = baseOffset + dir * cellChroma * 0.3;
  let bOff = baseOffset - dir * cellChroma * 0.7;

  let r = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + rOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + gOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + bOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(r, g, b);

  // Cell boundary transition smoothness
  let edgeFade = smoothstep(0.0, 0.15, voro.x);
  color = color * (0.7 + 0.3 * edgeFade);

  // Light falloff
  let falloff = 1.0 / (1.0 + dist * 2.0);
  color = color * falloff;

  // Audio brightness boost
  color = color * (1.0 + bass * 0.2);

  // Source alpha preserved, smooth boundary transitions
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let alpha = mix(src.a * 0.7, src.a, edgeFade);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "chromatic-mosaic-projector",
  "name": "Chromatic Mosaic Projector",
  "url": "shaders/chromatic-mosaic-projector.wgsl",
  "description": "Animated Voronoi cell mosaic with per-cell chromatic aberration, mouse gravity wells, and audio-reactive cell pulsing.",
  "params": [
    {
      "id": "cellSize",
      "name": "Cell Size",
      "default": 0.4,
      "min": 0,
      "max": 1
    },
    {
      "id": "chromatic",
      "name": "Chromatic Strength",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "voronoi",
      "name": "Voronoi Distort",
      "default": 0.4,
      "min": 0,
      "max": 1
    },
    {
      "id": "angle",
      "name": "Projection Angle",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba",
    "voronoi",
    "chromatic-dispersion"
  ],
  "tags": [
    "filter",
    "image-processing",
    "mosaic",
    "chromatic",
    "voronoi",
    "audio-reactive",
    "interactive"
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
