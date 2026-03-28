// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Oil Shader with Alpha Physics
//  Category: liquid-effects
//  Features: oil swirl, interference patterns, wavelength-dependent absorption
//
//  ALPHA PHYSICS:
//  - Oil has higher refractive index than water (n ≈ 1.47)
//  - Higher F0 for stronger Fresnel reflections
//  - Yellowish absorption (wavelength-dependent)
//  - Thicker oil = more opaque
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;

// Noise functions borrowed for swirl effect
fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise2D(p: vec2<f32>) -> vec2<f32> {
  var i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash2(i);
  let b = hash2(i + vec2<f32>(1.0, 0.0));
  let c = hash2(i + vec2<f32>(0.0, 1.0));
  let d = hash2(i + vec2<f32>(1.0, 1.0));
  let h = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
  return vec2<f32>(cos(h * 6.283), sin(h * 6.283));
}

fn flowPattern(p: vec2<f32>, time: f32) -> vec2<f32> {
  var flow = vec2<f32>(0.0);
  var amplitude = 1.0;
  var frequency = 1.0;
  for (var i = 0; i < 3; i++) {
    flow += noise2D(p * frequency + time * 0.1) * amplitude;
    amplitude *= 0.5;
    frequency *= 2.0;
  }
  return flow;
}

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate oil alpha - oil is more reflective and has yellowish tint
fn calculateOilAlpha(
    oilThickness: f32,
    viewDotNormal: f32,
    interference: f32
) -> f32 {
  // Oil has higher refractive index than water
  // F0 ≈ ((n1-n2)/(n1+n2))² with n_oil ≈ 1.47, n_air ≈ 1.0
  // F0 ≈ 0.036, but we use slightly higher for visual effect
  let F0 = 0.05;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);
  
  // Oil absorption: thicker = more opaque, yellowish
  // Oil absorbs blue more than red/yellow
  let absorption = exp(-oilThickness * 1.2);
  
  // Interference affects transparency (constructive = more opaque)
  let interferenceAlpha = mix(0.6, 0.9, absorption);
  
  // Fresnel reflection reduces transmission
  let alpha = interferenceAlpha * (1.0 - fresnel * 0.35);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate oil color with wavelength-dependent absorption
fn calculateOilColor(
    baseColor: vec3<f32>,
    oilThickness: f32,
    interference: vec3<f32>,
    displacementMag: f32
) -> vec3<f32> {
  // Oil absorbs blue light more strongly than red/yellow
  // This gives oil its characteristic yellowish/golden appearance
  let absorptionR = exp(-oilThickness * 0.5);
  let absorptionG = exp(-oilThickness * 0.8);
  let absorptionB = exp(-oilThickness * 1.3);
  
  // Apply wavelength-dependent absorption
  let absorbed = vec3<f32>(
      baseColor.r * absorptionR,
      baseColor.g * absorptionG,
      baseColor.b * absorptionB
  );
  
  // Add interference colors (oil slick rainbow effect)
  let oilTint = mix(absorbed, interference, 0.15);
  
  // Add golden sheen based on displacement
  let goldenSheen = vec3<f32>(0.3, 0.25, 0.1) * displacementMag * 2.0;
  
  return oilTint + goldenSheen;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;

  // --- Oil Swirl Logic ---
  // Continuous slow movement
  let time = currentTime * 0.05;
  let noiseuv = uv * 3.0;
  var flow = flowPattern(noiseuv, time);
  let ambientDisplacement = flow * 0.01;

  // --- Mouse Ripples ---
  var mouseDisplacement = vec2<f32>(0.0, 0.0);
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;
    if (timeSinceClick > 0.0 && timeSinceClick < 3.0) {
      let direction_vec = uv - rippleData.xy;
      let dist = length(direction_vec);
      if (dist > 0.0001) {
        // Stir the oil
        let stir_speed = 1.5;
        // Vortex-like stir
        let stir = vec2<f32>(-direction_vec.y, direction_vec.x); // Tangent
        let wave = sin(dist * 10.0 - timeSinceClick * stir_speed);
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / 3.0);
        mouseDisplacement += stir * wave * 0.02 * attenuation;
      }
    }
  }

  let totalDisplacement = ambientDisplacement + mouseDisplacement;
  let displacedUV = uv + totalDisplacement;

  // Sample color
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // Add interference pattern (oil slick colors)
  // Based on noise/displacement magnitude
  let slick = length(totalDisplacement) * 10.0;
  let interference = 0.5 + 0.5 * cos(slick + vec3<f32>(0.0, 2.0, 4.0)); // Rainbow bands

  // ═══════════════════════════════════════════════════════════════════════════════
  // ALPHA CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════════
  
  // Oil thickness from displacement magnitude
  let displacementMag = length(totalDisplacement);
  let oilThickness = displacementMag * 8.0 + 0.15;
  
  // Approximate normal from displacement gradient
  let normal = normalize(vec3<f32>(
      -totalDisplacement.x * 20.0,
      -totalDisplacement.y * 20.0,
      1.0
  ));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = dot(viewDir, normal);
  
  // Calculate oil color with wavelength-dependent absorption
  let oilColor = calculateOilColor(baseColor, oilThickness, interference, displacementMag);
  
  // Calculate alpha
  let avgInterference = (interference.r + interference.g + interference.b) / 3.0;
  let alpha = calculateOilAlpha(oilThickness, viewDotNormal, avgInterference);

  // Store with alpha
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(oilColor, alpha));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
