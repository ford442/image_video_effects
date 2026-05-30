// ═══════════════════════════════════════════════════════════════════
//  Velvet Vortex
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, spiral-sdf, upgraded-rgba
//  Complexity: High
//  Chunks From: velvet-vortex, bass_env, depth-aware-fog
//  Upgraded: 2026-05-31
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

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let center = u.zoom_config.yz;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let parallax = (depth - 0.5) * 0.04;

    let radiusParam = max(u.zoom_params.x, 0.001);
    let strength = u.zoom_params.y * bass_env(bass, mids);
    let softness = u.zoom_params.z;
    let pulseSpeed = u.zoom_params.w;

    let uvCorrected = uv * vec2<f32>(aspect, 1.0);
    let centerCorrected = center * vec2<f32>(aspect, 1.0) + vec2<f32>(parallax, parallax);
    let dist = distance(uvCorrected, centerCorrected);
    let pulse = sin(time * pulseSpeed * bass_env(bass, mids) * 5.0) * 0.2 + 1.0;
    let effectiveRadius = max(radiusParam * pulse, 0.001);
    let swirlFactor = 1.0 - smoothstep(0.0, effectiveRadius, dist);
    let softFactor = pow(swirlFactor, 1.0 / (softness + 0.1));

    // Audio modulates arm count
    let armCount = 3.0 + floor(mids * 6.0);
    let angle = strength * (8.0 + armCount) * softFactor;

    let s = sin(angle);
    let c = cos(angle);
    let dir = uvCorrected - centerCorrected;
    let rotatedDir = vec2<f32>(
        dir.x * c - dir.y * s,
        dir.x * s + dir.y * c
    );
    let finalUV = clamp((rotatedDir + centerCorrected) / vec2<f32>(aspect, 1.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let baseColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
    let velvetTint = vec3<f32>(0.12 + bass * 0.05, 0.02 + treble * 0.04, 0.16 + bass * 0.05) * softFactor;
    let finalColor = mix(baseColor.rgb, baseColor.rgb * vec3<f32>(0.85, 0.78 + treble * 0.08, 1.08), softFactor * 0.25) + velvetTint;
    let alpha = clamp(baseColor.a * 0.45 + softFactor * 0.35 + bass * 0.06, 0.08, 1.0);
    let depthOut = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + softFactor * 0.05, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
