// ═══════════════════════════════════════════════════════════════════
//  Holographic Contour
//  Category: artistic
//  Features: mouse-driven, audio-reactive, audio-driven
//  Upgraded: 2026-06-28
//  By: Codex
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
  config: vec4<f32>,    // .x=time, .y=click_count, .zw=resolution
  zoom_config: vec4<f32>, // .x=zoom, .yz=mouseXY (0..1), .w=click_flag
  zoom_params: vec4<f32>, // 4 user params mapped 0..1
  ripples: array<vec4<f32>, 50>, // ripple history for temporal fx
};

fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((color * (a * color + b)) / (color * (c * color + d) + e));
}

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let click = u.zoom_config.w;
    
    let dotSize = ((u.zoom_params.x * 20.0) + 2.0);
    let edgeThresh = max(0.01, ((1.0 - u.zoom_params.y) * 0.5));
    let levels = (floor((u.zoom_params.z * 10.0)) + 2.0);
    let inkDensity = u.zoom_params.w;
    
    // Audio Reactivity (bass, mid, treble + bins)
    let bass = plasmaBuffer[0].x;
    let mid = plasmaBuffer[1].x;
    let treble = plasmaBuffer[2].x;
    let bin1 = plasmaBuffer[3].x;
    
    // Persistent state: Bounded Spring for held pointer
    if (global_id.x == 0u && global_id.y == 0u) {
        var spring = extraBuffer[133];
        var vel = extraBuffer[134];
        let target = select(0.0, 1.0, click > 0.5);
        let force = (target - spring) * 0.2;
        vel = (vel + force) * 0.7;
        spring = clamp(spring + vel, 0.0, 1.0);
        extraBuffer[133] = spring;
        extraBuffer[134] = vel;
        extraBuffer[135] = time;
    }
    workgroupBarrier();
    let held_spring = extraBuffer[133];
    
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;
    
    var mp = mouse * 2.0 - 1.0;
    mp.x *= aspect;
    
    // Read previous frame from dataTextureC exactly
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    
    // Capped click fronts
    var ripple_sum = 0.0;
    for (var i = 0u; i < 50u; i++) {
        let rip = u.ripples[i];
        if (rip.w > 0.0) {
            let rip_p = rip.xy * 2.0 - 1.0;
            let rp = vec2<f32>(rip_p.x * aspect, rip_p.y);
            let d = length(p - rp);
            let age = time - rip.w;
            if (age > 0.0 && age < 3.0) {
                let r = age * 1.5;
                let w = 0.05 + age * 0.02;
                let v = smoothstep(w, 0.0, abs(d - r));
                ripple_sum += v * smoothstep(3.0, 2.0, age);
            }
        }
    }
    ripple_sum = min(ripple_sum, 1.5);
    
    // Continuous geometry raymarching for Holographic Contour
    var ro = vec3<f32>(0.0, 0.0, -3.5);
    var rd = normalize(vec3<f32>(p, 1.5));
    
    // Held pointer response shifts ray origin
    ro.x += mp.x * held_spring * 0.5;
    ro.y -= mp.y * held_spring * 0.5;
    
    var dist = 0.0;
    var t = 0.0;
    var hit_pos = ro;
    
    for (var i = 0; i < 60; i++) {
        var pos = ro + rd * t;
        
        // Add twist and wave using audio and ripple
        pos.xz = rot(time * 0.1 + ripple_sum * 0.5) * pos.xz;
        pos.xy = rot(sin(time * 0.05 + pos.z) * 0.5) * pos.xy;
        
        let q = fract(pos + vec3<f32>(0.0, 0.0, time * 0.2)) - 0.5;
        let d_grid = length(q) - (0.15 + bass * 0.05 * bin1);
        
        let d_shape = length(pos) - (dotSize * 0.1) - mid * 0.1;
        
        let d_final = max(d_grid, d_shape);
        dist = d_final;
        
        if (dist < 0.001 || t > 10.0) {
            hit_pos = pos;
            break;
        }
        t += dist;
    }
    
    var col = vec3<f32>(0.0);
    var alpha = 0.0;
    
    if (t < 10.0) {
        // Holographic optical material
        let glow = saturate(1.0 - t * 0.1);
        let n_phase = time + hit_pos.x * levels + hit_pos.y * levels + hit_pos.z * levels;
        let c = vec3<f32>(0.5) + 0.5 * cos(n_phase + vec3<f32>(0.0, 2.0, 4.0));
        
        // Prismatic reflection
        let fresnel = pow(1.0 - saturate(dot(-rd, normalize(hit_pos))), 3.0);
        col = c * glow * (0.5 + fresnel * 2.0) + treble * vec3<f32>(0.2, 0.5, 1.0) * fresnel;
        alpha = saturate(glow * inkDensity * (0.5 + ripple_sum));
    }
    
    // Add contour edge detection from base image (readTexture) to match the name
    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0).xyz;
    let luma = dot(base, vec3<f32>(0.299, 0.587, 0.114));
    let edge_val = smoothstep(edgeThresh, edgeThresh + 0.1, luma);
    
    // Combine holographic raymarching with base image contour
    let contour_col = base * 2.0 * vec3<f32>(0.5, 1.0, 2.0);
    col = mix(col, contour_col, edge_val * 0.6);
    alpha = saturate(alpha + edge_val * inkDensity);
    
    // Mix with previous frame (dataTextureC)
    col = mix(col, prev.xyz, 0.3 * (1.0 - saturate(ripple_sum)));
    alpha = mix(alpha, prev.w, 0.3);
    
    // ACES Tonemap
    col = aces_tonemap(col);
    
    // Semantic alpha
    alpha = saturate(alpha);
    let final_rgba = vec4<f32>(col, alpha);
    
    // Write final output ONLY to dataTextureA and writeTexture
    textureStore(dataTextureA, vec2<i32>(global_id.xy), final_rgba);
    textureStore(writeTexture, vec2<i32>(global_id.xy), final_rgba);
}
