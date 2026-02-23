// ═══════════════════════════════════════════════════════════════
//  Crystal Caverns - Infinite glowing crystal cave system
//  Category: generative
//  Description: An infinite, procedural cave system illuminated by 
//               clusters of glowing crystals. Mouse-controlled light.
//  Features: mouse-driven
//  Tags: crystal, cave, 3d, raymarching, fantasy, glowing
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

fn sdSphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let q = abs(p) - b; return length(max(q, vec3<f32>(0.0))) + min(max(q.x,max(q.y,q.z)), 0.0);
}

fn map(p: vec3<f32>, scale: f32, pulse: f32, time: f32) -> vec2<f32> {
  let ps = p * scale;
  var d = ps.y + 1.5;
  d = min(d, length(ps.xz) - 12.0 + sin(ps.y * 2.0) * 0.8);

  let cell = floor(ps * 0.8);
  var q = ps - cell * 1.25;
  let crystal = sdSphere(q + vec3<f32>(0.0, sin(time * pulse * 8.0 + length(cell)) * 0.3, 0.0), 0.4);

  let id = (cell.x + cell.y + cell.z) % 3.0;
  let finalD = min(d, crystal * (1.0 + id * 0.2));

  return vec2<f32>(finalD, 2.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let res = u.config.zw;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  
  if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

  var uv = (vec2<f32>(id.xy) / res - 0.5) * vec2<f32>(res.x / res.y, 1.0) * u.zoom_config.z;

  let scale = u.zoom_params.x * 1.9 + 0.1;
  let glowIntensity = u.zoom_params.z * 2.0;
  let pulse = u.zoom_params.w;

  let mouseAngle = mouse.x * 6.28;
  var ro = vec3<f32>(sin(mouseAngle) * 10.0, 3.0, cos(mouseAngle) * 10.0);
  let lookAt = vec3<f32>(0.0, 0.0, 0.0);
  let fwd = normalize(lookAt - ro);
  let right = normalize(cross(vec3<f32>(0.0,1.0,0.0), fwd));
  let up = cross(fwd, right);
  let rd = normalize(fwd + uv.x * right + uv.y * up);

  var t = 0.0;
  var mat = 0.0;
  for (var i: i32 = 0; i < 100; i++) {
    let p = ro + rd * t;
    let r = map(p, scale, pulse, time);
    if (r.x < 0.001) { mat = r.y; break; }
    t += r.x * 0.9;
    if (t > 80.0) { break; }
  }

  var col = vec3<f32>(0.01, 0.005, 0.03);

  if (t < 79.0) {
    let p = ro + rd * t;
    if (mat > 1.5) {
      let glow = pow(glowIntensity * 1.5 + sin(time * 8.0) * pulse * 0.3, 2.0);
      col = vec3<f32>(0.4, 0.8, 1.0) * glow + vec3<f32>(0.6, 0.3, 1.0) * 0.6;
    } else {
      col = vec3<f32>(0.15, 0.1, 0.08);
    }
  }

  let mouseLight = max(0.0, 1.0 - length(uv - mouse) * 3.0);
  col += vec3<f32>(0.8, 0.6, 1.0) * mouseLight * 0.8;

  textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
  
  var depth = 0.5;
  if (t < 79.0) {
    depth = 1.0 - (t / 80.0);
  }
  textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
