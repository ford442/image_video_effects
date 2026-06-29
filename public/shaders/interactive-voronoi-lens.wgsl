// ═══════════════════════════════════════════════════════════════════
//  Interactive Voronoi Lens
//  Category: distortion
//  Features: voronoi, lens, mouse-driven, upgraded-rgba
// ═══════════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / vec2<f32>(dims);
  let aspect = u.config.z / max(u.config.w, 0.001);
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);

  var mouse = u.zoom_config.yz;
  let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);

  // Params (all normalized before use)
  let density = mix(5.0, 50.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let strength = mix(0.0, 1.0, clamp(u.zoom_params.y, 0.0, 1.0));
  let chaos = mix(0.0, 1.0, clamp(u.zoom_params.z, 0.0, 1.0));

  // Voronoi
  let st = uv_corrected * density;
  let i_st = floor(st);
  let f_st = fract(st);

  var m_dist = 1.0;
  var m_point = vec2<f32>(0.0);
  var cell_id = vec2<f32>(0.0);

  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      var point = hash22(i_st + neighbor);

      point = 0.5 + 0.5 * sin(u.config.x * chaos + 6.2831 * point);

      let diff = neighbor + point - f_st;
      let dist = length(diff);

      if (dist < m_dist) {
        m_dist = dist;
        m_point = point;
        cell_id = i_st + neighbor;
      }
    }
  }

  let cell_center_corrected = (cell_id + m_point) / density;
  let cell_center_uv = vec2<f32>(cell_center_corrected.x / aspect, cell_center_corrected.y);

  let dist_to_mouse = length(uv_corrected - mouse_corrected);
  let mouse_influence = smoothstep(0.5, 0.0, dist_to_mouse);

  let final_strength = strength * (1.0 + mouse_influence * 2.0);

  var dir = uv - cell_center_uv;

  let dist_from_center = length(dir);
  let bulge = (1.0 - sin(dist_from_center * mix(1.0, 10.0, clamp(u.zoom_params.w, 0.0, 1.0))));

  let offset = dir * bulge * final_strength * 0.5;

  let final_uv = uv - offset;

  let color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0);

  textureStore(writeTexture, coord, color);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
