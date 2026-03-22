// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Swirl Shader with Alpha Physics
//  Category: liquid-effects
//  Features: vortex rotation, smooth blending, transparent vortex
//
//  ALPHA PHYSICS:
//  - Vortex center = thicker liquid = more opaque
//  - Edge falloff with Fresnel
//  - Rotation speed affects transparency
// ═══════════════════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=SwirlStrength, y=Radius, z=Smoothness, w=AutoRotation
  ripples: array<vec4<f32>, 50>,
};

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate vortex alpha
fn calculateVortexAlpha(
    distRatio: f32,
    rotationStrength: f32,
    viewDotNormal: f32
) -> f32 {
  // Fresnel at edges
  let F0 = 0.03;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);
  
  // Center of vortex = thicker liquid
  // Edge = thinner, more transparent
  let centerThickness = 1.0 - distRatio;
  let thicknessAlpha = mix(0.4, 0.85, centerThickness);
  
  // Fast rotation = more turbulent = slightly more opaque
  let rotationAlpha = mix(1.0, 1.1, abs(rotationStrength) * 0.1);
  
  let alpha = thicknessAlpha * rotationAlpha * (1.0 - fresnel * 0.3);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate vortex color with motion blur
fn calculateVortexColor(
    baseColor: vec3<f32>,
    distRatio: f32,
    rotationStrength: f32
) -> vec3<f32> {
  // Add motion tint at edges
  let motionTint = vec3<f32>(0.0, 0.05, 0.1) * abs(rotationStrength) * distRatio;
  
  // Slight darkening in vortex center
  let centerDarken = mix(1.0, 0.95, 1.0 - distRatio);
  
  return baseColor * centerDarken + motionTint;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;

  var mousePos = u.zoom_config.yz;
  let time = u.config.x;
  // ═══ AUDIO REACTIVITY ═══
  let audioOverall = u.zoom_config.x;
  let audioBass = audioOverall * 1.5;
  let audioReactivity = 1.0 + audioOverall * 0.3;

  let strength = (u.zoom_params.x - 0.5) * 10.0; // -5 to 5
  let radius = u.zoom_params.y * 0.8 + 0.01;
  let smoothness = u.zoom_params.z;
  let autoRot = (u.zoom_params.w - 0.5) * 4.0;

  // Calculate distance to center (mouse)
  let aspect = resolution.x / resolution.y;
  var center = mousePos;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let center_corrected = vec2<f32>(center.x * aspect, center.y);
  let dist = distance(uv_corrected, center_corrected);

  // Initialize output variables
  var finalColor: vec3<f32>;
  var finalUV: vec2<f32>;
  var distRatio: f32 = 0.0;
  var rotationStrength: f32 = 0.0;

  // Twist calculation
  if (dist < radius) {
      distRatio = dist / radius;
      let percent = (radius - dist) / radius;
      rotationStrength = percent * percent * (strength + autoRot * time);
      let s = sin(rotationStrength);
      let c = cos(rotationStrength);

      let d = uv - center;
      // Correct aspect for rotation to keep it circular
      d.x = d.x * aspect;

      let new_d = vec2<f32>(
          d.x * c - d.y * s,
          d.x * s + d.y * c
      );

      // Uncorrect aspect
      new_d.x = new_d.x / aspect;

      finalUV = center + new_d;

      // Smooth mixing at edges to prevent harsh lines
      // Actually standard swirl naturally falls off if percent goes to 0 at radius

      // Bounds check
      finalUV = clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0));

      var baseColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).rgb;
      
      // ═══════════════════════════════════════════════════════════════════════════════
      // ALPHA CALCULATION for vortex
      // ═══════════════════════════════════════════════════════════════════════════════
      
      // Approximate normal from rotation
      let normal = normalize(vec3<f32>(
          -rotationStrength * d.x * 0.5,
          -rotationStrength * d.y * 0.5,
          1.0
      ));
      let viewDir = vec3<f32>(0.0, 0.0, 1.0);
      let viewDotNormal = dot(viewDir, normal);
      
      // Calculate color with motion effects
      finalColor = calculateVortexColor(baseColor, percent, strength);
      
      // Calculate alpha
      let alpha = calculateVortexAlpha(percent, strength, viewDotNormal);
      
      textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  } else {
      var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
      // Outside vortex: minimal distortion, high transparency
      textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color.rgb, color.a * 0.9));
  }
}
