// ═══════════════════════════════════════════════════════════════════
//  Kaleidoscope Tunnel
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09
//  Ideas: log-z rings; wavelength split along the spiral
//  A packing: ACES display RGBA
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

fn rot2(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn kaleidoscope(uv: vec2<f32>, segments: f32) -> vec2<f32> {
  let angle = atan2(uv.y, uv.x);
  let radius = length(uv);
  let segmentAngle = 6.28318 / max(segments, 1.0);
  let mirroredAngle = abs(fract(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
  return vec2<f32>(cos(mirroredAngle), sin(mirroredAngle)) * radius;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn tunnelSample(polar: vec2<f32>, segmentBase: f32, depthLayer: f32) -> vec2<f32> {
  let segments = segmentBase + floor(polar.x * 10.0);
  let kUV = kaleidoscope(vec2<f32>(cos(polar.y), sin(polar.y)) * polar.x, segments);
  let perspective = 1.0 / (depthLayer + 0.1);
  return kUV * perspective * 0.5 + 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 0.001);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let tunnelSpeed = mix(0.2, 2.0, u.zoom_params.x) * (1.0 + bass * 0.35);
  let segmentBase = mix(3.0, 16.0, u.zoom_params.y);
  let spiralTwist = mix(0.0, 3.0, u.zoom_params.z) * (1.0 + mids * 0.25);
  let zoomDepth = mix(0.3, 2.0, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  var centered = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  var polar = vec2<f32>(length(centered), atan2(centered.y, centered.x));

  // Idea 1 — log-z rings: recede with -log(r), not a linear fract
  let tunnelZ = -log(max(polar.x * zoomDepth, 0.001));
  let depthLayer = fract(tunnelZ - time * tunnelSpeed * 0.2);

  polar.y = polar.y + depthLayer * spiralTwist * 6.28318;

  var sampleUV = tunnelSample(polar, segmentBase, depthLayer);

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    let live = step(0.0, elapsed) * (1.0 - step(3.0, elapsed));
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let ring = smoothstep(0.05, 0.0, abs(rDist - elapsed * 0.15)) * exp(-elapsed * 0.5) * live;
    sampleUV = sampleUV + vec2<f32>(sin(elapsed * 5.0 + f32(i)), cos(elapsed * 5.0 + f32(i))) * ring * 0.1;
  }

  let rotAngle = time * tunnelSpeed * 0.1 + mouseDown * 2.0;
  sampleUV = rot2(rotAngle) * (sampleUV - 0.5) + 0.5;

  // Idea 2 — wavelength split along the same spiral (R/B polar.y offset)
  let wave = 0.018 * (1.0 + treble * 0.4);
  var polarR = polar;
  var polarB = polar;
  polarR.y = polarR.y + wave;
  polarB.y = polarB.y - wave;
  let uvR = clamp(tunnelSample(polarR, segmentBase, depthLayer), vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(tunnelSample(polarB, segmentBase, depthLayer), vec2<f32>(0.0), vec2<f32>(1.0));

  var color = vec3<f32>(0.0);
  for (var layer: i32 = 0; layer < 3; layer = layer + 1) {
    let layerOffset = f32(layer) * 0.33;
    let shift = vec2<f32>(layerOffset * 0.1, layerOffset * 0.15);
    let rS = textureSampleLevel(readTexture, u_sampler, fract(uvR + shift), 0.0).r;
    let gS = textureSampleLevel(readTexture, u_sampler, fract(uvG + shift), 0.0).g;
    let bS = textureSampleLevel(readTexture, u_sampler, fract(uvB + shift), 0.0).b;
    let layerWeight = 1.0 / (1.0 + f32(layer));
    color = color + vec3<f32>(rS, gS, bS) * layerWeight;
  }
  color = color / (1.0 + 0.5 + 0.33);

  let fog = 1.0 - smoothstep(0.0, 0.8, depthLayer);
  color = color * (0.5 + 0.5 * fog);

  let ringGlow = smoothstep(0.02, 0.0, abs(depthLayer - 0.5)) * 0.3;
  color = color + vec3<f32>(0.6, 0.8, 1.0) * ringGlow * (1.0 + bass * 0.4);

  let srcA = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
  let alpha = clamp(depthLayer * 0.55 + ringGlow * 0.35 + srcA * 0.25 + bass * 0.08, 0.08, 1.0);
  let mapped = acesToneMap(color);
  let outCol = vec4<f32>(mapped, alpha);

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(d, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, outCol);
}
