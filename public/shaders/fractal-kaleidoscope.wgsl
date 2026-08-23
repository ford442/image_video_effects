// ═══════════════════════════════════════════════════════════════════
//  Fractal Kaleidoscope
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware,
//            facet-seams, held-drag, bounded-click-ripples
//  Complexity: High
//  Upgraded: 2026-08-23
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

fn rotate2D(uv: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn kaleidoscopeFractal(uv: vec2<f32>, segments: f32) -> vec2<f32> {
  var coord = uv - 0.5;
  let radius = length(coord);
  var angle = atan2(coord.y, coord.x);
  let segmentAngle = 6.28318530718 / max(segments, 1.0);
  angle = abs(fract(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
  coord = vec2<f32>(cos(angle), sin(angle)) * radius;
  return coord + 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let held = f32(u.zoom_config.w > 0.5);
  let mouse = u.zoom_config.yz;
  let prev = textureLoad(dataTextureC, pixel, 0);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let intensity = u.zoom_params.x;
  let speed = u.zoom_params.y;
  let scaleP = u.zoom_params.z;
  let detail = u.zoom_params.w;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  let segments = mix(4.0, 14.0, intensity) + sin(time * mix(0.12, 0.55, speed)) * 1.5;
  let pivot = mix(vec2<f32>(0.5), mouse, 0.35 + held * 0.4);
  var kaleidoUV = kaleidoscopeFractal(uv - pivot + 0.5, segments);
  var coord = kaleidoUV;
  let iterations = 2 + i32(detail * 3.0 + depth);
  for (var i: i32 = 0; i < 5; i = i + 1) {
    if (i >= iterations) { break; }
    let level = f32(i);
    let zoomAmt = (1.0 + sin(time * (0.25 + speed) + level * 1.5) * mix(0.12, 0.38, scaleP));
    coord = rotate2D(coord - 0.5, time * 0.1 * (1.0 + level * 0.5)) * zoomAmt + 0.5;
    coord += vec2<f32>(sin(time * 0.5 + level + depth * 2.0), cos(time * 0.5 + level + depth * 2.0)) * 0.02;
  }
  let finalUV = clamp(coord, vec2<f32>(0.0), vec2<f32>(1.0));
  let chromaticOffset = 0.003 * (1.0 - depth) * (0.6 + intensity);
  let colorR = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + vec2<f32>(chromaticOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let colorG = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
  let colorB = textureSampleLevel(readTexture, u_sampler, clamp(finalUV - vec2<f32>(chromaticOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var finalColor = vec3<f32>(colorR, colorG, colorB) * (0.8 + depth * 0.4);

  let folded = abs(fract(atan2(uv.y - pivot.y, uv.x - pivot.x) / 6.28318530718 * segments) - 0.5);
  let seam = pow(1.0 - folded * 2.0, 3.0);
  let conveyor = smoothstep(0.09, 0.0, abs(fract(length(uv - pivot) * 8.0 - time * (1.8 + bass * 2.0)) - 0.5));
  var click = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
      click = max(click, exp(-abs(distance(uv, rp.xy) - age * 0.5) * 64.0) * (1.0 - age / 1.5));
    }
  }
  let slick = hsv2rgb(vec3<f32>(fract(folded * 2.0 + time * 0.12 + mids * 0.25), 0.75, 0.95));
  finalColor = mix(finalColor, finalColor * slick * 1.3, 0.28 + treble * 0.2);
  finalColor += slick * (seam * 0.22 + conveyor * 0.26 + click * 0.55);

  let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(0.28 + luma * 0.62 + click * 0.12, 0.0, 1.0);
  let outCol = vec4<f32>(mix(finalColor, prev.rgb * 0.86, 0.26), mix(alpha, prev.a * 0.86, 0.26));
  textureStore(writeTexture, pixel, outCol);
  textureStore(dataTextureA, pixel, outCol);
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + seam * 0.08 + click * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
