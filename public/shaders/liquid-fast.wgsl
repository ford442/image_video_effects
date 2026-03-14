// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Fast Shader with Alpha Physics
//  Category: liquid-effects
//  Features: fast ripples, depth-aware, optimized performance
//
//  ALPHA PHYSICS:
//  - Fast movement = motion blur affecting alpha
//  - Ripple amplitude affects thickness
//  - Depth-based opacity falloff
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};

@group(0) @binding(3) var<uniform> u: Uniforms;

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate fast liquid alpha
fn calculateFastAlpha(
    rippleMag: f32,
    depthFactor: f32,
    motionBlur: f32
) -> f32 {
  // Fresnel
  let F0 = 0.02;
  // Approximate normal from ripple
  let normal = normalize(vec3<f32>(rippleMag * 2.0, rippleMag * 2.0, 1.0));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let fresnel = schlickFresnel(max(0.0, dot(viewDir, normal)), F0);
  
  // Ripple amplitude = liquid thickness
  let thickness = rippleMag * 4.0 + 0.1;
  
  // Motion blur reduces effective opacity
  let blurFactor = exp(-motionBlur * 0.5);
  
  // Depth factor: background = more transparent
  let depthAlpha = mix(0.9, 0.4, depthFactor);
  
  // Absorption
  let absorption = exp(-thickness * 1.5);
  let baseAlpha = mix(0.35, depthAlpha, absorption);
  
  let alpha = baseAlpha * blurFactor * (1.0 - fresnel * 0.3);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate fast liquid color with motion blur
fn calculateFastColor(
    baseColor: vec3<f32>,
    rippleMag: f32,
    depthFactor: f32
) -> vec3<f32> {
  // Fast liquid has slight motion blur effect
  let blur = exp(-rippleMag * 3.0);
  
  // Depth-based tint
  let depthTint = vec3<f32>(0.0, 0.05, 0.1) * (1.0 - depthFactor);
  
  return baseColor * blur + depthTint * rippleMag;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  let center_depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // --- Ambient Displacement (Background Only) ---
  var ambientDisplacement = vec2<f32>(0.0, 0.0);
  let background_factor = 1.0 - smoothstep(0.0, 0.1, center_depth);

  if (background_factor > 0.0) {
    let time = currentTime * 0.5;
    let base_ambient_strength = 0.004;
    let ambient_freq = 15.0;
    let motion = vec2<f32>(sin(uv.y * ambient_freq + time * 1.2), cos(uv.x * ambient_freq + time));
    ambientDisplacement = motion * base_ambient_strength * background_factor;
  }

  // --- Mouse-driven Ripples (FAST VARIATION) ---
  var mouseDisplacement = vec2<f32>(0.0, 0.0);
  var totalRippleMag: f32 = 0.0;
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = u.config.x - rippleData.z;

    // Shorter lifetime (1.5s instead of 3.0s)
    if (timeSinceClick > 0.0 && timeSinceClick < 1.5) {
      let direction_vec = uv - rippleData.xy;
      let dist = length(direction_vec);
      if (dist > 0.0001) {
        let rippleOriginDepthFactor = 1.0 - textureSampleLevel(readDepthTexture, non_filtering_sampler, rippleData.xy, 0.0).r;

        // Faster speed (3x base)
        let ripple_speed = mix(3.0, 5.0, rippleOriginDepthFactor);
        let ripple_amplitude = mix(0.005, 0.015, rippleOriginDepthFactor);

        // Higher frequency waves
        let wave = sin(dist * 40.0 - timeSinceClick * ripple_speed * 10.0);

        // Faster decay
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / (1.5 * mix(0.5, 1.0, rippleOriginDepthFactor)));
        let falloff = 1.0 / (dist * 20.0 + 1.0);
        let rippleContrib = (direction_vec / dist) * wave * ripple_amplitude * falloff * attenuation;
        mouseDisplacement += rippleContrib;
        
        // Track total ripple magnitude for alpha
        totalRippleMag += length(rippleContrib) * 10.0;
      }
    }
  }

  // --- Final Output ---
  let totalDisplacement = mouseDisplacement + ambientDisplacement;
  let colorDisplacedUV = uv + totalDisplacement;
  let baseColor = textureSampleLevel(readTexture, u_sampler, colorDisplacedUV, 0.0).rgb;
  
  // ═══════════════════════════════════════════════════════════════════════════════
  // ALPHA CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════════
  
  // Motion blur approximation from displacement
  let motionBlur = length(totalDisplacement) * 50.0;
  
  // Calculate color with motion effects
  let fastColor = calculateFastColor(baseColor, totalRippleMag, center_depth);
  
  // Calculate alpha
  let alpha = calculateFastAlpha(totalRippleMag, center_depth, motionBlur);
  
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(fastColor, alpha));

  // Update depth texture for next frame
  let depthDisplacedUV = uv + mouseDisplacement;
  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, depthDisplacedUV, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(displacedDepth, 0.0, 0.0, 0.0));
}
