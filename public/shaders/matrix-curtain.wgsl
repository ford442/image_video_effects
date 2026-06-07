// ═══════════════════════════════════════════════════════════════════
//  Matrix Curtain v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal
//  Complexity: High
//  Chunks From: matrix-curtain, conway-gol, perlin-noise
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
  return fract(vec2<f32>(n, n * 1.618) * 43758.5453123);
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn noise21(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn gol_state(col: f32, row: f32, t: f32) -> f32 {
  let h = hash12(vec2<f32>(col * 7.31 + floor(t * 0.5), row * 3.17));
  let birth = step(0.72, h);
  let survive = step(0.35, hash12(vec2<f32>(col * 5.13 + floor(t * 0.5) + 1.0, row * 2.71)));
  return max(birth, survive * 0.6);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let mouseDown = u.zoom_config.w > 0.5;
  let speed = mix(0.2, 3.0, u.zoom_params.x);
  let density = mix(24.0, 200.0, u.zoom_params.y);
  let width = mix(0.05, 0.6, u.zoom_params.z);
  let glowAmt = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let column = floor(uv.x * density);
  let colPhase = hash12(vec2<f32>(column, 0.0));
  let colVel = 0.6 + noise21(vec2<f32>(column * 0.07, time * 0.03)) * 1.8;
  let spawnRate = step(0.92 - bass * 0.18, hash12(vec2<f32>(column, floor(time * 2.0))));
  let shiftX = (mouse.x - 0.5) * 0.08 * width;
  let shiftedUV = vec2<f32>(fract(uv.x + shiftX), uv.y);
  let rainSpeed = speed * colVel * (0.5 + mouse.y * 1.5);

  let fall = fract(shiftedUV.y * (10.0 + density * 0.1) + time * rainSpeed + colPhase * 6.28);
  let row = floor((1.0 - fall) * 32.0 + time * 4.0);
  let gol = gol_state(column, row, time);
  let glyph = step(0.55, gol * spawnRate + hash12(vec2<f32>(column, row)) * 0.25);

  let curtainMask = smoothstep(width * 0.5 + 0.04, 0.0, abs(uv.x - mouse.x));
  let scan = smoothstep(0.22, 0.0, abs(fall - 0.12));
  let ghost = smoothstep(0.55, 0.0, abs(fall - 0.35)) * colVel * 0.35;

  let prevUV = clamp(uv + vec2<f32>(0.0, -1.0 / resolution.y), vec2<f32>(0.001), vec2<f32>(0.999));
  let prev = textureSampleLevel(dataTextureC, u_sampler, prevUV, 0.0);
  let phosphorDecay = prev.r * 0.82;

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let phosphorGreen = vec3<f32>(0.05, 0.95, 0.25);
  let phosphorDim = vec3<f32>(0.02, 0.45, 0.12);
  let codeColor = mix(phosphorDim, phosphorGreen, glyph) * curtainMask;
  let bloom = vec3<f32>(0.15, 1.0, 0.4) * scan * curtainMask * (0.22 + bass * 0.18);
  let trail = phosphorGreen * ghost * curtainMask * 0.14;
  var hdr = baseColor.rgb * 0.25 + codeColor + bloom + trail + phosphorDecay * vec3<f32>(0.08, 0.35, 0.12);

  let scanlineBeat = sin(uv.y * resolution.y * 0.5 + time * 12.0 + bass * 6.28) * 0.5 + 0.5;
  hdr = hdr * (0.92 - scanlineBeat * 0.06);

  let parallax = depth * 0.04 * (mouse.x - 0.5);
  let vign = 1.0 - length((uv - 0.5) * vec2<f32>(1.0, resolution.y / resolution.x)) * 0.6;
  hdr = hdr * max(vign, 0.3);

  let tonemapped = aces_tonemap(hdr * (0.9 + glowAmt * 0.4));
  let brightness = glyph * 0.7 + scan * 0.4 + ghost * 0.25 + phosphorDecay * 0.3;
  let alpha = clamp(baseColor.a * 0.2 + curtainMask * 0.18 + brightness * (0.35 + bass * 0.15), 0.06, 0.95);

  let finalPixel = vec4<f32>(tonemapped, alpha);
  let outDepth = clamp(depth + curtainMask * 0.06 + brightness * 0.04, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(brightness, curtainMask, glyph, alpha));
}
