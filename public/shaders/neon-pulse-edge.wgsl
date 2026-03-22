// ═══════════════════════════════════════════════════════════════
//  Neon Pulse Edge - Animated Edge Glow with Alpha Emission
//  Category: lighting-effects
//  Physics: Pulsing emissive edges with alpha occlusion
//  Alpha: Core edge = 0.3, Glow = 0.0 (additive)
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

// Alpha calculation for emissive materials
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

// Inverse square law for light falloff
fn inverseSquareFalloff(dist: f32, maxDist: f32) -> f32 {
    let d = max(dist, 0.001);
    return 1.0 / (1.0 + d * d * 5.0) * smoothstep(maxDist, 0.0, dist);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  // ═══ AUDIO REACTIVITY ═══
  let audioOverall = u.zoom_config.x;
  let audioBass = audioOverall * 1.5;
  let audioReactivity = 1.0 + audioOverall * 0.3;

  var mousePos = u.zoom_config.yz;

  // Params
  // x: PulseSpeed, y: GlowStrength, z: EdgeThreshold, w: OcclusionBalance
  let speed = u.zoom_params.x * 5.0;
  let glowStr = u.zoom_params.y * 2.0;
  let threshold = u.zoom_params.z;
  let radius = 0.3;
  let occlusionBalance = u.zoom_params.w;

  // Sobel Edge Detection
  let texel = vec2<f32>(1.0) / resolution;

  let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb;
  let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
  let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb;
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;

  let gx = length(l - r);
  let gy = length(t - b);
  let edge = sqrt(gx*gx + gy*gy);

  // Base emission
  var emission = vec3<f32>(0.0);

  if (edge > threshold) {
      // Base Neon Color with time cycling
      var neon = vec3<f32>(
          0.5 + 0.5 * sin(time * speed * audioReactivity),
          0.5 + 0.5 * sin(time * speed * audioReactivity + 2.0),
          0.5 + 0.5 * sin(time * speed * audioReactivity + 4.0)
      );

      // Mouse Interaction
      let aspect = resolution.x / resolution.y;
      let dVec = uv - mousePos;
      let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

      // Pulse based on distance
      let pulse = 1.0 - smoothstep(0.0, radius, dist);

      // If mouse is close, intensify and shift color
      let interaction = pulse * glowStr * 2.0;
      neon = mix(neon, vec3<f32>(1.0, 1.0, 1.0), interaction);

      // Calculate emission (HDR capable)
      let falloff = inverseSquareFalloff(dist, radius * 2.0);
      emission = neon * (glowStr + interaction) * edge * 2.0 * (1.0 + falloff);
  }

  // Calculate alpha based on emission intensity
  let glowIntensity = length(emission);
  let finalAlpha = calculateEmissiveAlpha(glowIntensity, occlusionBalance);

  // Output RGBA: RGB = emission (HDR), A = physical occlusion
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));
  
  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
