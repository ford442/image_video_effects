// ═══════════════════════════════════════════════════════════════════
//  Sim: Ink Diffusion
//  Category: artistic
//  Features: simulation, reaction-diffusion, multi-channel, paper-texture
//  Complexity: High
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Gray-Scott reaction-diffusion (multi-channel)
//  Each RGB = separate chemical with Wolfram-validated parameters
//  Paper texture affects diffusion rate
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

// Paper texture function
fn paperTexture(uv: vec2<f32>) -> f32 {
    var tex = 0.0;
    for (var i: i32 = 0; i < 3; i++) {
        let fi = f32(i);
        tex += hash12(uv * 100.0 * (fi + 1.0)) * pow(0.5, fi + 1.0);
    }
    return 0.8 + tex * 0.4;
}

fn laplacian9(coord: vec2<i32>, channel: i32) -> f32 {
    var sum: f32 = 0.0;
    let kernel = array<f32, 9>(0.05, 0.2, 0.05, 0.2, -1.0, 0.2, 0.05, 0.2, 0.05);
    var k: i32 = 0;
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let sample = textureLoad(dataTextureC, coord + vec2<i32>(i, j), 0)[channel];
            sum += sample * kernel[k];
            k++;
        }
    }
    return sum;
}

fn reactDiffuse(u_val: f32, v_val: f32, lapU: f32, lapV: f32, F: f32, k: f32, diffRate: f32) -> vec2<f32> {
    let Du = 0.16 * diffRate;
    let Dv = 0.08 * diffRate;
    
    let uvv = u_val * v_val * v_val;
    let newU = u_val + Du * lapU - uvv + F * (1.0 - u_val);
    let newV = v_val + Dv * lapV + uvv - (F + k) * v_val;
    
    return vec2<f32>(clamp(newU, 0.0, 1.0), clamp(newV, 0.0, 1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let id = vec2<i32>(global_id.xy);
    let time = u.config.x;
    
    // Parameters
    let wetness = mix(0.5, 1.5, u.zoom_params.x);      // x: Paper wetness (diffusion)
    let viscosity = mix(0.8, 1.2, u.zoom_params.y);    // y: Ink viscosity
    let feedRate = mix(0.01, 0.06, u.zoom_params.z);   // z: Feed rate
    let colorMixing = u.zoom_params.w;                  // w: Color mixing
    
    // Paper texture affects diffusion
    let paper = paperTexture(uv);
    let diffRate = wetness * paper;
    
    // Wolfram-validated parameters for different patterns
    // Coral: F=0.0545, k=0.062
    // Fingerprint: F=0.0545, k=0.063
    // Spots/Waves: F=0.018, k=0.050
    let patterns = array<vec2<f32>, 3>(
        vec2<f32>(0.0545, 0.062), // Coral (red channel)
        vec2<f32>(0.0545, 0.063), // Fingerprint (green channel)
        vec2<f32>(0.018, 0.050)   // Spots (blue channel)
    );
    
    // Read current chemical states (U in rgb, V in alpha)
    let curU = textureLoad(dataTextureC, id, 0).rgb;
    let curV = textureLoad(dataTextureC, id, 0).aaa;
    
    // Process each channel
    var newU = vec3<f32>(0.0);
    var newV = vec3<f32>(0.0);
    
    for (var ch: i32 = 0; ch < 3; ch++) {
        let lapU = laplacian9(id, ch);
        let lapV = laplacian9(id, 3); // V stored in alpha
        
        let F = patterns[ch].x * feedRate * 20.0;
        let k = patterns[ch].y;
        
        let result = reactDiffuse(curU[ch], curV[ch], lapU, lapV, F, k, diffRate);
        newU[ch] = result.x;
        newV[ch] = result.y;
    }
    
    // Inject ink at mouse position
    let mouse = u.zoom_config.yz;
    let distToMouse = distance(uv, mouse);
    if (distToMouse < 0.04) {
        let drop = (1.0 - distToMouse / 0.04) * 0.3;
        let hue = fract(time * 0.1);
        newU += vec3<f32>(
            drop * (0.5 + 0.5 * cos(hue * 6.28)),
            drop * (0.5 + 0.5 * cos(hue * 6.28 + 2.09)),
            drop * (0.5 + 0.5 * cos(hue * 6.28 + 4.18))
        );
        newV += vec3<f32>(drop);
    }
    
    // Store state
    textureStore(dataTextureA, id, vec4<f32>(newU, newV.r));
    
    // Mix channels for color mixing effect
    let mixedU = vec3<f32>(
        mix(newU.r, (newU.g + newU.b) * 0.5, colorMixing * 0.3),
        mix(newU.g, (newU.r + newU.b) * 0.5, colorMixing * 0.3),
        mix(newU.b, (newU.r + newU.g) * 0.5, colorMixing * 0.3)
    );
    
    // Ink colors - deep traditional ink tones
    let inkColor = vec3<f32>(
        mixedU.r * 0.1 + mixedU.g * 0.05 + mixedU.b * 0.3,  // Deep blue
        mixedU.r * 0.05 + mixedU.g * 0.1 + mixedU.b * 0.1,  // Dark green
        mixedU.r * 0.3 + mixedU.g * 0.1 + mixedU.b * 0.05   // Deep red
    );
    
    // Paper color
    let paperColor = vec3<f32>(0.95, 0.92, 0.85) * paper;
    
    // Blend ink with paper
    let inkDensity = length(mixedU);
    var color = mix(paperColor, inkColor, inkDensity);
    
    // Add paper grain
    color *= 0.98 + hash12(uv * 500.0) * 0.04;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.9, 1.0, inkDensity);
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - inkDensity * 0.1), 0.0, 0.0, 0.0));
}
