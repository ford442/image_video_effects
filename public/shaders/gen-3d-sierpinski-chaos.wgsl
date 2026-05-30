// ═══════════════════════════════════════════════════════════════════
//  3D Sierpinski Chaos Game
//  Category: generative
//  Features: sierpinski, chaos-game, 3d-fractal, audio-reactive, mouse-interactive, semantic-alpha
//  Complexity: Medium-High
//  Created: 2026-05-31
//  Updated: 2026-06-01
//  By: Kimi Agent (Bright batch)
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

const PI: f32 = 3.14159265359;

// Hash function for deterministic randomness
fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn hash2f(n: f32) -> vec2<f32> {
  return vec2<f32>(hashf(n), hashf(n + 73.156));
}

// 3D rotation around X axis
fn rotX(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a);
  let s = sin(a);
  return vec3<f32>(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}

// 3D rotation around Y axis
fn rotY(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a);
  let s = sin(a);
  return vec3<f32>(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let p1 = u.zoom_params.x; // intensity (point density)
  let p2 = u.zoom_params.y; // speed (rotation speed)
  let p3 = u.zoom_params.z; // scale (point size)
  let p4 = u.zoom_params.w; // color shift

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let audioSpeed = p2 * (0.9 + bass * 0.5);
  let audioIntensity = p1 * (0.85 + treble * 0.6);
  let audioColor = p4 + mids * 0.2;

  // Rotation angles from mouse or auto-rotate
  var rot_yaw: f32;
  var rot_pitch: f32;
  if mouseDown {
    rot_yaw = (mouse.x - 0.5) * PI * 2.0;
    rot_pitch = (mouse.y - 0.5) * PI * 0.8;
  } else {
    rot_yaw = time * audioSpeed * 0.3;
    rot_pitch = sin(time * audioSpeed * 0.2) * 0.4;
  }

  // Sierpinski tetrahedron vertices
  let vertices = array<vec3<f32>, 4>(
    vec3<f32>(0.0, 1.0, 0.0),
    vec3<f32>(-0.816, -0.333, 0.577),
    vec3<f32>(0.816, -0.333, 0.577),
    vec3<f32>(0.0, -0.333, -1.155)
  );

  // Pixel seed for deterministic sampling
  let pixel_seed = f32(pixel.x) * 137.0 + f32(pixel.y) * 241.0;
  let num_points = i32(50.0 + p1 * 400.0);

  // Chaos game starting point
  var point = vec3<f32>(
    hashf(pixel_seed) * 2.0 - 1.0,
    hashf(pixel_seed + 1.0) * 2.0 - 1.0,
    hashf(pixel_seed + 2.0) * 2.0 - 1.0
  );

  // Skip first 20 iterations to converge
  for (var i = 0; i < 20; i++) {
    let vi = i32(hashf(pixel_seed + f32(i) * 17.3) * 4.0);
    point = (point + vertices[vi]) * 0.5;
  }

  // Accumulate projected points
  var acc = vec3<f32>(0.0);
  var depth_acc = 0.0;
  var count = 0.0;

  let point_radius = 0.001 + p3 * 0.005;

  for (var i = 0; i < num_points; i++) {
    // Chaos game step
    let vi = i32(hashf(pixel_seed + f32(i + 20) * 37.7) * 4.0);
    point = (point + vertices[vi]) * 0.5;

    // Rotate and project
    var rp = rotY(rotX(point, rot_pitch), rot_yaw);

    // Perspective projection
    let proj_z = 2.5 + rp.z;
    if proj_z < 0.1 { continue; }
    let proj = vec2<f32>(rp.x / proj_z, rp.y / proj_z);

    // Check if this point contributes to current pixel
    let diff = uv - proj;
    let dist_sq = dot(diff, diff);
    if dist_sq < point_radius {
      // Point contributes - depth-weighted
      let depth_weight = 1.0 / proj_z;
      let influence = 1.0 - dist_sq / point_radius;

      // Color by vertex and depth
      let color_idx = f32(vi) * 0.25 + p4;
      let hue = color_idx + rp.y * 0.3;
      let sat = 0.7 + influence * 0.3;
      let val = depth_weight * (0.6 + influence * 0.4);

      let h = fract(hue) * 6.0;
      let c_val = val * sat;
      let x = c_val * (1.0 - abs(fract(h / 2.0) * 2.0 - 1.0));
      let m = val - c_val;

      var rgb: vec3<f32>;
      if h < 1.0 { rgb = vec3<f32>(c_val, x, 0.0); }
      else if h < 2.0 { rgb = vec3<f32>(x, c_val, 0.0); }
      else if h < 3.0 { rgb = vec3<f32>(0.0, c_val, x); }
      else if h < 4.0 { rgb = vec3<f32>(0.0, x, c_val); }
      else if h < 5.0 { rgb = vec3<f32>(x, 0.0, c_val); }
      else { rgb = vec3<f32>(c_val, 0.0, x); }
      rgb += vec3<f32>(m);

      acc += rgb * influence;
      depth_acc += depth_weight * influence;
      count += influence;
    }
  }

  var color: vec3<f32>;
  if count > 0.05 {
    color = acc / count;
    // Add ambient glow
    color += vec3<f32>(0.04, 0.05, 0.08) * depth_acc * 0.5;
  } else {
    // Background
    let bg_grad = length(uv) * 0.3;
    color = vec3<f32>(0.02, 0.02, 0.03) * (1.0 - bg_grad);
  }

  // Semantic alpha based on density
  let effect = clamp(count * 0.8, 0.4, 0.95);
  textureStore(writeTexture, pixel, vec4<f32>(color, effect));
}
