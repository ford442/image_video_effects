// ═══════════════════════════════════════════════════════════════════
//  Quantum Field Visualizer
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Shader Upgrade Swarm — Phase A
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ObsStrength, y=Speed, z=Energy, w=Uncertainty
  ripples: array<vec4<f32>, 50>,
};

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(coord) / resolution;

    let bass = plasmaBuffer[0].x;
    let obs_strength = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let energy = u.zoom_params.z * (1.0 + bass * 0.4);
    let uncertainty = u.zoom_params.w;

    let time = u.config.x * (0.5 + speed * 2.0);
    var mouse = u.zoom_config.yz;
    let aspect = u.config.z / max(u.config.w, 1.0);

    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    let radius = mix(0.1, 0.8, obs_strength);
    let collapse = smoothstep(radius, 0.0, dist);

    let seed = vec3<f32>(uv * 50.0, time);
    let noise = hash3(seed);

    let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgba;

    let q_color = 0.5 + 0.5 * sin(time + uv.xyx * 10.0 + vec3<f32>(0.0, 2.0, 4.0));
    let chaotic_color = mix(noise, q_color, energy);

    let mix_factor = (1.0 - collapse) * (0.5 + 0.5 * uncertainty);
    var final_color = mix(base_color.rgb, chaotic_color, mix_factor);

    let glow = (1.0 - abs(collapse * 2.0 - 1.0)) * energy * 0.5;
    final_color += vec3<f32>(0.2, 0.5, 1.0) * glow;

    // Alpha encodes quantum state: collapsed (near mouse) = image alpha, uncollapsed = chaos energy
    let luma = dot(final_color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(collapse * base_color.a + (1.0 - collapse) * (energy * 0.5 + glow) + luma * 0.1, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(final_color, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
