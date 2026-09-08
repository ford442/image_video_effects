// ═══════════════════════════════════════════════════════════════════
//  Interactive RGB Split
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-08
//  Ideas: wavelength-scaled R/G/B split along the existing offset; lateral vs longitudinal mix
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Mouse-localized chromatic split. Mode < 0.5 is radial (longitudinal);
//  mode >= 0.5 is directional (lateral). Ripples perturb the field.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=Falloff, z=Mode, w=AngleOffset
  ripples: array<vec4<f32>, 50>,
};

fn tentAlpha(x: f32) -> f32 {
  return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (lambda < 440.0) { r = (440.0 - lambda) / 60.0; b = 1.0; }
  else if (lambda < 490.0) { g = (lambda - 440.0) / 50.0; b = 1.0; }
  else if (lambda < 510.0) { g = 1.0; b = (510.0 - lambda) / 20.0; }
  else if (lambda < 580.0) { r = (lambda - 510.0) / 70.0; g = 1.0; }
  else if (lambda < 645.0) { r = 1.0; g = (645.0 - lambda) / 65.0; }
  else { r = 1.0; }
  var intensity = 1.0;
  if (lambda < 420.0) { intensity = 0.3 + 0.7 * (lambda - 380.0) / 40.0; }
  else if (lambda > 700.0) { intensity = 0.3 + 0.7 * (780.0 - lambda) / 80.0; }
  return clamp(vec3(r, g, b) * intensity, vec3(0.0), vec3(1.0));
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn gaussianMask(dist: f32, sigma: f32) -> f32 {
  return exp(-dist * dist / (2.0 * sigma * sigma));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(1.0, 1.0));

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  var mouse = u.zoom_config.yz;
  if (mouse.x < 0.0) { mouse = vec2<f32>(0.5, 0.5); }

  let strength = u.zoom_params.x * 0.05 * (1.0 + bass * 0.3);
  let falloff = clamp(u.zoom_params.y, 0.0, 1.0);
  let mode = clamp(u.zoom_params.z, 0.0, 1.0);
  let angleOffset = u.zoom_params.w;

  let aspect = resolution.x / max(resolution.y, 1.0);
  let uv_aspect = uv * vec2<f32>(aspect, 1.0);
  let mouse_aspect = mouse * vec2<f32>(aspect, 1.0);

  let dist = distance(uv_aspect, mouse_aspect);
  let delta = uv_aspect - mouse_aspect;
  let deltaLen = max(length(delta), 0.001);
  let dir = delta / deltaLen;

  // Calculate aberration amount with smoothstep falloff curve
  var amount = strength;
  if (falloff > 0.001) {
    amount *= smoothstep(0.8, 0.0, dist * falloff * 2.0);
  }

  // Compute SINGLE smooth displacement field
  var smoothOffset = vec2<f32>(0.0);
  if (mode < 0.5) {
    smoothOffset = (uv - mouse) * amount;
  } else {
    let angle = angleOffset * 6.2831;
    let s = sin(angle);
    let c = cos(angle);
    let splitDir = vec2<f32>(c, s);
    smoothOffset = splitDir * amount;
  }

  // Ripple waves perturb the single displacement field
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleOffset = vec2<f32>(0.0);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.5) {
      let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin(rDist * 30.0 - elapsed * 10.0) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let rDir = select(vec2<f32>(0.0), normalize((uv - ripple.xy) * vec2<f32>(aspect, 1.0)), rDist > 0.001);
      rippleOffset = rippleOffset + rDir * wave * 0.02;
    }
  }

  // Apply time-based micro-jitter for living glass feel
  let jitter = vec2<f32>(sin(time * 2.0 + uv.y * 10.0), cos(time * 1.7 + uv.x * 10.0)) * amount * 0.05;
  let field = smoothOffset + rippleOffset + jitter;
  // Wavelength-scaled split along the existing field. Radial mode stays
  // longitudinal (along the offset); directional mode is already lateral.
  let longW = select(1.0, 0.55, mode >= 0.5);
  let latDir = vec2<f32>(-field.y, field.x);
  let latLen = max(length(latDir), 0.0001);
  let lateral = (latDir / latLen) * length(field) * (1.0 - longW);
  let splitAxis = field * longW + lateral;
  let uvR = clamp(uv + splitAxis * 1.15, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(uv + splitAxis * 0.70, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv + splitAxis * 1.35, vec2<f32>(0.0), vec2<f32>(1.0));
  let splitColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
  );
  let displacedUV = clamp(uv + field, vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;
  let splitMix = clamp(length(field) * 8.0, 0.0, 1.0);
  let sampled = mix(baseColor, splitColor, splitMix);

  let displacementMagnitude = length(smoothOffset + rippleOffset);
  let luma = dot(sampled, vec3<f32>(0.299, 0.587, 0.114));
  let falloffAlpha = tentAlpha(displacementMagnitude * 4.0);
  let alpha = clamp(displacementMagnitude * 5.0 + luma * 0.4 + falloffAlpha * 0.3, 0.0, 1.0);

  let wavelength = mix(380.0, 780.0, angleOffset + displacementMagnitude * 2.0);
  let spectralTint = wavelengthToRGB(wavelength);
  let tintStrength = displacementMagnitude * 2.0;
  let color = mix(sampled, sampled * spectralTint, alpha * tintStrength);

  // Depth-aware compositing: blend with original based on depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthBlend = mix(1.0, 0.6, depth * 0.8);
  let fresnelEdge = schlickFresnel(clamp(dist * 2.0, 0.0, 1.0), 0.02);
  let finalColor = mix(baseColor, color, depthBlend * (1.0 + fresnelEdge * 0.3));
  let finalAlpha = alpha * mix(0.7, 1.0, depth);

  // Vignette darkening at screen edges for dramatic focus
  let vignette = 1.0 - smoothstep(0.4, 1.2, length(uv - vec2<f32>(0.5)) * 1.2);
  let vignettedColor = acesToneMap(finalColor * mix(0.85, 1.0, vignette));
  let pixel = vec2<i32>(global_id.xy);
  let outColor = vec4<f32>(vignettedColor, finalAlpha);
  textureStore(writeTexture, pixel, outColor);
  textureStore(dataTextureA, pixel, outColor);

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(d, 0.0, 0.0, 0.0));
}
