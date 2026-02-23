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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);
  let aspect = u.config.z / u.config.w;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);

  let mouse = u.zoom_config.yz;
  let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);

  // Params
  let density = mix(5.0, 50.0, u.zoom_params.x);
  let strength = u.zoom_params.y;
  let chaos = u.zoom_params.z;

  // Voronoi
  let st = uv_corrected * density;
  let i_st = floor(st);
  let f_st = fract(st);

  var m_dist = 1.0;  // Minimum distance
  var m_point = vec2<f32>(0.0); // Minimum point (relative)
  var cell_id = vec2<f32>(0.0); // Global cell ID

  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      var point = hash22(i_st + neighbor);

      // Animate point
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

  // Calculate center of the closest cell in UV space
  // cell_id + m_point is the position in "grid" space
  // Divide by density to get back to UV space (corrected)
  let cell_center_corrected = (cell_id + m_point) / density;
  let cell_center_uv = vec2<f32>(cell_center_corrected.x / aspect, cell_center_corrected.y);

  // Mouse Interaction: Modulate lens strength based on distance to mouse
  let dist_to_mouse = length(uv_corrected - mouse_corrected);
  let mouse_influence = smoothstep(0.5, 0.0, dist_to_mouse); // stronger near mouse

  let final_strength = strength * (1.0 + mouse_influence * 2.0); // Boost strength near mouse

  // Lens distortion: displace UV towards/away from cell center
  // Vector from center to current pixel
  let dir = uv - cell_center_uv;

  // Fisheye: displacement is non-linear with distance from center
  // Simple bulge:
  let dist_from_center = length(dir);
  let bulge = (1.0 - sin(dist_from_center * 3.1415)); // 1 at center, 0 at edge roughly

  let offset = dir * bulge * final_strength * 0.5;

  let final_uv = uv - offset;

  // Sample texture
  let color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0);

  // Add borders
  // let border = smoothstep(0.0, 0.1, m_dist);
  // let final_color = color * border;

  textureStore(writeTexture, coord, color);

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
