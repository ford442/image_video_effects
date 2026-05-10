// ═══════════════════════════════════════════════════════════════════
//  Fractal Glass Distort
//  Category: distortion
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Chunks From: (original effect)
//  Created: 2026-05-10
//  By: Phase A Upgrade Swarm
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=RotSpeed, y=Scale, z=RefractStr, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 0.001);
  let bass = plasmaBuffer[0].x;

  let rot_speed = u.zoom_params.x * 3.14159;
  let scale_base = mix(0.9, 1.3, clamp(u.zoom_params.y, 0.0, 1.0));
  let refract_str = mix(0.0, 0.05, clamp(u.zoom_params.z, 0.0, 1.0)) * (1.0 + bass * 0.3);
  let aberration = u.zoom_params.w * 0.1;

  var mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));

  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let mouse_p = (mouse - 0.5) * vec2<f32>(aspect, 1.0);

  var total_disp = vec2<f32>(0.0);
  var curr_p = p;

  for (var i = 0; i < 4; i++) {
    let rel_p = curr_p - mouse_p;
    let angle = rot_speed * (f32(i) + 1.0) * 0.3;
    let rotated = rotate(rel_p, angle);

    let sine_warp = vec2<f32>(
        sin(rotated.y * 10.0 + u.config.x),
        cos(rotated.x * 10.0 + u.config.x)
    );

    total_disp = total_disp + sine_warp * refract_str / max(f32(i) + 1.0, 0.001);
    curr_p = rotated * scale_base + mouse_p;
  }

  let final_p = p + total_disp;
  let final_uv = clamp(final_p / vec2<f32>(aspect, 1.0) + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));

  let r_uv = clamp((p + total_disp * (1.0 + aberration)) / vec2<f32>(aspect, 1.0) + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  let b_uv = clamp((p + total_disp * (1.0 - aberration)) / vec2<f32>(aspect, 1.0) + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));

  let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

  let color = vec3<f32>(r, g, b);

  // Alpha: refraction displacement magnitude drives glass distortion blend weight
  let dispMag = length(total_disp);
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(dispMag * 12.0 + luma * 0.2 + 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
