// ═══════════════════════════════════════════════════════════════════
//  RGB Ripple Distortion
//  Category: image
//  Features: upgraded-rgba, depth-aware, audio-reactive
//  Complexity: High
//  Scientific: Photoelastic birefringence from principal-stress eigenmodes with Maxwell stress modulation, isochromatic fringe orders, and polarized-light isoclinics
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn clampUV(uv: vec2<f32>) -> vec2<f32> {
  return clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let len2 = dot(v, v);
  if (len2 < 1e-8) {
    return vec2<f32>(0.0, 0.0);
  }
  return v * inverseSqrt(len2);
}

fn fieldAt(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(dataTextureC, u_sampler, clampUV(uv), 0.0);
}

fn fringePalette(order: f32) -> vec3<f32> {
  let p = fract(order);
  let c0 = vec3<f32>(1.0, 0.10, 0.75);
  let c1 = vec3<f32>(1.0, 0.52, 0.12);
  let c2 = vec3<f32>(0.98, 0.94, 0.22);
  let c3 = vec3<f32>(0.20, 0.92, 0.34);
  let c4 = vec3<f32>(0.14, 0.86, 1.0);
  let c5 = vec3<f32>(0.18, 0.28, 1.0);

  if (p < 0.2) {
    return mix(c0, c1, p / 0.2);
  }
  if (p < 0.4) {
    return mix(c1, c2, (p - 0.2) / 0.2);
  }
  if (p < 0.6) {
    return mix(c2, c3, (p - 0.4) / 0.2);
  }
  if (p < 0.8) {
    return mix(c3, c4, (p - 0.6) / 0.2);
  }
  return mix(c4, c5, (p - 0.8) / 0.2);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let texel = 1.0 / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let freq = 10.0 + 55.0 * clamp(u.zoom_params.x, 0.0, 1.0);
  let amp = 0.002 + 0.028 * clamp(u.zoom_params.y, 0.0, 1.0);
  let speed = 1.0 + 8.0 * clamp(u.zoom_params.z, 0.0, 1.0);
  let stressOptic = 0.05 + 0.45 * clamp(u.zoom_params.w, 0.0, 1.0);

  let previous = fieldAt(uv);
  var displacement = previous.rg * 0.94;

  let mouse = u.zoom_config.yz;
  let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);
  let mouseDelta = (uv - mouse) * aspectVec;
  let mouseDist = length(mouseDelta);
  let mouseEnvelope = exp(-mouseDist * 18.0);
  displacement += safeNormalize(mouseDelta) * (-mouseEnvelope * mouseDown * amp * 2.2);
  displacement += safeNormalize(vec2<f32>(-mouseDelta.y, mouseDelta.x)) * mouseEnvelope * mouseDown * amp * 0.9;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 4.5) {
      continue;
    }
    let delta = (uv - ripple.xy) * aspectVec;
    let r = length(delta);
    let phase = r * freq - age * speed * 4.0;
    let envelope = exp(-r * 9.0 - age * 0.9);
    let radial = safeNormalize(delta);
    displacement += radial * sin(phase) * envelope * amp * (1.0 + 1.2 * bass);
  }

  let left = fieldAt(uv - vec2<f32>(texel.x, 0.0)).rg;
  let right = fieldAt(uv + vec2<f32>(texel.x, 0.0)).rg;
  let up = fieldAt(uv - vec2<f32>(0.0, texel.y)).rg;
  let down = fieldAt(uv + vec2<f32>(0.0, texel.y)).rg;

  let dux_dx = (right.x - left.x) / (2.0 * texel.x);
  let dux_dy = (down.x - up.x) / (2.0 * texel.y);
  let duy_dx = (right.y - left.y) / (2.0 * texel.x);
  let duy_dy = (down.y - up.y) / (2.0 * texel.y);

  var sigma_xx = dux_dx + displacement.x * 20.0;
  var sigma_yy = duy_dy - displacement.y * 20.0;
  var sigma_xy = 0.5 * (dux_dy + duy_dx);

  let electricField = vec2<f32>(dux_dx - duy_dy, dux_dy + duy_dx) * (1.0 + 0.5 * treble);
  let e2 = dot(electricField, electricField);
  let epsilon0 = 0.018 + 0.035 * bass;
  sigma_xx += epsilon0 * (electricField.x * electricField.x - 0.5 * e2);
  sigma_yy += epsilon0 * (electricField.y * electricField.y - 0.5 * e2);
  sigma_xy += epsilon0 * (electricField.x * electricField.y);

  let trace = sigma_xx + sigma_yy;
  let diff = sigma_xx - sigma_yy;
  let rad = sqrt(max(diff * diff + 4.0 * sigma_xy * sigma_xy, 0.0));
  let sigma1 = 0.5 * (trace + rad);
  let sigma2 = 0.5 * (trace - rad);
  let principalAngle = 0.5 * atan2(2.0 * sigma_xy, diff + 1e-6);

  let deltaN = stressOptic * (sigma1 - sigma2) * 0.02;
  let thickness = 0.9 + 0.5 * mouseDown + 0.35 * bass;
  let deltaR = 2.0 * PI * thickness * deltaN / 0.650;
  let deltaG = 2.0 * PI * thickness * deltaN / 0.550;
  let deltaB = 2.0 * PI * thickness * deltaN / 0.450;

  let fringeOrder = abs(deltaG) / PI;
  let isoclinic = abs(sin(2.0 * principalAngle));
  let fringeColor = fringePalette(fringeOrder * 0.18 + previous.b * 0.25 + mids * 0.05);
  let spectral = vec3<f32>(sin(0.5 * deltaR) * sin(0.5 * deltaR), sin(0.5 * deltaG) * sin(0.5 * deltaG), sin(0.5 * deltaB) * sin(0.5 * deltaB));
  let photoelastic = fringeColor * spectral * (0.15 + 0.85 * isoclinic);

  let stressMag = clamp(abs(sigma1 - sigma2) * 0.05, 0.0, 1.0);
  let chromaShift = displacement * (0.6 + 0.8 * stressMag + 0.6 * treble);
  let r = textureSampleLevel(readTexture, u_sampler, clampUV(uv + displacement - chromaShift * 0.4), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clampUV(uv + displacement), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clampUV(uv + displacement + chromaShift * 0.4), 0.0).b;
  let base = vec3<f32>(r, g, b);

  let finalColor = clamp(mix(base, base * 0.35 + photoelastic, clamp(0.35 + 0.55 * stressMag + 0.20 * bass, 0.0, 1.0)), vec3<f32>(0.0), vec3<f32>(1.0));
  let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampUV(uv + displacement * 0.2), 0.0).r;
  let alpha = clamp(0.82 + 0.12 * stressMag + 0.06 * isoclinic, 0.0, 1.0);
  let depthProxy = clamp(depthSample * 0.45 + stressMag * 0.45 + clamp(fringeOrder * 0.08, 0.0, 0.3), 0.0, 1.0);

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(displacement, clamp(fringeOrder * 0.1, 0.0, 1.0), stressMag));
  textureStore(dataTextureB, global_id.xy, vec4<f32>(clamp((sigma1 - sigma2) * 0.05 + 0.5, 0.0, 1.0), fract(principalAngle / PI + 0.5), isoclinic, 1.0));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthProxy, 0.0, 0.0, 1.0));
}
