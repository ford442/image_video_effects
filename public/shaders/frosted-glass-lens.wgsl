// ═══════════════════════════════════════════════════════════════════
//  Frosted Glass Lens
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-17
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=FrostAmount, y=LensRadius, z=EdgeSoftness, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv    = vec2<f32>(global_id.xy) / resolution;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params — bass pulses frost amount, mids drive aberration
    let frost_amt_base = u.zoom_params.x;
    let frost_dyn      = frost_amt_base * (1.0 + bass * 0.3);
    let lens_radius    = u.zoom_params.y * 0.4 + 0.05;
    let edge_softness  = u.zoom_params.z * 0.2 + 0.01;
    let aberration     = u.zoom_params.w * 0.02 * (1.0 + mids * 0.5);
    let glassDensity   = frost_dyn * 1.5 + 0.5;

    // Mouse
    let mouse  = u.zoom_config.yz;
    let aspect = resolution.x / max(resolution.y, 0.001);

    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist     = length(dist_vec);

    // Lens mask: 0 inside lens (clear), 1 outside (frost)
    let lens_mask = smoothstep(lens_radius, lens_radius + edge_softness, dist);

    // Generate frost noise
    let noise_val    = hash12(uv * 100.0 + u.config.x * 0.1);
    let frost_offset = (noise_val - 0.5) * 0.05 * frost_dyn * lens_mask;

    // Fresnel via rough normal
    let roughNormal = normalize(vec3<f32>(frost_offset * 20.0, 0.0, 1.0 - frost_dyn * 0.5));
    let viewDir     = vec3<f32>(0.0, 0.0, 1.0);
    let cos_theta   = max(dot(viewDir, roughNormal), 0.0);
    let R0          = 0.04;
    let fresnel     = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);

    // Beer-Lambert thickness and absorption
    let thickness   = 0.03 + frost_dyn * 0.1 * (1.0 + noise_val);
    let glassColor  = vec3<f32>(0.92, 0.95, 0.98);
    let absorption  = exp(-(1.0 - glassColor) * thickness * glassDensity);

    let baseTransmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;
    let transmission     = mix(baseTransmission, baseTransmission * 0.7, frost_dyn * lens_mask);

    // ── Branchless replacement of the if(lens_mask > 0.001)/else ──
    // Branch A: outside/edge of lens — frosted sample
    let sample_uv_a = uv + vec2<f32>(frost_offset);
    let tex_a       = textureSampleLevel(readTexture, u_sampler, sample_uv_a, 0.0);
    let frostTint_a = mix(vec3<f32>(1.0), glassColor, 0.7);
    let rgb_a       = mix(tex_a.rgb, frostTint_a, 0.2 * frost_dyn * lens_mask);

    // Branch B: inside lens — clear with slight tint
    let tex_b = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let rgb_b = tex_b.rgb * glassColor;

    // Mix by lens_mask (0=inside=branch B, 1=outside=branch A)
    let blended_rgb = mix(rgb_b, rgb_a, lens_mask);
    // alpha also blended: inside uses baseTransmission, outside uses transmission
    let blended_alpha = mix(baseTransmission, transmission, lens_mask);

    // Edge chromatic aberration mask
    let ab_mask = smoothstep(lens_radius, lens_radius + edge_softness * 0.5, dist) *
                  (1.0 - smoothstep(lens_radius + edge_softness * 0.5, lens_radius + edge_softness, dist));

    // Final sampling with chromatic aberration (overrides blended_rgb for final color)
    let uv_r = uv + vec2<f32>(frost_offset) + vec2<f32>(aberration * ab_mask, 0.0);
    let uv_g = uv + vec2<f32>(frost_offset);
    let uv_b = uv + vec2<f32>(frost_offset) - vec2<f32>(aberration * ab_mask, 0.0);

    let col_r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let col_g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let col_b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    // Apply frost tint to aberrated color
    let frostTint  = vec3<f32>(0.9, 0.95, 1.0);
    let ab_rgb_raw = vec3<f32>(col_r, col_g, col_b);
    let ab_rgb     = mix(ab_rgb_raw, ab_rgb_raw * frostTint, 0.3 * frost_dyn * lens_mask);

    // Where we have aberration (ab_mask > 0), use aberrated color; elsewhere use blended
    let final_rgb   = mix(blended_rgb, ab_rgb, ab_mask);
    let final_alpha = blended_alpha; // Beer-Lambert transmission as alpha

    let finalColor = vec4<f32>(final_rgb, final_alpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);

    // Depth passthrough
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
