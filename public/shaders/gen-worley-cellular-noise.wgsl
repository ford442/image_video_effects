// ═══════════════════════════════════════════════════════════════════
//  Worley Cellular Noise
//  Category: generative
//  Features: procedural, cellular, worley, organic, audio-reactive,
//            mouse-driven, chromatic-aberration, aces-tonemap,
//            temporal-feedback, depth-aware
//  Complexity: High
//  Created: 2026-05-31
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)),
                     dot(p, vec2<f32>(269.5, 183.3)));
  return fract(sin(q) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
             u2.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var q = p;
  for (var i = 0u; i < 4u; i = i + 1u) {
    v = v + a * noise2(q);
    q = q * 2.03 + vec2<f32>(3.1, 1.7);
    a = a * 0.5;
  }
  return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;

  let scale = mix(3.0, 12.0, u.zoom_params.x) * (1.0 + bass * 0.3);
  let speed = mix(0.05, 0.4, u.zoom_params.y);
  let caAmt = u.zoom_params.z;
  let organic = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * vec2<f32>(aspect, 1.0) * scale;

  // Mouse attracts feature points
  let mPos = mouse * vec2<f32>(aspect, 1.0) * scale;
  p = p - mPos * 0.15;

  // Depth controls cell size perspective
  let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  p = p * (0.5 + depthSample);

  let cell = floor(p);
  let fracP = fract(p);

  var f1 = 1e9;
  var f2 = 1e9;

  // Search 3x3 neighborhood for feature points
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let neighbor = cell + vec2<f32>(f32(x), f32(y));
      let rnd = hash22(neighbor + vec2<f32>(time * speed * 10.0, 0.0));
      let feature = neighbor + rnd + vec2<f32>(
        sin(time * speed + rnd.x * 6.28) * 0.15 * (1.0 + bass),
        cos(time * speed + rnd.y * 6.28) * 0.15 * (1.0 + bass)
      );
      let d = distance(p, feature);
      if d < f1 {
        f2 = f1;
        f1 = d;
      } else if d < f2 {
        f2 = d;
      }
    }
  }

  var boundary = f2 - f1;
  let cellId = hash21(cell);

  // Temporal feedback for organic drift
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let drift = mix(0.0, prev.g * 0.08, organic);
  f1 = f1 + drift;
  boundary = boundary + drift * 0.5;

  // Organic tissue palette
  let tissue = mix(
    vec3<f32>(0.85, 0.55, 0.50),   // pink
    vec3<f32>(0.95, 0.72, 0.55),   // coral
    cellId
  );
  let ivory = vec3<f32>(0.96, 0.94, 0.88);
  let taupe = vec3<f32>(0.55, 0.48, 0.42);

  // Subsurface scattering on cell boundaries
  let scatter = exp(-boundary * 8.0) * (0.6 + mids * 0.4);
  var color = mix(taupe, mix(tissue, ivory, smoothstep(0.0, 0.4, f1)), smoothstep(0.0, 0.6, f1));
  color = color + vec3<f32>(1.0, 0.7, 0.5) * scatter * 0.5;

  // fBm for organic variation
  let org = fbm(p * 2.0 + vec2<f32>(time * 0.1, 0.0));
  color = mix(color, color * (0.8 + org * 0.4), organic);

  // HDR boundary glow
  let glow = exp(-boundary * 15.0) * (0.3 + treble * 0.5);
  color = color + vec3<f32>(0.9, 0.75, 0.55) * glow;

  // Chromatic aberration on thin membranes
  let caMask = smoothstep(0.0, 0.08, boundary) * (1.0 - smoothstep(0.08, 0.2, boundary)) * caAmt;
  let caR = acesToneMap(vec3<f32>(color.r * 1.1, color.g * 0.97, color.b * 0.9) * 1.2);
  let caB = acesToneMap(vec3<f32>(color.r * 0.9, color.g * 0.97, color.b * 1.1) * 1.2);
  color = mix(acesToneMap(color * 1.2), mix(caR, caB, caMask), caMask * 0.4);

  // Alpha: cell_boundary_proximity × tissue_density × depth
  let tissueDensity = clamp(1.0 - f1 * 0.5, 0.0, 1.0);
  let alpha = clamp(scatter * tissueDensity * depthSample, 0.0, 1.0);
  let depthOut = clamp(0.2 + tissueDensity * 0.8, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(f1, boundary, scatter, alpha));
}
