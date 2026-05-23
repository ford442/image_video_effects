// ═══════════════════════════════════════════════════════════════════
//  Klein Bottle Walk
//  Category: generative
//  Features: generative, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-23
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        val = val + amp * noise(p * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return val;
}

// Klein bottle parametric with UV mapping
fn kleinBottlePoint(u: f32, v: f32, r: f32) -> vec3<f32> {
    let cu = cos(u);
    let su = sin(u);
    let cv = cos(v);
    let sv = sin(v);
    let x = (r + cu * 0.5) * cv;
    let y = (r + cu * 0.5) * sv;
    let z = su * 0.5;
    return vec3<f32>(x, y, z);
}

fn hue2rgb(h: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(h + k) * 6.0 - 3.0);
    return clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
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
    
    // Walk position on Klein bottle surface
    let walkSpeed = mix(0.1, 0.5, param2);
    let walkU = time * walkSpeed + uv.x * 6.283185;
    let walkV = time * walkSpeed * 0.7 + uv.y * 6.283185;
    
    let kb = kleinBottlePoint(walkU, walkV, 1.0 + bass * 0.3);
    
    // Surface texture from FBM
    let texCoord = vec2<f32>(walkU / 6.283185, walkV / 6.283185);
    let surfaceNoise = fbm(texCoord * mix(4.0, 16.0, param3) + vec2<f32>(time * 0.05), 4);
    
    // Curvature approximation for lighting
    let kb_u = kleinBottlePoint(walkU + 0.01, walkV, 1.0);
    let kb_v = kleinBottlePoint(walkU, walkV + 0.01, 1.0);
    let du = kb_u - kb;
    let dv = kb_v - kb;
    let normal = normalize(cross(du, dv));
    
    let lightDir = normalize(vec3<f32>(sin(time * 0.2), cos(time * 0.15), 0.8));
    let diffuse = max(dot(normal, lightDir), 0.0);
    let specular = pow(max(dot(normal, normalize(lightDir + vec3<f32>(0.0, 0.0, 1.0))), 0.0), 32.0);
    
    // Audio-driven color
    let hue = fract(kb.z * 0.3 + surfaceNoise * 0.4 + time * 0.02 + mids * 0.1);
    let sat = mix(0.3, 0.85, param4 + treble * 0.2);
    let val = mix(0.2, 1.0, diffuse + surfaceNoise * 0.3 + bass * 0.2);
    
    let rgb = hue2rgb(hue) * sat + vec3<f32>(1.0 - sat) * val;
    let specColor = vec3<f32>(1.0, 0.9, 0.7) * specular * (1.0 + treble);
    
    let finalRGB = rgb * val + specColor;
    let alpha = clamp(diffuse * 0.5 + surfaceNoise * 0.3 + specular * 0.2 + 0.15, 0.0, 1.0);
    let finalColor = vec4<f32>(finalRGB, alpha);
    
    let depth = textureLoad(readDepthTexture, vec2<i32>(global_id.xy), 0).r;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
