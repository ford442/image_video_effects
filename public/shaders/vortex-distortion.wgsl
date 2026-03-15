// ═══════════════════════════════════════════════════════════════════════════════
//  Vortex Distortion with Alpha Physics
//  Scientific: Twisting deformation with light scattering
//  
//  ALPHA PHYSICS:
//  - Twist strength creates local distortion gradients
//  - Higher twist = more light path deviation = scattered alpha
//  - Chromatic aberration affects per-channel opacity
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Calculate distortion magnitude from twist parameters
fn calculateDistortionMagnitude(
    percent: f32,           // 0-1 based on distance from center
    twistStrength: f32,     // -10 to 10
    theta: f32              // rotation angle
) -> f32 {
    // Distortion increases with twist strength and is stronger at center
    let twistMag = abs(twistStrength) * 0.1;
    let centerFocus = percent * percent; // Stronger at center
    return twistMag * centerFocus;
}

// Calculate alpha based on physical distortion
// Higher distortion = more light scattering = reduced alpha
fn calculatePhysicalAlpha(
    baseAlpha: f32,
    distortionMag: f32,
    aberration: f32
) -> f32 {
    // Light scattering due to distortion gradient
    let scattering = distortionMag * 0.5;
    
    // Chromatic aberration contributes to alpha separation
    let chromaticScatter = aberration * 10.0 * distortionMag;
    
    // Combined alpha reduction
    return clamp(baseAlpha * (1.0 - scattering) - chromaticScatter * 0.1, 0.4, 1.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  var mousePos = u.zoom_config.yz; // Mouse (0-1)

  // Params
  let twistStrength = (u.zoom_params.x - 0.5) * 20.0; // -10 to 10
  let radius = u.zoom_params.y * 0.8 + 0.1; // 0.1 to 0.9
  let aberration = u.zoom_params.z * 0.05;
  let darkness = u.zoom_params.w;

  // Vector from mouse
  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  var finalColor = vec4<f32>(0.0);
  var distortionMag = 0.0;
  var warpedAlpha = 1.0;

  if (dist < radius) {
      // Calculate twist amount based on distance (stronger at center)
      let percent = (radius - dist) / radius;
      let theta = percent * percent * twistStrength;
      
      // Calculate distortion magnitude for alpha physics
      distortionMag = calculateDistortionMagnitude(percent, twistStrength, theta);
      
      let s = sin(theta);
      let c = cos(theta);

      // Rotate coordinates
      var centered = vec2<f32>(dVec.x * aspect, dVec.y);
      let rotated = vec2<f32>(
          centered.x * c - centered.y * s,
          centered.x * s + centered.y * c
      );
      let uvOffset = vec2<f32>(rotated.x / aspect, rotated.y);
      let twistedUV = mousePos + uvOffset;

      // Chromatic Aberration with per-channel alpha
      if (aberration > 0.001) {
          let rUV = twistedUV + vec2<f32>(aberration * percent, 0.0);
          let gUV = twistedUV;
          let bUV = twistedUV - vec2<f32>(aberration * percent, 0.0);

          let rSample = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
          let gSample = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
          let bSample = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);

          // Per-channel alpha with distortion physics
          let rAlpha = calculatePhysicalAlpha(rSample.a, distortionMag, aberration);
          let gAlpha = calculatePhysicalAlpha(gSample.a, distortionMag, aberration);
          let bAlpha = calculatePhysicalAlpha(bSample.a, distortionMag, aberration);
          
          // Combine channels with their respective alphas
          let avgAlpha = (rAlpha + gAlpha + bAlpha) / 3.0;
          finalColor = vec4<f32>(rSample.r, gSample.g, bSample.b, avgAlpha);
      } else {
          let sample = textureSampleLevel(readTexture, u_sampler, twistedUV, 0.0);
          warpedAlpha = calculatePhysicalAlpha(sample.a, distortionMag, 0.0);
          finalColor = vec4<f32>(sample.rgb, warpedAlpha);
      }

      // Darkness at center (absorption effect)
      let absorption = darkness * percent;
      finalColor = vec4<f32>(finalColor.rgb * (1.0 - absorption), finalColor.a);
      
      // Physical: higher absorption = slightly more opaque
      finalColor.a = min(finalColor.a + absorption * 0.2, 1.0);

  } else {
      finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

  // Depth Pass-through with distortion-based modification
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  // Distorted regions have depth uncertainty
  let depthUncertainty = distortionMag * 0.1;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d * (1.0 + depthUncertainty), 0.0, 0.0, 0.0));
}
