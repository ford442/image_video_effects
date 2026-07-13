# Swarm Brief: gen-ethereal-chrono-plasma-void-manta

**Role:** Visualist
**Name:** Ethereal Chrono-Plasma Void-Manta
**Category:** generative
**Description:** A majestic, hyper-organic cybernetic space-manta ray gliding through a dark-matter ocean, its translucent biomimetic wings rippling with shifting auroral temporal energy as it consumes deep acoustic bass frequencies.
**Current lines:** 174
**Target lines:** 224–264 (expand by +50 to +90)

## Role Instructions

You are the Visualist. Focus on color science, lighting, and emotional impact:
- Add HDR values > 1.0, ACES tone mapping, hue-preserving clamp, and IGN dither.
- Introduce 2+ light sources / temperature shifts, volumetric fog/god rays, Fresnel rim, or iridescence.
- Use a cohesive color palette (analogous/complementary) tied to the theme.
- Ensure meaningful alpha (not just 1.0) based on emission/density/occlusion.


## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.

## JSON Parameters / Controls

```json
{
  "id": "gen-ethereal-chrono-plasma-void-manta",
  "url": "shaders/gen-ethereal-chrono-plasma-void-manta.wgsl",
  "name": "Ethereal Chrono-Plasma Void-Manta",
  "category": "generative",
  "description": "A majestic, hyper-organic cybernetic space-manta ray gliding through a dark-matter ocean, its translucent biomimetic wings rippling with shifting auroral temporal energy as it consumes deep acoustic bass frequencies.",
  "parameters": [
    {
      "name": "Manta Speed",
      "uniform": "zoom_params.x",
      "default": 1.0,
      "min": 0.1,
      "max": 5.0,
      "step": 0.1
    },
    {
      "name": "Bio-Luminescence Intensity",
      "uniform": "zoom_params.y",
      "default": 1.0,
      "min": 0.0,
      "max": 3.0,
      "step": 0.1
    },
    {
      "name": "Wing Ripple Frequency",
      "uniform": "zoom_params.z",
      "default": 2.0,
      "min": 0.5,
      "max": 5.0,
      "step": 0.1
    },
    {
      "name": "Dark Matter Density",
      "uniform": "zoom_params.w",
      "default": 1.0,
      "min": 0.0,
      "max": 2.0,
      "step": 0.05
    }
  ]
}
```

## Current WGSL Code

```wgsl
struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// Ethereal Chrono-Plasma Void-Manta
// Category: generative
// ----------------------------------------------------------------

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



// Custom Parameters Mapping:
// custom_params[0].x = Manta Speed
// custom_params[0].y = Bio-Luminescence Intensity
// custom_params[0].z = Wing Ripple Frequency
// custom_params[0].w = Dark Matter Density

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// 3D Noise function (placeholder for actual implementation)
fn hash(p: vec3<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x * 0.1031, p.y * 0.1030, p.z * 0.0973));
    p3 = p3 + vec3<f32>(dot(p3, p3.yxz + vec3<f32>(33.33)));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_new = f * f * (vec3<f32>(3.0) - 2.0 * f);
    let f_final = f_new;
    return mix(mix(mix(hash(p + vec3<f32>(0.0, 0.0, 0.0)),
                        hash(p + vec3<f32>(1.0, 0.0, 0.0)), f_final.x),
                   mix(hash(p + vec3<f32>(0.0, 1.0, 0.0)),
                        hash(p + vec3<f32>(1.0, 1.0, 0.0)), f_final.x), f_final.y),
               mix(mix(hash(p + vec3<f32>(0.0, 0.0, 1.0)),
                        hash(p + vec3<f32>(1.0, 0.0, 1.0)), f_final.x),
                   mix(hash(p + vec3<f32>(0.0, 1.0, 1.0)),
                        hash(p + vec3<f32>(1.0, 1.0, 1.0)), f_final.x), f_final.y), f_final.z);
}

// Scene SDF
fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    let time = u.config.x * u.zoom_params.x;
    let audio = u.config.y;

    // Manta motion
    let flap = sin(pos.x * u.zoom_params.z - time * 3.0) * (pos.x * pos.x) * 0.2;
    pos.y += flap;

    // Core body (flattened sphere)
    let body_d = (length(pos / vec3<f32>(1.0, 0.2, 2.0)) - 1.0) * 0.2;

    // Wings (displaced plane)
    let wing_d = pos.y + noise(pos * 2.0 - vec3<f32>(0.0, 0.0, time)) * 0.5 * audio;

    // Blend body and wings
    let manta_d = smin(body_d * 0.5, abs(wing_d) - 0.1, 0.5);

    // Material ID: 1.0 for manta, 0.0 for background
    return vec2<f32>(manta_d, 1.0);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize( e.xyy*map( p + e.xyy ).x +
					  e.yyx*map( p + e.yyx ).x +
					  e.yxy*map( p + e.yxy ).x +
					  e.xxx*map( p + e.xxx ).x );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }

    let resolution = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = (vec2<f32>(id.xy) - 0.5 * resolution) / min(resolution.x, resolution.y);

    let time = u.config.x;
    let audio = u.config.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 2.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.5));

    // Mouse rotation
    let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 6.28;
    let new_ro_yz = rot(-mouse.y) * ro.yz;
    ro.y = new_ro_yz.x;
    ro.z = new_ro_yz.y;
    let new_rd_yz = rot(-mouse.y) * rd.yz;
    rd.y = new_rd_yz.x;
    rd.z = new_rd_yz.y;
    let new_ro_xz = rot(-mouse.x) * ro.xz;
    ro.x = new_ro_xz.x;
    ro.z = new_ro_xz.y;
    let new_rd_xz = rot(-mouse.x) * rd.xz;
    rd.x = new_rd_xz.x;
    rd.z = new_rd_xz.y;

    // Raymarching loop
    var t = 0.0;
    var col = vec3<f32>(0.0);
    var hit = false;

    // Background Dark Matter Ocean accumulation
    var bg_density = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);

        // Accumulate background density
        bg_density += noise(p * 0.5 + vec3<f32>(time * 0.1)) * u.zoom_params.w * 0.02;

        if (d.x < 0.001) {
            hit = true;
            // Shading
            let n = calcNormal(p);
            let light = normalize(vec3<f32>(1.0, 2.0, -1.0));
            let diff = max(dot(n, light), 0.0);

            // Subsurface / Bio-luminescence fake
            let thickness = map(p + n * 0.1).x; // sample slightly inside
            let sss = smoothstep(0.0, 0.1, abs(thickness)) * u.zoom_params.y;

            let base_col = vec3<f32>(0.1, 0.2, 0.5);
            let glow_col = vec3<f32>(0.9, 0.1, 0.7);

            col = base_col * diff + glow_col * sss * (1.0 + audio * 2.0);
            break;
        }
        if (t > 20.0) { break; }
        t += d.x;
    }

    if (!hit) {
        // Deep space / dark matter color
        col = vec3<f32>(0.02, 0.01, 0.05) + vec3<f32>(0.2, 0.1, 0.4) * bg_density;
    }

    // Output
    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}

```
