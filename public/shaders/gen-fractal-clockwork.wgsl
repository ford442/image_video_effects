// ═══════════════════════════════════════════════════════════════
//  Fractal Clockwork - Infinite steampunk gear field
//  Category: generative
//  Description: Infinite interlocking brass gears rotating in perfect mechanical sync.
//               Steampunk raymarched masterpiece with metallic PBR shading.
//  Features: mouse-driven, temporal, chromatic, depth-aware
//  Tags: steampunk, mechanical, 3d, raymarching, gears
//  Author: ford442
//  Upgraded: 2026-08-03 (Batch 33)
// ═══════════════════════════════════════════════════════════════

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

fn rot2D(a: f32) -> mat2x2<f32> {
  let c = cos(a); let s = sin(a); return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sdGear(p: vec3<f32>, radius: f32, teeth: f32, thickness: f32, time: f32) -> f32 {
  let r = length(p.xz);
  let a = atan2(p.z, p.x) + time;
  let tooth = 0.05 * radius * smoothstep(-0.5, 0.5, sin(a * teeth * 2.0));
  let d_cyl = r - (radius + tooth);
  let d_height = abs(p.y) - thickness;
  let d_axle = r - radius * 0.25;
  let gear = max(d_cyl, d_height);
  return max(gear, -d_axle);
}

fn map(p: vec3<f32>, gearScale: f32, teeth: f32, speed: f32, time: f32, audioReactivity: f32) -> f32 {
  let spacing = 5.0 * gearScale;
  var q = p;
  let cell = floor((p.xz + spacing * 0.5) / spacing);
  q.x = (fract((p.x + spacing * 0.5) / spacing) - 0.5) * spacing;
  q.z = (fract((p.z + spacing * 0.5) / spacing) - 0.5) * spacing;

  let parity = abs(i32(cell.x) + i32(cell.y)) % 2;
  let dir = select(-1.0, 1.0, parity == 0);
  let t = time * speed * audioReactivity * dir * 2.0;

  var d = sdGear(q, 1.8, teeth, 0.25, t);
  let floorD = p.y + 1.2;
  return min(d, floorD);
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, gearScale: f32, teeth: f32, speed: f32, time: f32, audioReactivity: f32) -> f32 {
  var t = 0.0;
  for (var i: i32 = 0; i < 96; i++) {
    var p = ro + rd * t;
    var d = map(p, gearScale, teeth, speed, time, audioReactivity);
    if (d < 0.001 || t > 80.0) { break; }
    t += max(d * 0.8, 0.002);
  }
  return t;
}

fn shade(p: vec3<f32>, n: vec3<f32>, ro: vec3<f32>, material: f32) -> vec3<f32> {
  let light = normalize(vec3<f32>(1.0, 2.0, 1.0));
  let diff = max(dot(n, light), 0.0);
  let spec = pow(max(dot(reflect(normalize(p - ro), n), light), 0.0), 32.0);

  var col = vec3<f32>(0.8, 0.6, 0.3);
  if (material > 0.5) { col = vec3<f32>(0.9, 0.9, 0.95); }
  if (material > 1.5) { col = vec3<f32>(1.0, 0.85, 0.4); }

  return col * (0.25 + diff * 0.7 + spec * 1.8);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let res = u.config.zw;
  let time = u.config.x;
  // ═══ AUDIO REACTIVITY ═══
  let audioOverall = plasmaBuffer[0].x;
  let audioBass = plasmaBuffer[0].x * 1.2;
  let audioMid = plasmaBuffer[0].y;
  let audioHigh = plasmaBuffer[0].z;
  let audioReactivity = 1.0 + audioOverall * 0.5;
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  
  if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

  var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  if (extraBuffer[137] < 0.5) { mouse = rawMouse; mouseVelocity = vec2<f32>(0.0); }
  let springDt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
  let springOmega = 7.0;
  mouseVelocity += ((rawMouse - mouse) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
  mouse += mouseVelocity * springDt;
  if (id.x == 0u && id.y == 0u && arrayLength(&extraBuffer) > 138u) {
    extraBuffer[133] = mouse.x; extraBuffer[134] = mouse.y;
    extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
    extraBuffer[137] = 1.0; extraBuffer[138] = time;
  }

  // Standard UV calculation
  var uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;
  let uv01 = (vec2<f32>(id.xy) + vec2<f32>(0.5)) / res;

  let gearScale = u.zoom_params.x * 1.5 + 0.5;
  let teeth = mix(6.0, 24.0, u.zoom_params.y);
  var clickTorque = 0.0;
  let aspect = res.x / res.y;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.2) {
      let radius = length((uv01 - ripple.xy) * vec2<f32>(aspect, 1.0));
      clickTorque = max(clickTorque, exp(-abs(radius - age * 0.2) * 55.0) * exp(-age * 1.4));
    }
  }
  let speed = u.zoom_params.z * 5.0 * (1.0 + clickTorque * 1.5);
  let material = u.zoom_params.w * 2.0;

  // Orbit camera logic
  let yaw = mouse.x * 6.28;
  let height = mouse.y * 14.0 + 1.0;
  let dist = 12.0;

  var ro = vec3<f32>(sin(yaw) * dist, height, cos(yaw) * dist);
  let lookAt = vec3<f32>(0.0, 0.0, 0.0);
  let fwd = normalize(lookAt - ro);
  let right = normalize(cross(vec3<f32>(0.0,1.0,0.0), fwd));
  let up = cross(fwd, right);
  let rd = normalize(fwd + uv.x * right + uv.y * up);

  var t = raymarch(ro, rd, gearScale, teeth, speed, time, audioReactivity);
  var col = vec3<f32>(0.02, 0.01, 0.005);

  if (t < 79.9) {
    var p = ro + rd * t;
    let eps = 0.001;
    let n = normalize(vec3<f32>(
      map(p + vec3<f32>(eps,0.0,0.0), gearScale, teeth, speed, time, audioReactivity) - map(p - vec3<f32>(eps,0.0,0.0), gearScale, teeth, speed, time, audioReactivity),
      map(p + vec3<f32>(0.0,eps,0.0), gearScale, teeth, speed, time, audioReactivity) - map(p - vec3<f32>(0.0,eps,0.0), gearScale, teeth, speed, time, audioReactivity),
      map(p + vec3<f32>(0.0,0.0,eps), gearScale, teeth, speed, time, audioReactivity) - map(p - vec3<f32>(0.0,0.0,eps), gearScale, teeth, speed, time, audioReactivity)
    ));
    col = shade(p, n, ro, material);

    // ═══ Chromatic dispersion: per-channel spatial offsets on gear surface ═══
    let chromAmt = 0.015 + audioBass * 0.02;
    col.r = col.r + sin(p.x * 25.0 + time * 2.0) * chromAmt * audioBass;
    col.g = col.g + cos(p.z * 20.0 + time * 1.7) * chromAmt * audioMid;
    col.b = col.b + sin((p.x + p.z) * 18.0 + time * 1.3) * chromAmt * audioHigh;
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
  }

  // ═══ Temporal feedback ═══
  let prev = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);
  col = mix(col, prev.rgb * 0.9, clamp(0.03 + audioBass * 0.01, 0.0, 0.08));
  col += vec3<f32>(1.0, 0.55, 0.16) * clickTorque * (0.25 + audioHigh * 0.2);
  col = acesToneMap(max(col, vec3<f32>(0.0)) * (1.0 + audioMid * 0.12));

  let hit = t < 79.9;
  let alpha = clamp(select(0.0, 0.62 + clickTorque * 0.2, hit) + dot(col, vec3<f32>(0.2126, 0.7152, 0.0722)) * 0.25, 0.0, 0.96);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  textureStore(dataTextureA, id.xy, vec4<f32>(col, alpha));
  
  var depth = 0.0;
  if (hit) { depth = clamp(1.0 - t / 80.0, 0.0, 1.0); }
  textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
