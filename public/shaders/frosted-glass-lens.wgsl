// ═══════════════════════════════════════════════════════════════
// Frosted Glass Lens - Physical glass transmission with Beer-Lambert law
// Category: distortion
// Features: frost noise, lens distortion, chromatic aberration, alpha
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=FrostAmount, y=LensRadius, z=EdgeSoftness, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let frost_amt = u.zoom_params.x;
    let lens_radius = u.zoom_params.y * 0.4 + 0.05;
    let edge_softness = u.zoom_params.z * 0.2 + 0.01;
    let aberration = u.zoom_params.w * 0.02;
    let glassDensity = frost_amt * 1.5 + 0.5; // Density increases with frost

    // Mouse
    var mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Lens mask: 0 inside lens (clear), 1 outside (frost)
    let lens_mask = smoothstep(lens_radius, lens_radius + edge_softness, dist);

    // Generate Frost Noise
    let noise_val = hash12(uv * 100.0 + u.config.x * 0.1);
    let frost_offset = (noise_val - 0.5) * 0.05 * frost_amt * lens_mask;

    // Calculate normal for fresnel (rougher in frost areas)
    let roughNormal = normalize(vec3<f32>(frost_offset * 20.0, 1.0 - frost_amt * 0.5));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    
    // Fresnel effect (more reflection at edges of lens and in frost)
    let cos_theta = max(dot(viewDir, roughNormal), 0.0);
    let R0 = 0.04;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
    
    // Frost thickness varies with frost amount
    let thickness = 0.03 + frost_amt * 0.1 * (1.0 + noise_val);
    
    // Frosted glass color (slight white/blue tint)
    let glassColor = vec3<f32>(0.92, 0.95, 0.98);
    
    // Beer-Lambert absorption (more opaque when frosted)
    let absorption = exp(-(1.0 - glassColor) * thickness * glassDensity);
    
    // Transmission coefficient - frost reduces transparency
    let baseTransmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;
    let transmission = mix(baseTransmission, baseTransmission * 0.7, frost_amt * lens_mask);

    // Sample with offset for frost effect
    var final_color: vec4<f32>;

    if (lens_mask > 0.001) {
         // Outside or edge of lens: blurred/frosted
         let sample_uv = uv + vec2<f32>(frost_offset);
         final_color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);
         // Frost whitening with reduced transmission
         let frostTint = mix(vec3<f32>(1.0), glassColor, 0.7);
         final_color = vec4<f32>(mix(final_color.rgb, frostTint, 0.2 * frost_amt * lens_mask), transmission);
    } else {
         // Inside lens: clear with slight tint
         final_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
         final_color = vec4<f32>(final_color.rgb * glassColor, baseTransmission);
    }

    // Edge Aberration with transmission consideration
    let ab_mask = smoothstep(lens_radius, lens_radius + edge_softness * 0.5, dist) * 
                  (1.0 - smoothstep(lens_radius + edge_softness * 0.5, lens_radius + edge_softness, dist));

    // Final sampling with chromatic aberration
    let uv_r = uv + vec2<f32>(frost_offset) + vec2<f32>(aberration * ab_mask, 0.0);
    let uv_g = uv + vec2<f32>(frost_offset);
    let uv_b = uv + vec2<f32>(frost_offset) - vec2<f32>(aberration * ab_mask, 0.0);

    let col_r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let col_g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let col_b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    var color = vec4<f32>(col_r, col_g, col_b, transmission);

    // Apply frost tint based on lens mask
    let frostTint = vec3<f32>(0.9, 0.95, 1.0);
    color = vec4<f32>(mix(color.rgb, color.rgb * frostTint, 0.3 * frost_amt * lens_mask), transmission);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
}
