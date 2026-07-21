// ═══════════════════════════════════════════════════════════════════
//  Zeta Function Landscape
//  Category: generative
//  Features: generative, audio-reactive, upgraded-rgba, aces-tone-map, temporal-smoothing, chromatic-zeros,
//            bass-term-modulation, depth-output
//  Complexity: High
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash21(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn zetaApprox(s_re: f32, s_im: f32, terms: i32) -> vec2<f32> {
    var sum_re = 0.0;
    var sum_im = 0.0;
    for (var n: i32 = 1; n <= terms; n = n + 1) {
        let ln_n = log(f32(n));
        let phase = -s_im * ln_n;
        let c = cos(phase);
        let s = sin(phase);
        let denom = exp(-s_re * ln_n);
        sum_re = sum_re + denom * c;
        sum_im = sum_im + denom * s;
    }
    return vec2<f32>(sum_re, sum_im);
}

fn hue2rgb(h: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(h + k) * 6.0 - 3.0);
    return clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
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
    let mouse = u.zoom_config.yz;
    
    let param1 = u.zoom_params.x;
    let param2 = u.zoom_params.y;
    let param3 = u.zoom_params.z;
    let param4 = u.zoom_params.w;
    
    let sigma = 0.5 + (param1 - 0.5) * 0.3;
    let t_min = -20.0 - param2 * 40.0 + bass * 5.0;
    let t_max = 20.0 + param2 * 40.0 - bass * 5.0;
    let t_range = t_max - t_min;
    
    let t = t_min + uv.x * t_range + (mouse.x - 0.5) * 10.0;
    let y_offset = (uv.y - 0.5) * 8.0 * (1.0 + param3 * 2.0) + (mouse.y - 0.5) * 4.0;
    
    let terms = i32(mix(50.0, 200.0, param4 + treble * 0.3));
    let z = zetaApprox(sigma, t + y_offset * 0.1, terms);
    let z_mag = sqrt(z.x * z.x + z.y * z.y);
    let z_arg = atan2(z.y, z.x) / (2.0 * 3.14159265);
    
    let height = log(1.0 + z_mag) * 0.3;
    let ridge = smoothstep(0.5, 1.5, height);
    
    let zeroProximity = 1.0 / (1.0 + z_mag * z_mag * 0.5);
    
    // Chromatic zeros: near zeros shift color toward cyan/purple
    let hue = fract(z_arg + time * 0.02 + mids * 0.1 + uv.x * 0.2);
    let zeroHue = mix(hue, 0.5 + treble * 0.2, zeroProximity * 0.5);
    let sat = mix(0.5, 1.0, ridge + bass * 0.3);
    let val = mix(0.2, 1.0, height + zeroProximity * 0.5);
    
    let rgb = hue2rgb(zeroHue) * sat + vec3<f32>(1.0 - sat) * val;
    
    // Temporal smoothing: previous frame averages for landscape stability
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let smoothed = mix(rgb, prev, 0.08 + bass * 0.02);
    
    let alpha = clamp(height * 0.7 + ridge * 0.3 + bass * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(acesToneMap((smoothed * val) * 1.1), alpha);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(height, 0.0, 0.0, 0.0));
}
