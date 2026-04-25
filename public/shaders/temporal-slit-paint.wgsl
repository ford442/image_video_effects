// ═══════════════════════════════════════════════════════════════════
//  Temporal Slit Paint
//  Category: artistic
//  Features: mouse-driven
//  Complexity: Medium-High
//  Upgraded: 2026-04-25
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

// ── Hash & Noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}
fn hash11(p: f32) -> f32 {
  return fract(sin(p * 12.9898) * 43758.5453);
}
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}
fn rgbToLuma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let c = hsv.z * hsv.y;
  let h = hsv.x * 6.0;
  let x = c * (1.0 - abs(fract(h) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else              { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(hsv.z - c);
}
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}
fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
  let d = abs(p) - b;
  return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}
fn sdLine(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// ── Brush Mask ───────────────────────────────────────────────
fn brushMask(uv: vec2<f32>, center: vec2<f32>, size: f32, shapeType: i32, rotation: f32, softness: f32) -> f32 {
  let local = uv - center;
  let ca = cos(rotation);
  let sa = sin(rotation);
  let rot = vec2<f32>(local.x * ca - local.y * sa, local.x * sa + local.y * ca);
  var d = 0.0;
  if (shapeType == 0) {
    d = length(rot);
  } else if (shapeType == 1) {
    d = pow(pow(abs(rot.x), 2.5) + pow(abs(rot.y), 2.5), 0.4);
  } else if (shapeType == 2) {
    let angle = atan2(rot.y, rot.x);
    let rad = length(rot);
    let n = 5.0;
    let sector = 6.283 / n;
    let a = fract(angle / sector + 0.5) * sector - sector * 0.5;
    d = cos(a) * rad;
  } else {
    let q = vec2<f32>(abs(rot.x), rot.y);
    let w = q.x - q.y * 0.5 + 0.05;
    d = length(vec2<f32>(w, q.y - 0.1));
  }
  let inner = size * (1.0 - softness);
  return 1.0 - smoothstep(inner, size, d);
}

// ── MAIN ─────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let brushSize = mix(0.01, 0.2, u.zoom_params.x);
  let shapeType = i32(clamp(u.zoom_params.y * 3.0 + 0.5, 0.0, 3.0));
  let softness = u.zoom_params.z;
  let diffusion = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let aspect = resolution.x / resolution.y;

  // Synthetic velocity for anisotropic smear
  let vel = vec2<f32>(cos(time * 2.0 + mouse.x * 6.28), sin(time * 3.0 + mouse.y * 6.28)) * 0.01;
  let velAngle = atan2(vel.y, vel.x);

  // Sample history and current input
  let hist = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Diffusion from history neighbors
  let texel = 1.0 / resolution;
  let n1 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0);
  let n2 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0);
  let n3 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0);
  let n4 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0);
  let laplacian = (n1 + n2 + n3 + n4) * 0.25;

  // Brush application
  let mask = brushMask(uv, mouse, brushSize, shapeType, velAngle, softness);

  var paintColor = hist;
  if (mouseDown && mask > 0.0) {
    paintColor = mix(hist, current, mask);
    paintColor.a = mix(hist.a, 1.0, mask);
  } else {
    paintColor.a = paintColor.a * 0.995;
  }

  // Apply diffusion to paint
  paintColor = mix(paintColor, laplacian, diffusion * 0.1);

  // Clamp alpha
  paintColor.a = clamp(paintColor.a, 0.0, 1.0);

  textureStore(writeTexture, global_id.xy, paintColor);
  textureStore(dataTextureA, global_id.xy, paintColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
