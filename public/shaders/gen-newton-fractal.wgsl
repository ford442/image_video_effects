// ═══════════════════════════════════════════════════════════════════
//  Newton Fractal
//  Category: generative
//  Features: procedural, fractal, newton-method, orbit-trap,
//            audio-reactive, mouse-driven, aces-tonemap, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-30
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

fn cpower(z: vec2<f32>, n: f32) -> vec2<f32> {
  let r = length(z);
  let a = atan2(z.y, z.x);
  let rn = pow(r + 1e-6, n);
  return vec2<f32>(rn * cos(n * a), rn * sin(n * a));
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  let d = dot(b, b) + 1e-8;
  return vec2<f32>((a.x * b.x + a.y * b.y) / d, (a.y * b.x - a.x * b.y) / d);
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mouse = u.zoom_config.yz;

  let zoom = mix(0.6, 5.0, u.zoom_params.x);
  let degree = mix(3.0, 5.0, clamp(u.zoom_params.y + bass * 0.4, 0.0, 1.0));
  let iterDepth = i32(mix(25.0, 90.0, u.zoom_params.z));
  let bloom = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 3.5 / zoom;
  let zoomCenter = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
  p = p + zoomCenter;

  var z = p;
  var iters = 0;
  var orbitMin = 1e9;

  for (var i = 0; i < iterDepth; i = i + 1) {
    let zn = cpower(z, degree);
    let znm1 = cpower(z, degree - 1.0);
    let dz = cdiv(zn - vec2<f32>(1.0, 0.0), degree * znm1);
    z = z - dz;
    iters = i;

    let maxRoots = min(i32(degree + 0.5), 5);
    for (var k = 0; k < 5; k = k + 1) {
      if (k >= maxRoots) { break; }
      let ra = 6.28318 * f32(k) / degree;
      let root = vec2<f32>(cos(ra), sin(ra));
      orbitMin = min(orbitMin, distance(z, root));
    }

    if (length(dz) < 1e-4) { break; }
  }

  let angle = atan2(z.y, z.x);
  let rootIdx = clamp(i32(fract(angle / (6.28318 / degree) + 0.5) * degree + 0.5) % 5, 0, 4);

  let rootColors = array<vec3<f32>, 5>(
    vec3<f32>(1.0, 0.12, 0.08),
    vec3<f32>(0.08, 0.92, 0.15),
    vec3<f32>(0.08, 0.25, 1.0),
    vec3<f32>(1.0, 0.85, 0.08),
    vec3<f32>(0.95, 0.08, 0.85)
  );

  let iterRatio = f32(iters) / f32(iterDepth);
  var color = rootColors[rootIdx] * (1.0 - iterRatio * 0.6);

  let orbitGlow = exp(-orbitMin * 8.0);
  color = color + vec3<f32>(0.5, 0.65, 0.9) * orbitGlow * bloom * 2.0;

  let boundary = exp(-iterRatio * 10.0);
  color = color + vec3<f32>(0.4, 0.55, 0.8) * boundary * bloom * 1.5;

  let ca = smoothstep(0.15, 0.55, iterRatio);
  color = vec3<f32>(color.r * (1.0 + ca * 0.18), color.g, color.b * (1.0 - ca * 0.08));

  color = aces_tonemap(color * 1.8);

  let histUV = uv + vec2<f32>(sin(time * 0.2) * 0.002, cos(time * 0.15) * 0.002);
  let prev = textureSampleLevel(dataTextureC, u_sampler, histUV, 0.0).rgb;
  color = mix(color, prev * 0.93, 0.06);

  let convergence = 1.0 - iterRatio;
  let alpha = convergence * (1.0 - boundary * 0.25) * clamp(1.0 - length(uv - 0.5) * 1.1, 0.0, 1.0);
  let depth = convergence * (0.8 + iterRatio * 0.2);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
