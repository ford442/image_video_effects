// ═══════════════════════════════════════════════════════════════════
//  Gravito-Phononic Accretion
//  Category: generative
//  Features: gravitational-accretion, audio-driven, lensing, particle-density, mouse-gravity
//  Complexity: High
//  Chunks From: inverse-square field summation + density advection
//  Created: 2026-05-31
//  By: Grok (creative technical artist)
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
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.4;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Read previous density
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;

    // Audio-controlled gravitational centers
    let g1 = vec2<f32>(0.3 + sin(time * 0.3) * 0.1, 0.4 + cos(time * 0.25) * 0.08);
    let g2 = vec2<f32>(0.7 + cos(time * 0.4) * 0.09, 0.65 + sin(time * 0.35) * 0.07);

    // Gravitational strength from audio
    let mass1 = 0.8 + bass * 1.2;
    let mass2 = 0.7 + mids * 1.1;
    let mass3 = 0.9 + treble * 0.8;

    // Compute gravitational pull from multiple centers
    let d1 = length(uv - g1) + 0.08;
    let d2 = length(uv - g2) + 0.08;
    let d3 = length(uv - mouse) + 0.05;

    let gForce = (mass1 / (d1 * d1)) * normalize(g1 - uv) * 0.04 +
                 (mass2 / (d2 * d2)) * normalize(g2 - uv) * 0.035 +
                 (mass3 * mouseDown / (d3 * d3)) * normalize(mouse - uv) * 0.06;

    // Sample density in the direction of gravitational flow
    let flowUV = clamp(uv - gForce * 12.0, vec2<f32>(0.0), vec2<f32>(1.0));
    let flowed = textureSampleLevel(dataTextureC, u_sampler, flowUV, 0.0).r;

    // Accretion with some diffusion
    var density = flowed * 0.96 + prev * 0.04;

    // Add small noise for visual interest
    let noise = hash12(uv * 15.0 + time * 0.8) - 0.5;
    density += noise * 0.008 * (0.5 + treble * 0.8);

    // Store
    textureStore(dataTextureA, gid.xy, vec4<f32>(density, 0.0, 0.0, 0.0));

    // Visualization with gravitational lensing effect
    let core = smoothstep(0.08, 0.0, d1) * mass1 * 0.6 + smoothstep(0.07, 0.0, d2) * mass2 * 0.55;
    let col = mix(vec3<f32>(0.05, 0.04, 0.08), vec3<f32>(0.95, 0.9, 0.6), density * 0.8);
    let finalCol = col + vec3<f32>(0.4, 0.6, 1.0) * core * 0.7;

    let alpha = clamp(density * 0.9 + core * 0.6, 0.15, 1.25);
    let a = clamp(alpha, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(finalCol * a, a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(density * 0.7, 0.0, 0.0, 0.0));
}