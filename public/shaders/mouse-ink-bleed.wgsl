// ═══════════════════════════════════════════════════════════════════
//  Mouse Ink Bleed
//  Category: interactive-mouse
//  Features: mouse-driven, ink-diffusion, organic, audio-reactive, semantic-alpha
//  Complexity: Medium
//  Created: 2026-05-30
//  Updated: 2026-06-01
//  By: Kimi Agent (integrated + upgraded)
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let mouse = u.zoom_config.yz;
    let isPress = u.zoom_config.w;

    let spread = u.zoom_params.x;
    let turbulence = u.zoom_params.y;
    let decay = u.zoom_params.z;
    let colorIntensity = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    let dist = length(uv - mouse);
    let activeBrush = smoothstep(spread * 0.6, spread * 0.08, dist) * (0.6 + isPress * 1.2);

    let inkRadius = activeBrush * (0.7 + bass * 0.5);

    // Turbulent displacement for organic bleed
    let turb = turbulence * (1.0 + treble * 0.6);
    let gradX = noise(uv * turb * 6.0 + vec2<f32>(0.01, 0.0)) - noise(uv * turb * 6.0 - vec2<f32>(0.01, 0.0));
    let gradY = noise(uv * turb * 6.0 + vec2<f32>(0.0, 0.01)) - noise(uv * turb * 6.0 - vec2<f32>(0.0, 0.01));
    let displacement = vec2<f32>(gradX, gradY) * inkRadius * spread * 2.0;

    let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let inkColor = mix(vec3<f32>(luminance), color * vec3<f32>(0.3, 0.25, 0.35), 0.3);
    color = mix(color, inkColor, inkRadius * colorIntensity);

    let edgeGlow = smoothstep(0.1, 0.6, inkRadius) * (1.0 - smoothstep(0.4, 0.9, inkRadius));
    color += vec3<f32>(0.05, 0.02, 0.08) * edgeGlow * colorIntensity * (0.8 + mids * 0.4);

    // Semantic alpha - stronger where the ink is actively bleeding
    let effect = inkRadius * 0.7 + edgeGlow * 0.5;
    let semantic_alpha = clamp(0.5 + effect * 0.6, 0.4, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, semantic_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}