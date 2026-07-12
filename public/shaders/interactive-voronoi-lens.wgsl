// ═══════════════════════════════════════════════════════════════════
//  Interactive Voronoi Lens
//  Category: distortion
//  Features: voronoi, lens, mouse-driven, audio-reactive,
//            depth-aware, temporal-feedback, semantic-alpha
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
const TAU: f32 = 6.28318530718;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    return mix(prev, bass, select(release, attack, bass > prev));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);
  let aspect = u.config.z / max(u.config.w, 0.001);
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);
  let isPress = u.zoom_config.w;

  let density = mix(5.0, 50.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let strength = clamp(u.zoom_params.y, 0.0, 1.0);
  let chaos = clamp(u.zoom_params.z, 0.0, 1.0);
  let curve = clamp(u.zoom_params.w, 0.0, 1.0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, coord, 0);
  let env = bass_env(prev.a, bass, 0.8, 0.15);

  let st = uv_corrected * density;
  let i_st = floor(st);
  let f_st = fract(st);

  var m_dist = 1.0;
  var m_point = vec2<f32>(0.0);
  var cell_id = vec2<f32>(0.0);
  var s_dist = 1.0;

  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      var point = hash22(i_st + neighbor);
      let jitter = 0.1 + env * 0.35 + chaos;
      point = 0.5 + 0.5 * sin(time * (1.0 + chaos * 2.0) * (1.0 + treble * 0.5) + TAU * point + neighbor * jitter);
      let diff = neighbor + point - f_st;
      let dist = length(diff);
      let nearer = dist < m_dist;
      s_dist = select(s_dist, smin(s_dist, dist, 0.3), !nearer && dist < s_dist);
      s_dist = select(s_dist, m_dist, nearer);
      m_dist = select(m_dist, dist, nearer);
      m_point = select(m_point, point, nearer);
      cell_id = select(cell_id, i_st + neighbor, nearer);
    }
  }

  let cell_center_corrected = (cell_id + m_point) / density;
  let cell_center_uv = vec2<f32>(cell_center_corrected.x / aspect, cell_center_corrected.y);

  let dist_to_mouse = length(uv_corrected - mouse_corrected);
  let mouse_influence = smoothstep(0.5, 0.0, dist_to_mouse) * (1.0 + isPress * 2.0);
  let final_strength = strength * (1.0 + mouse_influence * 2.0 + env * 0.6);

  var dir = uv - cell_center_uv;
  let dist_from_center = length(dir);
  let bulge = (1.0 - sin(dist_from_center * mix(1.0, 10.0, curve)));
  let cell_edge = clamp(s_dist - m_dist, 0.0, 1.0);

  let offset = dir * bulge * final_strength * 0.5;
  let final_uv = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));

  var color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let neon = vec3<f32>(0.15, 0.35, 0.6) * cell_edge * (0.5 + mids * 0.6);
  color += neon * strength;

  let fog = 1.0 - exp(-depth * 1.8);
  color = mix(color, color * 0.7, fog * 0.4);

  let trail = mix(prev.rgb * 0.96, color, 0.12 + mouse_influence * 0.12);
  color = mix(color, trail, 0.25);
  color = acesToneMap(color * (0.9 + env * 0.2));

  let alpha = clamp(0.35 + cell_edge * 0.45 + mouse_influence * 0.25, 0.0, 0.95);
  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(trail, env));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
