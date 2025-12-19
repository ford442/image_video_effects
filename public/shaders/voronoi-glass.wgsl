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
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Hash function for randomness
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Params
  let cell_density = 5.0 + u.zoom_params.x * 20.0;
  let refraction_strength = u.zoom_params.y * 0.1;
  let border_width = u.zoom_params.z * 0.1;
  let mouse_attraction = u.zoom_params.w;

  let aspect = resolution.x / resolution.y;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);

  // Voronoi
  let i_st = floor(uv_corrected * cell_density);
  let f_st = fract(uv_corrected * cell_density);

  var m_dist = 1.0;  // Minimal distance
  var m_point = vec2<f32>(0.0); // Minimal point position relative to grid

  // Iterate through neighbors
  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      var point = hash22(i_st + neighbor);

      // Animate point
      point = 0.5 + 0.5 * sin(time + 6.2831 * point);

      // Mouse attraction
      let mousePos = u.zoom_config.yz;
      let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);
      let cell_world_pos = (i_st + neighbor + point) / cell_density;
      let dist_mouse = distance(cell_world_pos, mouse_corrected);

      if (dist_mouse < 0.3) {
          // Pull point towards mouse
          let pull = (1.0 - dist_mouse / 0.3) * mouse_attraction;
          let dir = normalize(mouse_corrected - cell_world_pos);
          // We can't easily move the point outside its grid cell without artifacts in standard voronoi
          // but we can bias the animation phase
          point = mix(point, point + dir * pull, 0.5);
      }

      let diff = neighbor + point - f_st;
      let dist = length(diff);

      if (dist < m_dist) {
        m_dist = dist;
        m_point = point;
      }
    }
  }

  // Calculate borders
  // We need second closest distance for borders, but simpler is to use m_dist directly
  // Refraction: sample texture based on the cell center or normal

  // Approximating a normal based on distance from center of cell
  let normal = normalize(vec3<f32>(m_point - f_st, m_dist));

  let refract_uv = uv + normal.xy * refraction_strength;

  var color = textureSampleLevel(readTexture, u_sampler, refract_uv, 0.0).rgb;

  // Draw borders
  // A simple border can be made by checking if m_dist is close to the neighbor's distance,
  // but since we only tracked the closest, we can just use m_dist edge
  // Better approach for borders in 1-pass Voronoi is tricky without 2nd closest.
  // Instead, let's use the distance field to darken edges slightly (glass bevel effect)

  let bevel = smoothstep(0.0, border_width, m_dist) * smoothstep(1.0, 1.0 - border_width, m_dist);
  // Actually, Voronoi cells are convex. m_dist goes from 0 (center) to ~0.5-0.7 (edge).
  // Let's highlight the center (specular) and darken the edge.

  color += vec3<f32>(0.1) * (1.0 - m_dist); // Center glow
  color -= vec3<f32>(0.2) * smoothstep(0.4, 0.5, m_dist); // Edge darken

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
