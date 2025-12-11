// Boids Swarm Masking - simplified compute skeleton
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
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>; // boid array
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=zoomTime, y=mouseX, z=mouseY, w=unused
  zoom_params: vec4<f32>,  // x=param1, y=param2, z=param3, w=param4
  ripples: array<vec4<f32>, 50>,
};

const BOID_COUNT: u32 = 8192u;
const BOID_SPEED: f32 = 2.0;

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= BOID_COUNT) { return; }
  let base = idx * 4u;
  let px = extraBuffer[base + 0u];
  let py = extraBuffer[base + 1u];
  var vx = extraBuffer[base + 2u];
  var vy = extraBuffer[base + 3u];
  let pos = vec2<f32>(px, py);
  let dim_i = textureDimensions(readTexture);
  let tex_size = vec2<f32>(f32(dim_i.x), f32(dim_i.y));
  let brightness = textureSampleLevel(readTexture, u_sampler, pos / tex_size, 0.0).r;
  let attraction = vec2<f32>(0.0);
  // simple move towards brighter areas
  if (brightness > 0.5) { vx += 0.01; vy += 0.01; }
  var vel = normalize(vec2<f32>(vx, vy)) * BOID_SPEED;
  var new_pos = pos + vel;
  new_pos = fract(new_pos);
  extraBuffer[base + 0u] = new_pos.x;
  extraBuffer[base + 1u] = new_pos.y;
  extraBuffer[base + 2u] = vel.x;
  extraBuffer[base + 3u] = vel.y;
}

@compute @workgroup_size(8, 8, 1)
fn reveal_texture(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  let dim = textureDimensions(readTexture);
  var revealed = vec4<f32>(0.0);
  // sample a portion of boids for demo reveal
  for (var i: u32 = 0u; i < 1024u; i = i + 1u) {
    let base = i * 4u;
    let bx = extraBuffer[base + 0u] * f32(dim.x);
    let by = extraBuffer[base + 1u] * f32(dim.y);
    if (distance(vec2<f32>(f32(coord.x), f32(coord.y)), vec2<f32>(bx, by)) < 3.0) {
      revealed = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
      break;
    }
  }
  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), revealed);
}

// (No extra wrapper — `main` performs the update pass)
