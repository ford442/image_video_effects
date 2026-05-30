// ═══════════════════════════════════════════════════════════════════
//  Ripple Bloom
//  Category: hybrid
//  Features: ripple, bloom, audio-reactive, mouse-interactive, semantic-alpha, hybrid
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let rippleAmount = u.zoom_params.x * (0.8 + bass * 0.7);
    let bloomAmount = u.zoom_params.y * (0.9 + treble * 0.6);
    let mouseInfluence = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    let mouse = u.zoom_config.yz;
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Ripple distortion
    let distToMouse = length(uv - mouse);
    let ripplePhase = distToMouse * 18.0 - time * 3.5;
    let ripple = sin(ripplePhase) * exp(-distToMouse * 4.0) * rippleAmount;

    let displacedUV = clamp(uv + vec2<f32>(ripple * 0.015, ripple * 0.012), vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // Bloom on bright areas + audio
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let bloom = smoothstep(0.55, 0.92, luma) * bloomAmount;
    color += bloom * vec3<f32>(0.6, 0.8, 1.0) * (0.6 + mids * 0.5);

    // Mouse light tint
    let mouseLight = (1.0 - smoothstep(0.0, 0.45, distToMouse)) * mouseInfluence * 0.5;
    color += mouseLight * vec3<f32>(0.8, 0.9, 1.0);

    // Subtle color shift from audio
    let hueShift = colorShift * 0.15 + mids * 0.08;
    color = mix(color, color * vec3<f32>(1.0 + hueShift, 1.0 - hueShift * 0.5, 1.0 - hueShift), 0.2);

    // Semantic alpha - higher where bloom or ripple is strong
    let effect = bloom * 0.5 + abs(ripple) * 2.5 * rippleAmount + mouseLight * 0.6;
    let semantic_alpha = clamp(0.58 + effect * 0.55, 0.45, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, semantic_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}