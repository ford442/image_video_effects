// ═══════════════════════════════════════════════════════════════════
//  Apollonian Gasket
//  Category: generative
//  Features: procedural, fractal, apollonian-gasket, circle-inversion,
//            descartes-theorem, audio-reactive, mouse-driven, aces-tonemap, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-06-06
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

fn circle_inv(p: vec2<f32>, c: vec2<f32>, r: f32) -> vec2<f32> {
  let d = p - c;
  let l2 = dot(d, d) + 1e-8;
  return c + d * (r * r) / l2;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x * 2.6;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) { springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]); lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5; }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 8.0; let springDecay = exp(-omega * dt); let sdelta = springPos - rawMouse; let temp = (springVel + omega * sdelta) * dt;
  springVel = (springVel - omega * temp) * springDecay; springPos = rawMouse + (sdelta + temp) * springDecay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) { extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y; extraBuffer[137] = time; extraBuffer[138] = 1.0; }
  let mouse = springPos;
  let mouseDown = u.zoom_config.w > 0.5;
  let held = select(1.0, 1.5, mouseDown);

  let recursion = i32(mix(3.0, 10.0, clamp(u.zoom_params.x + bass * 0.3, 0.0, 1.0)));
  let invIntensity = u.zoom_params.y;
  let circleSize = mix(0.5, 2.0, u.zoom_params.z);
  let rainbow = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 3.0 / circleSize;

  // Descartes theorem: k4 = k1+k2+k3 ± 2*sqrt(k1k2+k2k3+k3k1)
  // Curvature k = 1/r. For r=0.5, k=2.0; for r=0.155, k≈6.45; for r=0.3, k≈3.33
  let circles = array<vec3<f32>, 5>(
    vec3<f32>(0.5, 0.0, 0.5),    // center=(0.5,0), r=0.5, k=2.0
    vec3<f32>(-0.5, 0.0, 0.5),   // center=(-0.5,0), r=0.5, k=2.0
    vec3<f32>(0.0, 0.866, 0.5),  // center=(0,0.866), r=0.5, k=2.0
    vec3<f32>(0.0, 0.289, 0.155),// center=(0,0.289), r=0.155, k≈6.45
    vec3<f32>(0.0, -0.5, 0.3)    // center=(0,-0.5), r=0.3, k≈3.33
  );

  var q = p;
  var invCount = 0.0;
  let spin = mat2x2<f32>(cos(time * 0.35 + mids), sin(time * 0.35), -sin(time * 0.35), cos(time * 0.35 + mids));
  q = spin * q;

  for (var i = 0; i < recursion; i = i + 1) {
    var inverted = false;
    for (var j = 0; j < 5; j = j + 1) {
      let c = circles[j].xy;
      let r = circles[j].z;
      if (distance(q, c) < r) {
        q = circle_inv(q, c, r);
        invCount = invCount + 1.0;
        inverted = true;
        break;
      }
    }
    if (!inverted) { break; }
  }

  let mp = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 3.0 / circleSize;
  let mr = (0.18 + invIntensity * 0.35) * held;
  if (distance(q, mp) < mr * 1.4) {
    q = circle_inv(q, mp, mr);
    invCount = invCount + 1.0;
  }

  var minDist = 1e9;
  for (var j = 0; j < 5; j = j + 1) {
    let d = abs(distance(q, circles[j].xy) - circles[j].z);
    minDist = min(minDist, d);
  }

  let density = exp(-minDist * 15.0);
  let hue = fract(invCount * 0.14 + length(q) * 0.3 + time * 0.12 + treble * 0.2);
  let sat = 0.55 + density * 0.45 + mids * 0.15;
  let val = 0.18 + density * 0.85;

  var color = vec3<f32>(
    val * (0.5 + sat * cos(hue * 6.283) * 0.5),
    val * (0.5 + sat * cos((hue - 0.33) * 6.283) * 0.5),
    val * (0.5 + sat * cos((hue - 0.66) * 6.283) * 0.5)
  );
  let ring = abs(fract(minDist * 18.0 + time * 2.0) - 0.5);
  color += vec3<f32>(1.0, 0.2, 0.85) * (1.0 - smoothstep(0.0, 0.08, ring)) * 0.35;

  let ca = smoothstep(0.0, 0.4, density) * rainbow;
  color = vec3<f32>(
    color.r * (1.0 + ca * 0.2),
    color.g * (1.0 + ca * 0.05),
    color.b * (1.0 - ca * 0.1)
  );

  let alpha = density * clamp(invCount / 8.0, 0.0, 1.0) * (0.7 + bass * 0.3);
  let depth = clamp(1.0 - minDist * 2.0, 0.0, 1.0);

  // Temporal feedback
  let hist = textureLoad(dataTextureC, coord, 0).rgb;
  color = mix(color, hist * 0.94, 0.05);

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  // Write temporal feedback before ACES so next frame reads untonemapped color
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));

  // Single ACES tonemap
  color = acesToneMap(color * 2.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
