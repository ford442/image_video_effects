struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(
    v.x * c - v.y * s,
    v.x * s + v.y * c
  );
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);
  let aspect = u.config.z / u.config.w;

  // Params
  let rot_speed = u.zoom_params.x * 3.14159; // Rotation range
  let scale_base = mix(0.9, 1.3, u.zoom_params.y); // Scale
  let refract_str = mix(0.0, 0.05, u.zoom_params.z);
  let aberration = u.zoom_params.w * 0.1;

  let mouse = u.zoom_config.yz;

  // To handle non-square aspect ratio properly during rotation, we should correct UVs
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let mouse_p = (mouse - 0.5) * vec2<f32>(aspect, 1.0);

  // Accumulate displacement
  var total_disp = vec2<f32>(0.0);

  // We act as if we are tracing a ray through layers of glass
  var curr_p = p;

  // Number of iterations acts as layers
  for (var i = 0; i < 4; i++) {
    // Offset relative to mouse (interactive center)
    // We want the recursion to be relative to the mouse position
    // effectively creating a "portal" or "lens" at the mouse.

    // Shift origin to mouse for rotation
    let rel_p = curr_p - mouse_p;

    let angle = rot_speed * (f32(i) + 1.0) * 0.3;
    let rotated = rotate(rel_p, angle);

    // Add some sine distortion based on position
    let sine_warp = vec2<f32>(
        sin(rotated.y * 10.0 + u.config.x),
        cos(rotated.x * 10.0 + u.config.x)
    );

    total_disp = total_disp + sine_warp * refract_str / (f32(i) + 1.0);

    // Prepare for next iteration: Scale up
    curr_p = rotated * scale_base + mouse_p;
  }

  // Final UV lookup
  // We apply the accumulated displacement to the original UV
  // Correct back to UV space
  let final_p = p + total_disp;
  let final_uv = final_p / vec2<f32>(aspect, 1.0) + 0.5;

  // Chromatic Aberration
  // Sample R, G, B at different scales of displacement
  let r_uv = (p + total_disp * (1.0 + aberration)) / vec2<f32>(aspect, 1.0) + 0.5;
  let b_uv = (p + total_disp * (1.0 - aberration)) / vec2<f32>(aspect, 1.0) + 0.5;

  let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

  // Bounds check (optional, clamping usually handled by sampler but good to be safe for style)
  // Mirror repeat mode is usually default or Clamp.

  textureStore(writeTexture, coord, vec4<f32>(r, g, b, 1.0));
}
