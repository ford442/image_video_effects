// ═══════════════════════════════════════════════════════════════════
//  Wave Halftone v2
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: wave-halftone
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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn acesTone(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hexCell(uv: vec2<f32>, density: f32) -> vec2<f32> {
  let s = uv * density;
  let r = vec2<f32>(1.0, 1.7320508);
  let h = r * 0.5;
  let a = fract(s) - h;
  let b = fract(s - h) - h;
  return select(a, b, dot(a, a) < dot(b, b));
}

fn hexCenter(uv: vec2<f32>, density: f32) -> vec2<f32> {
  let s = uv * density;
  let r = vec2<f32>(1.0, 1.7320508);
  let h = r * 0.5;
  let a = fract(s) - h;
  let b = fract(s - h) - h;
  let gv = select(a, b, dot(a, a) < dot(b, b));
  let id = s - gv;
  return id / density;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let dotSizeScale = 0.4 + u.zoom_params.x * 0.8;
  let gridDensity = 12.0 + u.zoom_params.y * 80.0;
  let waveAmp = u.zoom_params.z * 0.15;
  let chromaticAmt = u.zoom_params.w * 0.02;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Hexagonal close-packed grid coordinates
  let hexUV = hexCell(uv, gridDensity);
  let hexDist = length(hexUV);

  // 2D wave equation interference from multiple oscillators
  var interference = 0.0;
  interference = interference + sin(uv.x * 12.0 + time * 2.0) * cos(uv.y * 10.0 - time * 1.5);
  interference = interference + sin((uv.x + uv.y) * 8.0 + time * 1.2) * 0.5;
  interference = interference + cos(uv.x * 6.0 - time * 0.8) * sin(uv.y * 14.0 + time * 1.1) * 0.3;
  interference = interference * waveAmp * (1.0 + bass * 1.5);

  // Dynamic wave sources from mouse ripples
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let d = length(uv - r.xy);
    let t = time - r.z;
    interference = interference + sin(d * 30.0 - t * 8.0) * exp(-d * 5.0) * 0.06 * mouseDown;
  }

  // Mouse cursor acts as a continuous wave source
  let mouseDist = length(uv - mousePos);
  interference = interference + sin(mouseDist * 25.0 - time * 5.0) * exp(-mouseDist * 4.0) * 0.08 * mouseDown;

  // Sample image at hex cell center for color quantization
  let cellCenter = hexCenter(uv, gridDensity);
  let safeCenter = clamp(cellCenter, vec2<f32>(0.001), vec2<f32>(0.999));
  let color = textureSampleLevel(readTexture, u_sampler, safeCenter, 0.0);
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // Depth controls dot perspective (smaller dots for distant objects)
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let perspective = mix(0.6, 1.0, depth);

  // Dot radius modulated by luma and wave interference crests
  let waveMod = 1.0 + interference * 0.5;
  let radius = luma * 0.45 * dotSizeScale * waveMod * perspective;

  // Moire patterns at high-interference nodes
  let moire = smoothstep(0.7, 1.0, abs(interference)) * 0.25;

  // Chromatic aberration on wave crests
  let crestMask = smoothstep(0.5, 1.0, abs(interference));
  let rShift = chromaticAmt * crestMask * perspective;
  let rSample = textureSampleLevel(readTexture, u_sampler, clamp(safeCenter + vec2<f32>(rShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bSample = textureSampleLevel(readTexture, u_sampler, clamp(safeCenter - vec2<f32>(rShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  // Paper texture grain
  let paper = hash21(uv * 400.0 + time * 0.1) * 0.06 + 0.94;

  // Anti-aliased dot mask
  let edgeWidth = 0.08 * perspective;
  let mask = smoothstep(radius + edgeWidth, radius - edgeWidth, hexDist);

  let dotColor = vec3<f32>(rSample, color.g, bSample) * mask * paper;
  let moireColor = vec3<f32>(0.85, 0.92, 1.0) * moire * mask * (0.5 + treble * 0.5);

  // ACES tone mapping on final composited color
  let finalColor = acesTone(dotColor + moireColor + color.rgb * 0.04);

  // Alpha: wave interference intensity × dot_density × depth
  let interferenceIntensity = smoothstep(0.0, 1.0, abs(interference) + 0.2);
  let dotDensity = mask * luma;
  let alpha = clamp(interferenceIntensity * dotDensity * depth + mask * 0.12, 0.1, 0.9);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(interference, mask, luma, alpha));
}
