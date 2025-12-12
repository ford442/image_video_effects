// Neon Edge Diffusion - compute skeleton
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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=unused, y=unused, z=unused, w=unused
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn edge_diffusion(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let dim = textureDimensions(readTexture);
  let uv = vec2<f32>(f32(gid.x), f32(gid.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  let time = u.config.x;
  
  let center = textureLoad(readTexture, coord, 0).rgb;
  let left = textureLoad(readTexture, coord + vec2<i32>(-1, 0), 0).rgb;
  let right = textureLoad(readTexture, coord + vec2<i32>(1, 0), 0).rgb;
  let top = textureLoad(readTexture, coord + vec2<i32>(0, -1), 0).rgb;
  let bottom = textureLoad(readTexture, coord + vec2<i32>(0, 1), 0).rgb;
  let gx = length(right - left);
  let gy = length(bottom - top);
  var edge = sqrt(gx*gx + gy*gy);
  
  // Mouse as local diffusion amplifier
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let dist_to_mouse = distance(uv, mouse_pos);
  if (dist_to_mouse < 0.2) {
    edge *= 1.0 + (1.0 - dist_to_mouse / 0.2) * 2.0;
  }
  
  let light = vec4<f32>(edge * 10.0);
  textureStore(dataTextureA, coord, light);
}

fn diffuse_light_impl(gid: vec3<u32>) {
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let dim = textureDimensions(dataTextureA);
  let uv = vec2<f32>(f32(gid.x), f32(gid.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  let time = u.config.x;
  
  let center = textureLoad(dataTextureC, coord, 0).r;
  let left = textureLoad(dataTextureC, coord + vec2<i32>(-1,0), 0).r;
  let right = textureLoad(dataTextureC, coord + vec2<i32>(1,0), 0).r;
  let top = textureLoad(dataTextureC, coord + vec2<i32>(0,-1), 0).r;
  let bottom = textureLoad(dataTextureC, coord + vec2<i32>(0,1), 0).r;
  var diffused = (center + left + right + top + bottom) * 0.2;
  
  // Ripples create neon pulses at click positions
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 2.0) {
        let dist_to_ripple = distance(uv, ripple.xy);
        if (dist_to_ripple < 0.1) {
          let pulse = sin(dist_to_ripple * 50.0 - ripple_age * 10.0) * exp(-ripple_age);
          diffused += pulse * 2.0;
        }
      }
    }
  }
  
  let shift = diffused * 0.1;
  let color = vec3<f32>(diffused * (1.0 - shift), diffused * (1.0 - abs(shift - 0.5)), diffused * shift);
  textureStore(dataTextureB, coord, vec4<f32>(color, 1.0));
  textureStore(writeTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(color, 1.0));
}
// Main entrypoint for Neon Edge Diffusion - run diffuse_light pass
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  diffuse_light_impl(gid);
}
