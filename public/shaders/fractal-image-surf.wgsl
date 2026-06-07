// ═══════════════════════════════════════════════════════════════════
//  Fractal Image Surf v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: fractal-image-surf
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

fn hash33(p: vec3<f32>) -> vec3<f32> {
  let q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                    dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                    dot(p, vec3<f32>(113.5, 271.9, 124.6)));
  return fract(sin(q) * 43758.5453);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var val = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    let i2 = vec2<f32>(f32(i) * 37.0, f32(i) * 93.0);
    let n = hash33(vec3<f32>(p * freq, 0.0) + vec3<f32>(i2, 0.0)).x;
    val = val + n * amp;
    amp = amp * 0.5;
    freq = freq * 2.03;
  }
  return val;
}

fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn julia_iter(z: vec2<f32>, c: vec2<f32>, maxIter: u32) -> vec2<f32> {
  var p = z;
  for (var i: u32 = 0u; i < maxIter; i = i + 1u) {
    p = cmul(p, p) + c;
    if (dot(p, p) > 16.0) { break; }
  }
  return p;
}

fn mandelbrot_iter(z: vec2<f32>, maxIter: u32) -> vec2<f32> {
  var p = vec2<f32>(0.0, 0.0);
  for (var i: u32 = 0u; i < maxIter; i = i + 1u) {
    p = cmul(p, p) + z;
    if (dot(p, p) > 16.0) { break; }
  }
  return p;
}

fn burning_ship_iter(z: vec2<f32>, c: vec2<f32>, maxIter: u32) -> vec2<f32> {
  var p = z;
  for (var i: u32 = 0u; i < maxIter; i = i + 1u) {
    p = cmul(vec2<f32>(abs(p.x), abs(p.y)), vec2<f32>(abs(p.x), abs(p.y))) + c;
    if (dot(p, p) > 16.0) { break; }
  }
  return p;
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, 0.0, 1.0);

  let iterations = u32(clamp(u.zoom_params.x * 28.0 + 4.0, 4.0, 32.0));
  let zoom = max(u.zoom_params.y * 1.5 + 0.1, 0.1);
  let offset = vec2<f32>(u.zoom_params.z - 0.5, u.zoom_params.w - 0.5) * 0.6;

  let centered = (uv - 0.5) * zoom * (1.0 + bass * 0.3) + offset + (mouse - 0.5) * 0.6;
  let c = vec2<f32>((mouse.x - 0.5) * 0.85 + 0.18, (mouse.y - 0.5) * 0.7 - 0.22 + sin(time * 0.9) * 0.07);

  let fractalMorph = bass;
  var zJ = julia_iter(centered, c, iterations);
  var zM = mandelbrot_iter(centered, iterations);
  var zB = burning_ship_iter(centered, c, iterations);

  let fj = 1.0 / (1.0 + dot(zJ, zJ));
  let fm = 1.0 / (1.0 + dot(zM, zM));
  let fb = 1.0 / (1.0 + dot(zB, zB));
  let w1 = smoothstep(0.0, 0.5, fractalMorph);
  let w2 = smoothstep(0.5, 1.0, fractalMorph);
  let det = fj * (1.0 - w1) + fm * (w1 - w2) + fb * w2;

  let warp = fbm(centered * 3.0 + vec2<f32>(time * 0.1), 5);
  let dwarp = vec2<f32>(
    fbm(centered * 3.0 + vec2<f32>(0.01, 0.0) + vec2<f32>(time * 0.1), 5) - warp,
    fbm(centered * 3.0 + vec2<f32>(0.0, 0.01) + vec2<f32>(time * 0.1), 5) - warp
  ) * 50.0;
  let jac = abs(1.0 + dwarp.x * dwarp.y - dot(dwarp, dwarp) * 0.25);
  let safeJac = max(jac, 0.3);

  let parallax = depth * 0.012;
  let layer1 = uv + (vec2<f32>(zJ.x, zJ.y) * 0.008 + dwarp * 0.005) / safeJac;
  let layer2 = uv + (vec2<f32>(zM.x, zM.y) * 0.006 + dwarp * 0.004) / safeJac + parallax;
  let sampleUV = clamp(mix(layer1, layer2, w1), vec2<f32>(0.001), vec2<f32>(0.999));

  let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let spec = pow(max(det - 0.4, 0.0), 3.0) * (0.6 + treble * 0.6);
  let hdrSpec = vec3<f32>(0.75, 0.88, 1.0) * spec;
  let grain = hash33(vec3<f32>(uv * resolution, time * 60.0)).x * 0.04 - 0.02;
  let finalColor = aces_tone_map(baseColor.rgb * (0.8 + det * 0.35) + hdrSpec + grain);

  let alpha = clamp(det * warp * depth * 0.8 + baseColor.a * 0.2 + spec * 0.15, 0.08, 1.0);
  let outDepth = clamp(depth + det * 0.05 + warp * 0.03, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(det, warp, spec, alpha));
}
