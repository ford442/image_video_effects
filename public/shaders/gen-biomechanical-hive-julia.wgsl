// ═══════════════════════════════════════════════════════════════════
//  Gen Biomechanical Hive Julia
//  Category: advanced-hybrid
//  Features: raymarched, quaternion-julia, biomechanical, mouse-driven
//  Complexity: Very High
//  Chunks From: gen-biomechanical-hive.wgsl, spec-quaternion-julia.wgsl
//  Created: 2026-04-18
//  By: Agent CB-5 — Generative & Hybrid Enhancer
// ═══════════════════════════════════════════════════════════════════
//  A biomechanical hive where each cell contains a living quaternion
//  Julia fractal core. The chitinous exoskeleton surrounds morphing
//  4D fractal organisms that pulse with bioluminescence.
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

// ═══ CHUNK: hash (from gen-biomechanical-hive.wgsl) ═══
fn hash(p: vec3<f32>) -> f32 {
  let p3 = fract(p * 0.1031);
  let d = dot(p3, vec3<f32>(p3.y + 19.19, p3.z + 19.19, p3.x + 19.19));
  return fract((p3.x + p3.y) * p3.z + d);
}

fn noise(p: vec3<f32>) -> f32 {
  var i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(hash(i + vec3<f32>(0.0, 0.0, 0.0)), hash(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
                 mix(hash(i + vec3<f32>(0.0, 1.0, 0.0)), hash(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
             mix(mix(hash(i + vec3<f32>(0.0, 0.0, 1.0)), hash(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
                 mix(hash(i + vec3<f32>(0.0, 1.0, 1.0)), hash(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
  var val = 0.0;
  var amp = 0.5;
  var pos = p;
  for (var i = 0; i < 4; i++) {
    val += amp * noise(pos);
    pos = pos * 2.0;
    amp *= 0.5;
  }
  return val;
}

fn sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32 {
  let k = vec3<f32>(-0.8660254, 0.5, 0.57735027);
  let p_abs = abs(p);
  let dot_k_p = dot(k.xy, p_abs.xy);
  let offset = 2.0 * min(dot_k_p, 0.0);
  var p_xy = p_abs.xy - vec2<f32>(offset * k.x, offset * k.y);
  let d = vec2<f32>(
     length(p_xy - vec2<f32>(clamp(p_xy.x, -k.z*h.x, k.z*h.x), h.x)) * sign(p_xy.y - h.x),
     p_abs.z - h.y
  );
  return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// ═══ CHUNK: quaternionMul (from spec-quaternion-julia.wgsl) ═══
fn quaternionMul(a: vec4<f32>, b: vec4<f32>) -> vec4<f32> {
  return vec4<f32>(
    a.x*b.x - a.y*b.y - a.z*b.z - a.w*b.w,
    a.x*b.y + a.y*b.x + a.z*b.w - a.w*b.z,
    a.x*b.z - a.y*b.w + a.z*b.x + a.w*b.y,
    a.x*b.w + a.y*b.z - a.z*b.y + a.w*b.x
  );
}

// ═══ CHUNK: quaternionJuliaDE (from spec-quaternion-julia.wgsl) ═══
fn quaternionJuliaDE(p: vec3<f32>, c: vec4<f32>) -> f32 {
  var q = vec4<f32>(p, 0.0);
  var dq = vec4<f32>(1.0, 0.0, 0.0, 0.0);
  for (var i: i32 = 0; i < 8; i = i + 1) {
    dq = 2.0 * quaternionMul(q, dq);
    q = quaternionMul(q, q) + c;
    if (dot(q, q) > 256.0) { break; }
  }
  let r = length(q);
  let dr = length(dq);
  return 0.5 * r * log(r) / max(dr, 0.001);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

// Scene map: hex hive with Julia core
fn map(p: vec3<f32>, time: f32, c: vec4<f32>, density: f32, biomass: f32, pulseSpeed: f32) -> vec2<f32> {
  let cell_size = 12.0 / density;
  let spacing = vec3<f32>(cell_size * 2.0, cell_size * 2.0, cell_size * 4.0);
  let id = floor((p + spacing * 0.5) / spacing);
  let local_p = (fract((p + spacing * 0.5) / spacing) - 0.5) * spacing;

  let hex_h = vec2<f32>(cell_size * 0.8, cell_size * 1.8);
  let d_hex = sdHexPrism(local_p, hex_h * 0.9);
  let d_base = -d_hex;

  // Ribs/Pipes
  let rib_freq = 10.0;
  let rib_amp = 0.05;
  let ribs = sin(local_p.z * rib_freq) * rib_amp;

  // Organic displacement
  var pulse = sin(time * pulseSpeed * 2.0) * 0.5 + 0.5;
  let noise_val = fbm(p * 2.0 + vec3<f32>(0.0, 0.0, time * 0.2));
  let displacement = noise_val * biomass * 0.5;
  let breathing = sin(time + p.z) * 0.05;

  let d_organic = d_base + ribs + displacement + breathing;

  // Quaternion Julia core instead of sphere
  let juliaScale = cell_size * 0.15;
  let juliaLocal = local_p / juliaScale;
  let d_julia = quaternionJuliaDE(juliaLocal, c) * juliaScale;

  // Combine walls and Julia core
  let d_final = min(d_organic, d_julia);

  var mat = 1.0;
  if (d_julia < d_organic) {
    mat = 2.0;
  }

  return vec2<f32>(d_final, mat);
}

fn calcNormal(p: vec3<f32>, time: f32, c: vec4<f32>, density: f32, biomass: f32, pulseSpeed: f32) -> vec3<f32> {
  let e = 0.001;
  var d = map(p, time, c, density, biomass, pulseSpeed).x;
  return normalize(vec3<f32>(
    map(p + vec3<f32>(e, 0.0, 0.0), time, c, density, biomass, pulseSpeed).x - d,
    map(p + vec3<f32>(0.0, e, 0.0), time, c, density, biomass, pulseSpeed).x - d,
    map(p + vec3<f32>(0.0, 0.0, e), time, c, density, biomass, pulseSpeed).x - d
  ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, c: vec4<f32>, density: f32, biomass: f32, pulseSpeed: f32) -> vec2<f32> {
  var t = 0.0;
  var mat = 0.0;
  for(var i=0; i<100; i++) {
    var p = ro + rd * t;
    var res = map(p, time, c, density, biomass, pulseSpeed);
    var d = res.x;
    mat = res.y;
    if(d < 0.001 || t > 100.0) { break; }
    t += d;
  }
  return vec2<f32>(t, mat);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

  let mouse = u.zoom_config.yz;
  let time = u.config.x;

  let density = mix(4.0, 10.0, u.zoom_params.x);
  let pulseSpeed = u.zoom_params.y;
  let biomass = u.zoom_params.z;
  let morphSpeed = mix(0.1, 1.0, u.zoom_params.w);

  let yaw = (mouse.x - 0.5) * 6.28;
  let pitch = (mouse.y - 0.5) * 3.14;

  let cam_pos = vec3<f32>(0.0, 0.0, time * 2.0);
  let ro = cam_pos;

  let forward = normalize(vec3<f32>(sin(yaw), sin(pitch), cos(yaw)));
  let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
  let up = cross(forward, right);
  let rd = normalize(forward + right * uv.x + up * uv.y);

  // Animate 4D Julia constant
  let t = time * morphSpeed;
  let c = vec4<f32>(
    -0.2 + 0.1 * sin(t * 0.7),
    0.6 + 0.15 * cos(t * 0.5),
    0.1 * sin(t * 0.3),
    0.2 * cos(t * 0.4)
  );

  var res = raymarch(ro, rd, time, c, density, biomass, pulseSpeed);
  var t_dist = res.x;
  var mat = res.y;

  var color = vec3<f32>(0.0);
  var alpha = 1.0;
  let fogColor = vec3<f32>(0.01, 0.01, 0.02);

  if (t_dist < 100.0) {
    var p = ro + rd * t_dist;
    let n = calcNormal(p, time, c, density, biomass, pulseSpeed);
    let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));

    var pulse = sin(time * pulseSpeed * 5.0) * 0.5 + 0.5;
    var baseColor = vec3<f32>(0.1, 0.1, 0.15);

    let cell_size = 12.0 / density;
    let spacing = vec3<f32>(cell_size * 2.0, cell_size * 2.0, cell_size * 4.0);
    let local_p = (fract((p + spacing * 0.5) / spacing) - 0.5) * spacing;

    if (mat == 2.0) {
      // Julia core coloring
      let hue = f32(t_dist) * 0.05 + time * 0.05;
      baseColor = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
        0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
      );
      baseColor = baseColor * (1.0 + pulse * 0.5);
      baseColor += fbm(p * 5.0) * 0.2;
    } else {
      // Chitinous wall
      let refl = reflect(-rd, n);
      let spec = pow(max(dot(refl, lightDir), 0.0), 16.0);
      baseColor += vec3<f32>(1.0) * spec * 0.5;
      let rim = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
      baseColor += vec3<f32>(0.2, 0.3, 0.4) * rim;
    }

    let diff = max(dot(n, lightDir), 0.0);
    color = baseColor * (diff * 0.8 + 0.2);

    let fogAmount = 1.0 - exp(-t_dist * 0.05);
    color = mix(color, fogColor, fogAmount);

    alpha = select(0.75, 0.55 + pulse * 0.2, mat == 2.0);
    alpha = clamp(alpha, 0.35, 0.95);
  } else {
    color = fogColor;
  }

  textureStore(writeTexture, vec2<u32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(t_dist / 100.0, 0.0, 0.0, 0.0));
}
