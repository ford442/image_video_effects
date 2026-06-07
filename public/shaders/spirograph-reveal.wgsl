// ═══════════════════════════════════════════════════════════════════
//  Spirograph Reveal v2
//  Category: artistic
//  Features: audio-reactive, mouse-driven, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-30
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let aspect = resolution.x / resolution.y;
  let center = mouse;
  let p = (uv - center) * vec2<f32>(aspect, 1.0);
  let r = length(p);
  let a = atan2(p.y, p.x);

  // Gear parameters modulated by mouse and params
  let outerTeeth = 3.0 + floor(u.zoom_params.x * 12.0);
  let innerTeeth = 1.0 + floor(u.zoom_params.y * 8.0);
  let speed = u.zoom_params.z * 2.0 * (1.0 + bass * 0.3);
  let thickness = 0.02 + u.zoom_params.w * 0.08;

  // Depth creates 3D spirograph depth layers
  let depthLayers = 1.0 + depth * 2.0;

  var totalDensity = 0.0;
  var totalBloom = 0.0;

  // Multiple rotating gears with epicycloid/hypocycloid math
  for (var gear: u32 = 0u; gear < 3u; gear = gear + 1u) {
    let g = f32(gear);
    let gearRatio = (outerTeeth + g) / (innerTeeth + g * 0.5);
    let gearSpeed = speed * (1.0 + g * 0.3) * (1.0 + bass * 0.4);
    let t = time * gearSpeed + g * 2.094;

    // Epicycloid when ratio > 0, hypocycloid variation
    let k = gearRatio;
    let theta = a * (k + 1.0) + t;
    let rho = r * 10.0 * depthLayers;

    // True spirograph: R * ( (1-k)*cos(t) + l*k*cos((1-k)/k*t) )
    let l = 0.5 + mouse.x * 0.5;
    let spiro = sin(theta) + l * sin((1.0 - k) * theta / max(k, 0.1));
    let cusp = cos(rho - spiro * 3.0);

    let wave = sin(rho * 0.5 + spiro * 5.0 + cusp * 2.0);
    let val = abs(wave);
    let lineField = smoothstep(0.0, thickness * (1.0 + g * 0.3), val);
    let density = 1.0 - lineField;

    // Specular highlight at cusps
    let cuspSharp = pow(1.0 - smoothstep(0.0, 0.15, val), 3.0);
    totalBloom = totalBloom + cuspSharp * (0.5 + depth * 0.5);
    totalDensity = totalDensity + density * (0.6 - g * 0.15);
  }

  totalDensity = clamp(totalDensity, 0.0, 1.0);
  totalBloom = clamp(totalBloom, 0.0, 1.0);

  let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let gray = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // Metallic ink aesthetic
  let inkColor = vec3<f32>(0.85, 0.82, 0.78) * (0.4 + 0.6 * gray);
  let specColor = vec3<f32>(1.0, 0.95, 0.85) * totalBloom * 2.0;
  let gradientFill = mix(
    vec3<f32>(0.2, 0.05, 0.4),
    vec3<f32>(0.05, 0.3, 0.5),
    fract(r * 2.0 + time * 0.1)
  );

  // Combine metallic ink with gradient fill along curve length
  var outColor = mix(inkColor, gradientFill, totalDensity * 0.4);
  outColor = outColor + specColor;

  // Depth fade
  let fade = smoothstep(1.2, 0.2, r);
  let finalMask = totalDensity * fade;

  // Reveal image through spirograph mask
  outColor = mix(outColor, color.rgb, finalMask * 0.5);

  // HDR bloom at cusps added on top
  outColor = outColor + specColor * 0.5;

  // Alpha: curve density × depth_occlusion
  let depthOcclusion = 1.0 - depth * 0.5;
  let alpha = clamp(totalDensity * depthOcclusion * fade + totalBloom * 0.3, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(outColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(outColor, alpha));
}
