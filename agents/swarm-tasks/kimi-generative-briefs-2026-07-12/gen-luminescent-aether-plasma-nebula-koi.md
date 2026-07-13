# Swarm Brief: gen-luminescent-aether-plasma-nebula-koi

**Role:** Visualist
**Name:** Luminescent Aether-Plasma Nebula-Koi
**Category:** generative
**Description:** A hyper-organic, glowing biomechanical space-koi woven from flowing aether-plasma and shattered chromatic crystal, swimming gracefully through a volumetric quantum nebula while reacting dynamically to ambient acoustic frequencies.
**Current lines:** 199
**Target lines:** 249–289 (expand by +50 to +90)

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
  "id": "gen-luminescent-aether-plasma-nebula-koi",
  "name": "Luminescent Aether-Plasma Nebula-Koi",
  "category": "generative",
  "description": "A hyper-organic, glowing biomechanical space-koi woven from flowing aether-plasma and shattered chromatic crystal, swimming gracefully through a volumetric quantum nebula while reacting dynamically to ambient acoustic frequencies.",
  "url": "shaders/gen-luminescent-aether-plasma-nebula-koi.wgsl",
  "tags": [
    "organic",
    "quantum",
    "cosmic",
    "particle systems",
    "audio-reactive"
  ],
  "parameters": [
    {
      "name": "zoom_params.x",
      "label": "plasma_intensity",
      "type": "float",
      "default": 1.0,
      "min": 0.0,
      "max": 2.0,
      "step": 0.01
    },
    {
      "name": "zoom_params.y",
      "label": "koi_speed",
      "type": "float",
      "default": 1.0,
      "min": 0.1,
      "max": 5.0,
      "step": 0.1
    },
    {
      "name": "zoom_params.z",
      "label": "nebula_density",
      "type": "float",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "name": "zoom_params.w",
      "label": "tail_length",
      "type": "float",
      "default": 1.5,
      "min": 0.5,
      "max": 3.0,
      "step": 0.1
    }
  ]
}
```

## Current WGSL Code

```wgsl
// ----------------------------------------------------------------
// Luminescent Aether-Plasma Nebula-Koi
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: vec4<f32>,
};

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

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + vec3<f32>(33.33));
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn voronoi(x: vec3<f32>) -> vec2<f32> {
    let n = floor(x);
    let f = fract(x);
    var m = vec3<f32>(8.0);
    for(var k = -1; k <= 1; k++) {
        for(var j = -1; j <= 1; j++) {
            for(var i = -1; i <= 1; i++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash33(n + g);
                let r = g - f + o;
                let d = dot(r, r);
                if (d < m.x) {
                    m = vec3<f32>(d, m.x, m.y);
                } else if (d < m.y) {
                    m = vec3<f32>(m.x, d, m.y);
                }
            }
        }
    }
    return vec2<f32>(sqrt(m.x), sqrt(m.y));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn mapKoi(p_in: vec3<f32>, time: f32, koi_speed: f32, tail_length: f32) -> f32 {
    var p = p_in;

    // Sinuous swimming motion
    let wave = sin(p.z * 2.0 - time * koi_speed * 3.0) * 0.5;
    p.x += wave;

    // Body (Capsule/spindle-like)
    let body_len = 2.0;
    let p_body = p - vec3<f32>(0.0, 0.0, 0.0);

    var clamped_z = p_body.z;
    if (clamped_z < -body_len) {
        clamped_z = -body_len;
    } else if (clamped_z > body_len) {
        clamped_z = body_len;
    }
    let dz = p_body.z - clamped_z;

    var body_radius = 0.4 * (1.0 - abs(p_body.z) / (body_len + 0.1));
    body_radius = max(0.01, body_radius);
    let d_body = length(vec2<f32>(p_body.x, p_body.y)) - body_radius + dz*dz;

    // Fins
    let fin_p = vec3<f32>(abs(p.x) - body_radius - 0.1, p.y, p.z);
    var d_fins = length(vec2<f32>(fin_p.x, fin_p.y)) - 0.02;
    d_fins = max(d_fins, abs(p.z) - 0.5);

    // Tail
    let tail_p = p - vec3<f32>(0.0, 0.0, -body_len - tail_length * 0.5);
    let tail_wave = sin(tail_p.z * 5.0 - time * koi_speed * 5.0) * 0.5;
    let d_tail = length(vec2<f32>(tail_p.x + tail_wave, tail_p.y)) - (0.3 - abs(tail_p.z)*0.2) + abs(tail_p.z)-tail_length*0.5;

    var d = smin(d_body, d_tail, 0.3);
    d = smin(d, d_fins, 0.2);

    return d;
}

fn fbm(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    var f = 0.0;
    var amp = 0.5;
    for(var i = 0; i < 4; i++) {
        f += amp * (voronoi(p).x * 2.0 - 1.0);
        p *= 2.0;
        amp *= 0.5;
    }
    return f;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }

    let uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * vec2<f32>(f32(dims.x), f32(dims.y))) / f32(dims.y);

    let time = u.config.x;
    let audio = u.config.y;
    let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(f32(dims.x)/f32(dims.y), 1.0);

    let plasma_intensity = u.zoom_params.x;
    let koi_speed = u.zoom_params.y;
    let nebula_density = u.zoom_params.z;
    let tail_length = u.zoom_params.w;

    let ro = vec3<f32>(0.0, 0.0, 5.0);
    var rd = normalize(vec3<f32>(uv, -1.0));

    // Mouse interaction - bend rays (gravitational ripple)
    let mouse_dist = length(uv - mouse);
    if (mouse_dist < 0.5) {
        let pull = (0.5 - mouse_dist) * 0.5;
        rd = normalize(rd + vec3<f32>(normalize(uv - mouse) * pull, 0.0));
    }

    var col = vec3<f32>(0.0);
    var t = 0.0;

    // Raymarch Koi
    var hit = false;
    var p = vec3<f32>(0.0);
    for(var i = 0; i < 64; i++) {
        p = ro + rd * t;
        let d = mapKoi(p, time, koi_speed, tail_length);
        if (d < 0.01) {
            hit = true;
            break;
        }
        t += d * 0.5;
        if (t > 10.0) { break; }
    }

    if (hit) {
        // Shading for koi
        let v = voronoi(p * 5.0 + vec3<f32>(0.0, 0.0, time));
        let scale_pattern = v.y - v.x;

        let base_col = vec3<f32>(0.1, 0.4, 0.8);
        let glow_col = vec3<f32>(0.9, 0.2, 0.8) * plasma_intensity * (1.0 + audio * 2.0);

        col = mix(base_col, glow_col, scale_pattern);

        // Edge glow
        let fresnel = pow(1.0 - max(dot(-rd, normalize(p)), 0.0), 3.0);
        col += glow_col * fresnel;
    }

    // Nebula Background (Volumetric)
    var nebula_col = vec3<f32>(0.0);
    var nt = 0.0;
    for(var i = 0; i < 32; i++) {
        let np = ro + rd * nt;
        let den = fbm(np * 0.5 + vec3<f32>(time * 0.1, 0.0, time * 0.2));
        if (den > 0.0) {
            let nc = mix(vec3<f32>(0.1, 0.0, 0.2), vec3<f32>(0.0, 0.4, 0.6), den);
            nebula_col += nc * den * 0.1 * nebula_density;
        }
        nt += 0.3;
    }

    col += nebula_col;

    // Apply bloom from audio
    col += vec3<f32>(0.2, 0.5, 1.0) * audio * plasma_intensity * (1.0 / (1.0 + t*t*0.1));

    // Tonemapping
    col = col / (vec3<f32>(1.0) + col);
    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}

```
