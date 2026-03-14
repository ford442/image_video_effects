// ═══════════════════════════════════════════════════════════════
//  Neon Strings - Vibration Edge Effect with Alpha Emission
//  Category: lighting-effects
//  Physics: Emissive string vibration with alpha occlusion
//  Alpha: Core tube = 0.3, Glow = 0.0 (additive)
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn get_luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn sobel(uv: vec2<f32>) -> f32 {
    let texel = vec2<f32>(1.0 / u.config.z, 1.0 / u.config.w);
    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;

    let gx = -1.0 * get_luminance(l) + 1.0 * get_luminance(r);
    let gy = -1.0 * get_luminance(t) + 1.0 * get_luminance(b);

    return sqrt(gx * gx + gy * gy);
}

// Inverse square law for light falloff
fn inverseSquareFalloff(dist: f32, maxDist: f32) -> f32 {
    let d = max(dist, 0.001);
    return 1.0 / (1.0 + d * d * 5.0) * (1.0 - smoothstep(maxDist * 0.5, maxDist, dist));
}

// Alpha calculation for emissive materials
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  var mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = distance(uv_corrected, mouse_corrected);

  // Params
  // x: Thickness (Edge Threshold)
  // y: Vibration amplitude
  // z: Radius
  // w: Occlusion balance (alpha control)
  let thickness = max(0.01, u.zoom_params.x);
  let vibration_amp = u.zoom_params.y;
  let radius = u.zoom_params.z;
  let occlusionBalance = u.zoom_params.w;

  // Vibration logic - standing wave pattern near mouse
  let freq = 50.0;
  let wave = sin(uv.y * freq + time * 10.0);
  let influence = smoothstep(radius, 0.0, dist);

  // Displace UVs for sampling to simulate vibrating strings
  let displacement = vec2<f32>(wave * vibration_amp * influence * 0.02, 0.0);
  let distorted_uv = uv + displacement;

  // Sobel Edge Detection on distorted UV
  let edge = sobel(distorted_uv);

  // Thresholding with smoothstep for anti-aliased edge
  let edge_val = smoothstep(thickness, thickness + 0.1, edge);

  // Sample original color at distorted UV to get the hue
  let original_color = textureSampleLevel(readTexture, u_sampler, distorted_uv, 0.0).rgb;

  // Neon emission calculation - can exceed 1.0 for HDR
  let baseIntensity = 2.0;
  let emission = original_color * baseIntensity * edge_val;

  // Apply inverse square falloff from mouse
  let lightFalloff = inverseSquareFalloff(dist, radius * 2.0);
  
  // Total emission including falloff
  let totalEmission = emission * (1.0 + lightFalloff * 2.0);

  // Calculate alpha based on emission intensity
  let glowIntensity = length(totalEmission) * edge_val;
  let finalAlpha = calculateEmissiveAlpha(glowIntensity, occlusionBalance);

  // Output RGBA: RGB = emission (HDR), A = physical occlusion
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(totalEmission, finalAlpha));

  // Update depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
