// ═══════════════════════════════════════════════════════════════════
//  Symbiotic Light Propagation Networks
//  Category: generative
//  Features: light-transport, organic-networks, symbiotic-growth, audio-color, mouse-seeding
//  Complexity: High
//  Chunks From: light ray marching simulation + growth models
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
    let time = u.config.x * 0.3;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Read previous network state
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Growth influenced by light (previous frame brightness) + audio
    let lightReceived = prev.a;
    let growth = (0.015 + mids * 0.025) * (0.4 + lightReceived * 1.2);

    // Two symbiotic species
    let species1 = prev.r;
    let species2 = prev.g;

    // They support each other but also compete
    let support = species1 * species2 * 0.6;
    let compete = abs(species1 - species2) * 0.3;

    var newS1 = species1 * 0.97 + growth * (1.0 + support - compete);
    var newS2 = species2 * 0.97 + growth * (1.0 + support - compete * 0.8);

    // Mouse seeds the network
    let mouseDist = length(uv - mouse);
    let mouseSeed = smoothstep(0.1, 0.0, mouseDist) * mouseDown * 0.8;
    newS1 += mouseSeed * 0.5;
    newS2 += mouseSeed * 0.4;

    // Simple diffusion
    let ps = 1.0 / res;
    let n1 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(ps.x, 0.0), 0.0);
    let n2 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(ps.x, 0.0), 0.0);
    let n3 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, ps.y), 0.0);
    let n4 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, ps.y), 0.0);

    newS1 = (newS1 + n1.r + n2.r + n3.r + n4.r) * 0.2;
    newS2 = (newS2 + n1.g + n2.g + n3.g + n4.g) * 0.2;

    // Light transport simulation (very simplified)
    let lightDir = normalize(vec2<f32>(0.6, 0.4));
    let lightSample = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - lightDir * 0.03, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let transmittedLight = (lightSample.r + lightSample.g) * 0.4 * (0.6 + treble * 0.5);

    let totalDensity = newS1 + newS2;
    let light = transmittedLight * (1.0 - totalDensity * 0.4);

    // Store
    textureStore(dataTextureA, gid.xy, vec4<f32>(newS1, newS2, light, totalDensity));

    // Visualization: glowing organic network
    let c1 = vec3<f32>(0.3, 0.8, 0.5) * newS1;
    let c2 = vec3<f32>(0.8, 0.4, 0.7) * newS2;
    let glow = vec3<f32>(0.4, 0.7, 0.9) * light * 1.5;

    let col = c1 + c2 + glow;

    let alpha = clamp(totalDensity * 0.7 + light * 0.6, 0.2, 1.25);
    let a = clamp(alpha, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(col * a, a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(totalDensity * 0.6 + light * 0.4, 0.0, 0.0, 0.0));
}