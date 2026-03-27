// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Mirror Shader with Alpha Physics
//  Category: liquid-effects
//  Features: liquid distortion, mirror reflection, metallic surface
//
//  ALPHA PHYSICS:
//  - Mirror surface has high Fresnel reflection
//  - Liquid waves create varying thickness
//  - Metallic tint affects perceived transparency
// ═══════════════════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate liquid mirror alpha
fn calculateMirrorAlpha(
    waveHeight: f32,
    reflectionStrength: f32,
    viewDotNormal: f32
) -> f32 {
  // Liquid mirror has high base F0 for metallic look
  let baseF0 = mix(0.04, 0.6, reflectionStrength);
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), baseF0);
  
  // Wave height creates varying liquid film thickness
  let filmThickness = abs(waveHeight) * 3.0 + 0.1;
  
  // Thicker liquid = more opaque
  let absorption = exp(-filmThickness * 1.5);
  let baseAlpha = mix(0.5, 0.9, absorption);
  
  // Higher reflection = less transmission
  let reflectionFactor = 1.0 - reflectionStrength * 0.4;
  
  let alpha = baseAlpha * reflectionFactor * (1.0 - fresnel * 0.35);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate liquid mirror color with metallic properties
fn calculateMirrorColor(
    baseColor: vec3<f32>,
    luma: f32,
    reflectionStrength: f32,
    waveHeight: f32
) -> vec3<f32> {
  // Metallic effect: boost contrast and add a silver tint
  let metallic = vec3<f32>(luma * 1.2, luma * 1.25, luma * 1.3); // Slight blue tint
  
  // Mix based on reflection strength
  let mirrorMix = mix(baseColor, metallic, reflectionStrength);
  
  // Wave height adds subtle color variation
  let waveTint = vec3<f32>(0.0, 0.03, 0.05) * waveHeight;
  
  return mirrorMix + waveTint;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  var mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  // Params
  let distortion_amt = u.zoom_params.x * 0.2;
  let smoothness = u.zoom_params.y; // Unused but reserved for future noise scale
  let reflection_strength = u.zoom_params.z;
  let push_size = u.zoom_params.w * 0.5;

  // Liquid distortion from mouse
  let dist = distance(uv_corrected, mouse_corrected);
  var displacement = vec2<f32>(0.0);
  var waveHeight: f32 = 0.0;

  if (dist < push_size && dist > 0.001) {
    let push = (1.0 - dist / push_size);
    var dir = normalize(uv_corrected - mouse_corrected);
    displacement = dir * push * distortion_amt * sin(dist * 20.0 - time * 5.0);
    waveHeight = sin(dist * 20.0 - time * 5.0) * push;
  }

  // Base liquid noise (simplified sine waves for fluid feel)
  let noise_uv = uv * 3.0;
  let liquid_wave = vec2<f32>(
    sin(noise_uv.y * 5.0 + time) * 0.01,
    cos(noise_uv.x * 5.0 + time) * 0.01
  );

  let final_uv = uv + displacement + liquid_wave;

  // Sample texture with reflection feel (mirroring edges)
  let mirrored_uv = vec2<f32>(
      abs(fract(final_uv.x * 0.5) * 2.0 - 1.0), // Simple wrap mirroring
      abs(fract(final_uv.y * 0.5) * 2.0 - 1.0)
  );

  // Check if we want standard mirroring or just clamping
  // For a liquid mirror, let's just clamp/wrap cleanly or use the sampler's mode.
  // We'll trust the sampler (usually repeat or clamp) but adding a metallic tint.

  var baseColor = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0).rgb;

  // ═══════════════════════════════════════════════════════════════════════════════
  // ALPHA CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════════
  
  // Calculate normal from displacement
  let normal = normalize(vec3<f32>(
      -displacement.x * 10.0,
      -displacement.y * 10.0,
      1.0
  ));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = dot(viewDir, normal);
  
  // Metallic effect: boost contrast and add a silver tint
  let luma = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));
  
  // Calculate mirror color
  let mirrorColor = calculateMirrorColor(baseColor, luma, reflection_strength, waveHeight);
  
  // Calculate alpha
  let alpha = calculateMirrorAlpha(waveHeight, reflection_strength, viewDotNormal);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(mirrorColor, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
