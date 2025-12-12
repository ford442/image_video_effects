// Physarum Polycephalum (Slime Mold) Texture Feeder - skeleton
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // trail_map
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // agent storage (encoded)
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>; // agents
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=unused, y=unused, z=unused, w=unused
  ripples: array<vec4<f32>, 50>,
};

// Minimal agent update: extraBuffer encodes packed agent state triples [x, y, angle]
@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx * 3u + 2u >= arrayLength(&extraBuffer)) { return; }
  let x = extraBuffer[idx * 3u + 0u];
  let y = extraBuffer[idx * 3u + 1u];
  var angle = extraBuffer[idx * 3u + 2u];
  let tex_size = vec2<f32>(textureDimensions(readTexture));
  let time = u.config.x;
  
  // Mouse position influence
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let to_mouse = mouse_pos - vec2<f32>(x, y);
  let dist_to_mouse = length(to_mouse);
  if (dist_to_mouse > 0.01 && dist_to_mouse < 0.3) {
    let mouse_angle = atan2(to_mouse.y, to_mouse.x);
    angle = mix(angle, mouse_angle, 0.1);
  }
  
  // Ripple-based spawning/biasing
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 2.0) {
        let dist_to_ripple = distance(vec2<f32>(x, y), ripple.xy);
        if (dist_to_ripple < 0.05) {
          angle += (ripple_age - 1.0) * 0.5;
        }
      }
    }
  }
  
  let dir = vec2<f32>(cos(angle), sin(angle));
  let sensor_pos = vec2<f32>(x, y) + dir * 5.0;
  let front_color = textureSampleLevel(readTexture, u_sampler, sensor_pos / tex_size, 0.0);
  // Simple steer: rotate a bit toward brighter color (red channel by default)
  let signal = front_color.r;
  angle = angle + (signal - 0.5) * 0.05;
  let new_pos = fract(vec2<f32>(x, y) + dir * 0.5);
  // deposit trail as inverse-color
  let coord = vec2<u32>(u32(new_pos.x * tex_size.x), u32(new_pos.y * tex_size.y));
  let current = textureLoad(dataTextureC, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  let inverse = vec4<f32>(1.0 - front_color.rgb, 1.0);
  let mixed = mix(current, inverse, 0.05);
  textureStore(dataTextureA, vec2<i32>(i32(coord.x), i32(coord.y)), mixed);
  // write back
  extraBuffer[idx * 3u + 0u] = new_pos.x;
  extraBuffer[idx * 3u + 1u] = new_pos.y;
  extraBuffer[idx * 3u + 2u] = angle;
  // Also write a pixel to output to preview
  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), mixed);
}
