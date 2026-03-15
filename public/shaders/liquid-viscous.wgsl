// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Viscous Shader with Alpha Physics
//  Category: liquid-effects
//  Features: vortex physics, chromatic aberration, cohesion effects
//
//  ALPHA PHYSICS:
//  - Viscous liquid = more scattering = more opaque
//  - Vortex strength affects thickness
//  - Chromatic dispersion affects per-channel opacity
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

// Hash function for per-vortex variation based on click position
fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Multi-octave noise-like function for ambient flow
fn noise2D(p: vec2<f32>) -> vec2<f32> {
  var i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f); // smoothstep

  var a = hash2(i);
  var b = hash2(i + vec2<f32>(1.0, 0.0));
  let c = hash2(i + vec2<f32>(0.0, 1.0));
  let d = hash2(i + vec2<f32>(1.0, 1.0));

  let h = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);

  // Return derivative-like vector for flow direction
  return vec2<f32>(
    cos(h * 6.283185),
    sin(h * 6.283185)
  );
}

// Multi-octave flow pattern
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

fn hash2_to_vec2(h: f32) -> vec2<f32> {
  var a = fract(h * 0.1031);
  var b = fract(h * 0.11369);
  return vec2<f32>(a, b) * 2.0 - 1.0;
}

fn viscous_noise(p: vec2<f32>, time: f32) -> vec2<f32> {
  var uv = p * vec2<f32>(0.1, 0.1) + time * 0.1;
  let noiseValue = sin(uv.x * 3.14159) * cos(uv.y * 3.14159);
  var flow = hash2_to_vec2(fract(noiseValue * 43758.5453));
  return flow * exp(-length(p) * 0.5);
}

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate viscous liquid alpha
fn calculateViscousAlpha(
    vortexStrength: f32,
    chromaticMag: f32,
    viewDotNormal: f32,
    depthFactor: f32
) -> f32 {
  // Viscous liquid has higher base F0 due to density
  let F0 = 0.04;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);
  
  // Viscous = more scattering = more opaque
  let viscosityFactor = 1.0 + vortexStrength * 0.5;
  
  // Chromatic dispersion affects effective thickness
  let chromaticThickness = chromaticMag * 2.0 + 0.2;
  
  // Depth factor: more viscous in foreground
  let depthOpacity = mix(0.95, 0.5, depthFactor);
  
  // Absorption with viscosity
  let absorption = exp(-chromaticThickness * viscosityFactor);
  let baseAlpha = mix(0.4, depthOpacity, absorption);
  
  let alpha = baseAlpha * (1.0 - fresnel * 0.3);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate viscous color with cohesion effects
fn calculateViscousColor(
    r: f32,
    g: f32,
    b: f32,
    vortexStrength: f32,
    chromaticOffset: f32
) -> vec3<f32> {
  // Viscous liquid slightly desaturates colors (scattering)
  let avg = (r + g + b) / 3.0;
  let saturation = 1.0 - vortexStrength * 0.1;
  
  let desaturated = vec3<f32>(
      mix(avg, r, saturation),
      mix(avg, g, saturation),
      mix(avg, b, saturation)
  );
  
  // Add viscous "glow" at vortex centers
  let glow = vec3<f32>(0.02, 0.03, 0.04) * vortexStrength;
  
  return desaturated + glow;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  let pixelSize = 1.0 / resolution;
  let center_depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = 1.0 - center_depth;

  // Ambient displacement and gravity bias
  var ambientDisplacement = vec2<f32>(0.0);
  let background_factor = smoothstep(0.0, 0.25, depthFactor);
  if (background_factor > 0.0) {
    let time = currentTime * 0.2 + depthFactor * 2.0;
    let noiseuv = uv * vec2<f32>(9.0, 7.0) + vec2<f32>(currentTime * 0.05, currentTime * 0.04);
    var flow = flowPattern(noiseuv, time);
    let gravity = vec2<f32>(0.0, 0.0006);
    ambientDisplacement = (flow * 0.003 + gravity) * background_factor * (0.2 + depthFactor);
  }

  // Vortex calculation
  var mouseDisplacement = vec2<f32>(0.0);
  var chromaticAccumulator = 0.0;
  var totalVortexStrength: f32 = 0.0;
  let rippleCount = u32(u.config.y);

  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;

    if (timeSinceClick <= 0.0) {
      continue;
    }
    let vortexSeed = hash2(rippleData.xy * 100.0);
    let vortexDuration = mix(3.0, 6.0, vortexSeed);
    let chromaticStrength = mix(0.001, 0.005, hash2(rippleData.xy * 200.0));

    if (timeSinceClick < vortexDuration) {
      let direction_vec = uv - rippleData.xy;
      let dist = length(direction_vec);

      if (dist > 0.0001) {
        let rippleOriginDepthFactor = 1.0 - textureSampleLevel(readDepthTexture, non_filtering_sampler, rippleData.xy, 0.0).r;

        // Vortex calculation: tangential velocity (perpendicular to radius)
        let tangent = vec2<f32>(-direction_vec.y, direction_vec.x); // Perpendicular vector

        // Angular velocity with quadratic decay (fast initial spin)
        let normalizedTime = timeSinceClick / vortexDuration;
        let angularVelocity = (1.0 - normalizedTime * normalizedTime) * 8.0; // Quadratic decay

        // Vortex strength modulated by depth
        let vortex_amplitude = mix(0.008, 0.022, rippleOriginDepthFactor);

        // Tighter falloff (60% radius reduction: 20.0 -> 33.0)
        let falloff = 1.0 / (dist * 33.0 + 1.0);

        // Time-based attenuation
        let attenuation = 1.0 - smoothstep(0.0, 1.0, normalizedTime);

        // Add spiral component (inward/outward motion based on time)
        let spiralFactor = sin(normalizedTime * 3.14159) * 0.3;
        let radialComponent = (direction_vec / dist) * spiralFactor;

        // Combine tangential and radial motion
        let vortexDisplacement = (tangent * angularVelocity + radialComponent) * vortex_amplitude * falloff * attenuation;

        mouseDisplacement += vortexDisplacement;
        chromaticAccumulator += chromaticStrength * length(vortexDisplacement) * 100.0;
        totalVortexStrength += length(vortexDisplacement) * 100.0;
      }
    }
  }

  // 4 tap smoothing
  let smoothedDisplacement = mouseDisplacement * 0.7; // 70% original

  // Sample 4 cardinal neighbors
  let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0);
  let left = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-pixelSize.x, 0.0), 0.0);
  let up = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -pixelSize.y), 0.0);
  let down = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0);

  // Average neighbor effect for cohesion
  let neighborAvg = (right + left + up + down) * 0.25;
  let centerColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let cohesionEffect = (neighborAvg - centerColor) * 0.3; // 30% smoothing

  // Apply smoothing to displacement
  let finalMouseDisplacement = smoothedDisplacement + cohesionEffect.xy * 0.01;

  // --- Chromatic Aberration ---
  let totalDisplacement = finalMouseDisplacement + ambientDisplacement;
  let displacementMagnitude = length(totalDisplacement);
  let chromaticOffset = chromaticAccumulator * (1.0 - center_depth) * 0.5;

  // Sample each color channel at slightly different offsets
  let redUV = uv + totalDisplacement * (1.0 + chromaticOffset);
  let greenUV = uv + totalDisplacement;
  let blueUV = uv + totalDisplacement * (1.0 - chromaticOffset);

  let redChannel = textureSampleLevel(readTexture, u_sampler, redUV, 0.0).r;
  let greenChannel = textureSampleLevel(readTexture, u_sampler, greenUV, 0.0).g;
  let blueChannel = textureSampleLevel(readTexture, u_sampler, blueUV, 0.0).b;

  // ═══════════════════════════════════════════════════════════════════════════════
  // ALPHA CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════════
  
  // Approximate normal from displacement
  let normal = normalize(vec3<f32>(
      -totalDisplacement.x * 20.0,
      -totalDisplacement.y * 20.0,
      1.0
  ));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = dot(viewDir, normal);
  
  // Calculate viscous color
  let viscousColor = calculateViscousColor(redChannel, greenChannel, blueChannel, totalVortexStrength, chromaticOffset);
  
  // Calculate alpha
  let alpha = calculateViscousAlpha(totalVortexStrength, chromaticOffset, viewDotNormal, center_depth);

  // --- Final Output ---
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(viscousColor, alpha));

  // Update depth texture for next frame
  let depthDisplacedUV = uv + finalMouseDisplacement;
  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, depthDisplacedUV, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(displacedDepth, 0.0, 0.0, 0.0));
}
