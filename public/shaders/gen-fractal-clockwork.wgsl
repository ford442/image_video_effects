// ═══════════════════════════════════════════════════════════════
//  Fractal Clockwork - Infinite steampunk gear field
//  Category: generative
//  Description: Infinite interlocking brass gears rotating in perfect mechanical sync.
//               Steampunk raymarched masterpiece with metallic PBR shading.
//  Features: mouse-driven
//  Tags: steampunk, mechanical, 3d, raymarching, gears
//  Author: ford442
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

fn map(p: vec3<f32>, gearScale: f32, teeth: f32, speed: f32, time: f32) -> f32 {
  let spacing = 5.0 * gearScale;
  var q = p;
  let cell = floor((p.xz + spacing * 0.5) / spacing);
  q.x = (fract((p.x + spacing * 0.5) / spacing) - 0.5) * spacing;
  q.z = (fract((p.z + spacing * 0.5) / spacing) - 0.5) * spacing;

  let dir = ((cell.x + cell.y) % 2.0) * 2.0 - 1.0;
  let t = time * speed * dir * 2.0;

  let d = sdGear(q, 1.8, teeth, 0.25, t);
  let floorD = p.y + 1.2;
  return min(d, floorD);
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, gearScale: f32, teeth: f32, speed: f32, time: f32) -> f32 {
  var t = 0.0;
  for (var i: i32 = 0; i < 120; i++) {
    let p = ro + rd * t;
    let d = map(p, gearScale, teeth, speed, time);
    if (d < 0.001 || t > 200.0) { break; }
    t += d * 0.8;
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let res = u.config.zw;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  
  if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

  // Standard UV calculation
  let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;

  let gearScale = u.zoom_params.x * 1.5 + 0.5;
  let teeth = mix(6.0, 24.0, u.zoom_params.y);
  let speed = u.zoom_params.z * 5.0;
  let material = u.zoom_params.w * 2.0;

  // Orbit camera logic
  let yaw = mouse.x * 6.28;
  let height = mouse.y * 14.0 + 1.0; // Height control
  let dist = 12.0;

  var ro = vec3<f32>(sin(yaw) * dist, height, cos(yaw) * dist);
  let lookAt = vec3<f32>(0.0, 0.0, 0.0);
  let fwd = normalize(lookAt - ro);
  let right = normalize(cross(vec3<f32>(0.0,1.0,0.0), fwd));
  let up = cross(fwd, right);
  let rd = normalize(fwd + uv.x * right + uv.y * up);

  let t = raymarch(ro, rd, gearScale, teeth, speed, time);
  var col = vec3<f32>(0.02, 0.01, 0.005);

  if (t < 199.0) {
    let p = ro + rd * t;
    let eps = 0.001;
    let n = normalize(vec3<f32>(
      map(p + vec3<f32>(eps,0.0,0.0), gearScale, teeth, speed, time) - map(p - vec3<f32>(eps,0.0,0.0), gearScale, teeth, speed, time),
      map(p + vec3<f32>(0.0,eps,0.0), gearScale, teeth, speed, time) - map(p - vec3<f32>(0.0,eps,0.0), gearScale, teeth, speed, time),
      map(p + vec3<f32>(0.0,0.0,eps), gearScale, teeth, speed, time) - map(p - vec3<f32>(0.0,0.0,eps), gearScale, teeth, speed, time)
    ));
    col = shade(p, n, ro, material);
  }

  textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
  
  var depth = 0.5;
  if (t < 199.0) {
    depth = 1.0 - (t / 200.0);
  }
  textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
