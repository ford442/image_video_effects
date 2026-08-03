// ═══════════════════════════════════════════════════════════════════
//  Chaos Game IFS Fractal
//  Category: generative
//  Features: generative, audio-reactive, upgraded-rgba, temporal-ghosting, chromatic-attractors,
//            bass-scale-pulse, upgraded-rgba, aces-tone-map
//  Complexity: Medium
//  Created: 2026-05-23
//  Upgraded: 2026-06-06
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

const PI: f32 = 3.14159265359;

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

// Compact analytic SDF library used by the orbit sculpture.
fn sdSphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    return length(vec2<f32>(length(p.xz) - t.x, p.y)) - t.y;
}
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735027;
}
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a; let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
    return length(pa - ba * h) - r;
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Three-dimensional embodiment of the IFS attractor: cut crystal core,
// orbit ring, and three capsule axes. Returns distance + material id.
fn sceneDE(pIn: vec3<f32>, bass: f32, treble: f32, ringParam: f32) -> vec2<f32> {
    let p = rotY(u.config.x * 0.18 + bass * 0.35) * pIn;
    let cutCore = max(sdSphere(p, 0.55 + bass * 0.08), -sdBox(p, vec3<f32>(0.31)));
    let crystal = sdOctahedron(p, 0.72 + treble * 0.12);
    let core = smin(cutCore, crystal, 0.10);
    let ring = sdTorus(p, vec2<f32>(0.88 + ringParam * 0.22, 0.035 + treble * 0.025));
    var axes = sdCapsule(p, vec3<f32>(-0.82, 0.0, 0.0), vec3<f32>(0.82, 0.0, 0.0), 0.025);
    axes = min(axes, sdCapsule(p, vec3<f32>(0.0, -0.82, 0.0), vec3<f32>(0.0, 0.82, 0.0), 0.025));
    axes = min(axes, sdCapsule(p, vec3<f32>(0.0, 0.0, -0.82), vec3<f32>(0.0, 0.0, 0.82), 0.025));
    var out = vec2<f32>(core, 1.0);
    if (ring < out.x) { out = vec2<f32>(ring, 2.0); }
    if (axes < out.x) { out = vec2<f32>(axes, 3.0); }
    return out;
}

fn sceneNormal(p: vec3<f32>, bass: f32, treble: f32, ringParam: f32) -> vec3<f32> {
    let e = vec2<f32>(0.003, 0.0);
    return normalize(vec3<f32>(
        sceneDE(p + e.xyy, bass, treble, ringParam).x - sceneDE(p - e.xyy, bass, treble, ringParam).x,
        sceneDE(p + e.yxy, bass, treble, ringParam).x - sceneDE(p - e.yxy, bass, treble, ringParam).x,
        sceneDE(p + e.yyx, bass, treble, ringParam).x - sceneDE(p - e.yyx, bass, treble, ringParam).x));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hue2rgb(h: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(h + k) * 6.0 - 3.0);
    return clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ifsPoint(uv: vec2<f32>, iter: i32, time: f32, bass: f32) -> vec2<f32> {
    var p = uv * 2.0 - 1.0;
    let rot = time * 0.1 + bass * 0.5;
    let c = cos(rot);
    let s = sin(rot);
    
    for (var i: i32 = 0; i < iter; i = i + 1) {
        let fi = f32(i);
        let a1 = vec2<f32>(-0.5 * c - 0.0 * s, -0.5 * s + 0.0 * c);
        let a2 = vec2<f32>(0.5 * c - 0.0 * s, 0.5 * s + 0.0 * c);
        let a3 = vec2<f32>(0.0 * c - 0.866 * s, 0.0 * s + 0.866 * c);
        
        let h = hash12(p + vec2<f32>(fi * 0.1, time * 0.01));
        let scale = 0.5 + bass * 0.1;
        
        p = select(
            select(
                (p - a3) * scale,
                (p - a2) * scale,
                h > 0.33
            ),
            (p - a1) * scale,
            h < 0.33
        );
    }
    return p;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;
    let resolution = vec2<f32>(u.config.zw);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    
    let param1 = u.zoom_params.x;
    let param2 = u.zoom_params.y;
    let param3 = u.zoom_params.z;
    let param4 = u.zoom_params.w;
    
    let iterations = i32(mix(3.0, 12.0, clamp(param1 + bass * 0.3, 0.0, 1.0)));
    
    // Chromatic attractor separation: R/B use different attractor offsets
    let p_r = ifsPoint(uv + vec2<f32>(param4 * 0.01 * bass, 0.0), iterations, time, bass);
    let p_b = ifsPoint(uv - vec2<f32>(param4 * 0.01 * treble, 0.0), iterations, time, bass);
    let p_g = ifsPoint(uv, iterations, time, bass);
    
    let d_r = length(p_r);
    let d_g = length(p_g);
    let d_b = length(p_b);
    let angle = atan2(p_g.y, p_g.x) / (2.0 * 3.14159265);
    
    let glow_r = 1.0 / (1.0 + d_r * d_r * mix(4.0, 20.0, param2));
    let glow_g = 1.0 / (1.0 + d_g * d_g * mix(4.0, 20.0, param2));
    let glow_b = 1.0 / (1.0 + d_b * d_b * mix(4.0, 20.0, param2));
    let ringDistance = abs(fract(d_g * mix(3.0, 10.0, param3)) - 0.5);
    let rings = 1.0 - smoothstep(0.02, 0.12, ringDistance);
    
    let hue = fract(angle + time * 0.03 + mids * 0.15);
    let sat = mix(0.4, 1.0, param4 + treble * 0.3);
    let val_r = glow_r * (0.5 + rings * 0.5) * (1.0 + bass * 0.3);
    let val_g = glow_g * (0.5 + rings * 0.5) * (1.0 + bass * 0.3);
    let val_b = glow_b * (0.5 + rings * 0.5) * (1.0 + bass * 0.3);
    
    let rgb = hue2rgb(hue) * sat + vec3<f32>(1.0 - sat);
    var finalRGB = vec3<f32>(rgb.r * val_r, rgb.g * val_g, rgb.b * val_b);

    // Raymarched orbit sculpture layered over the 2D chaos-game field.
    let aspect = resolution.x / resolution.y;
    let screen = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let cam = rotY(time * 0.09 + mids * 0.25);
    let ro = cam * vec3<f32>(0.0, 0.0, 2.8);
    let rd = cam * normalize(vec3<f32>(screen, -1.6));
    var rayT = 0.0;
    var hit = false;
    var matId = 0.0;
    for (var i = 0; i < 44; i = i + 1) {
        let sample = sceneDE(ro + rd * rayT, bass, treble, param3);
        if (sample.x < 0.003) { hit = true; matId = sample.y; break; }
        rayT += max(sample.x * 0.82, 0.004);
        if (rayT > 6.0) { break; }
    }
    var heroDepth = 0.0;
    if (hit) {
        let pos = ro + rd * rayT;
        let n = sceneNormal(pos, bass, treble, param3);
        let light = normalize(vec3<f32>(0.7, 0.9, -0.5));
        let diff = max(dot(n, light), 0.0);
        let rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let matHue = fract(angle + matId * 0.19 + time * 0.04);
        let heroColor = hue2rgb(matHue) * mix(0.45, 1.0, param4);
        finalRGB += heroColor * (0.25 + diff * 0.8 + rim * (0.8 + treble));
        heroDepth = clamp(1.0 - rayT / 6.0, 0.0, 1.0);
    }
    
    // Temporal ghosting from previous IFS state
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
    let ghosted = mix(finalRGB, prev * 0.88, 0.1 + bass * 0.05);
    
    let depth = textureLoad(readDepthTexture, vec2<i32>(global_id.xy), 0).r;
    let alpha = clamp((val_r + val_g + val_b) * 0.3 + glow_g * 0.3 + 0.1 + bass * 0.05 + select(0.0, 0.5, hit), 0.0, 1.0);
    let finalColor = vec4<f32>(acesToneMap(ghosted * 1.1), alpha);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(max(depth, heroDepth), 0.0, 0.0, 0.0));
}
