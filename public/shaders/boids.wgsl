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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=unused, y=unused, z=unused, w=unused
  ripples: array<vec4<f32>, 50>,
};

const BOID_COUNT: u32 = 8192u;
const BOID_SPEED: f32 = 2.0;

@compute @workgroup_size(64, 1, 1)
fn update_boids(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= BOID_COUNT) { return; }
  let base = idx * 4u;
  let px = extraBuffer[base + 0u];
  let py = extraBuffer[base + 1u];
  var vx = extraBuffer[base + 2u];
  var vy = extraBuffer[base + 3u];
  let pos = vec2<f32>(px, py);
  let tex_size = vec2<f32>(textureDimensions(readTexture));
  let brightness = textureSampleLevel(readTexture, u_sampler, pos / tex_size, 0.0).r;
  let time = u.config.x;
  
  // Mouse position as attractor
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let to_mouse = mouse_pos - pos;
  let dist_to_mouse = length(to_mouse);
  if (dist_to_mouse > 0.01) {
    let mouse_force = normalize(to_mouse) * 0.05;
    vx += mouse_force.x;
    vy += mouse_force.y;
  }
  
  // Ripples as attractor seeds
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 4.0) {
        let to_ripple = ripple.xy - pos;
        let dist_to_ripple = length(to_ripple);
        if (dist_to_ripple > 0.01 && dist_to_ripple < 0.3) {
          let ripple_force = normalize(to_ripple) * 0.02 * (1.0 - ripple_age / 4.0);
          vx += ripple_force.x;
          vy += ripple_force.y;
        }
      }
    }
  }
  
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

fn reveal_texture_impl(gid: vec3<u32>) {
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

// Wrapper main entrypoint for host pipeline compatibility
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  reveal_texture_impl(gid);
}
