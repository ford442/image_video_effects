// ═══════════════════════════════════════════════════════════════════
//  Chaos Game IFS Fractal
//  Category: generative
//  Features: generative, audio-reactive, upgraded-rgba
//  Complexity: Medium
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

fn hue2rgb(h: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(h + k) * 6.0 - 3.0);
    return clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
}

// IFS attractor point with rotation
fn ifsPoint(uv: vec2<f32>, iter: i32, time: f32, bass: f32) -> vec2<f32> {
    var p = uv * 2.0 - 1.0;
    let rot = time * 0.1 + bass * 0.5;
    let c = cos(rot);
    let s = sin(rot);
    
    for (var i: i32 = 0; i < iter; i = i + 1) {
        let fi = f32(i);
        // Three attractor points forming Sierpinski-like pattern
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
    
    let iterations = i32(mix(3.0, 12.0, param1 + bass * 0.3));
    let p = ifsPoint(uv, iterations, time, bass);
    
    let d = length(p);
    let angle = atan2(p.y, p.x) / (2.0 * 3.14159265);
    
    // Glow from attractor density
    let glow = 1.0 / (1.0 + d * d * mix(4.0, 20.0, param2));
    let rings = smoothstep(0.0, 0.1, abs(fract(d * mix(3.0, 10.0, param3)) - 0.5));
    
    let hue = fract(angle + time * 0.03 + mids * 0.15);
    let sat = mix(0.4, 1.0, param4 + treble * 0.3);
    let val = glow * (0.5 + rings * 0.5) * (1.0 + bass * 0.3);
    
    let rgb = hue2rgb(hue) * sat + vec3<f32>(1.0 - sat) * val;
    
    let depth = textureLoad(readDepthTexture, vec2<i32>(global_id.xy), 0).r;
    let alpha = clamp(val * 0.7 + glow * 0.3 + 0.1, 0.0, 1.0);
    let finalColor = vec4<f32>(rgb * val, alpha);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
