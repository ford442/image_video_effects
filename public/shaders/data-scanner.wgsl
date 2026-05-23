// ═══════════════════════════════════════════════════════════════════
//  Data Scanner
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: data-scanner (original)
//  Created: 2026-05-17
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PHI = 1.61803398874989484820;

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return fract(sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453123);
}

fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
             mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var a = 0.5; var s = 0.0; var q = p;
  for (var i = 0; i < 4; i = i + 1) { s = s + a * vnoise(q); q = q * PHI; a = a * 0.5; }
  return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
  let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
  return fbm(p + 4.0 * q);
}

fn voronoiF2F1(p: vec2<f32>) -> f32 {
  var F1 = 1e9; var F2 = 1e9; let ip = floor(p);
  for (var i = -1; i <= 1; i = i + 1) {
    for (var j = -1; j <= 1; j = j + 1) {
      let d = length(p - ip - vec2<f32>(f32(i), f32(j)) - hash22(ip + vec2<f32>(f32(i), f32(j))));
      F2 = select(select(F2, d, d < F2), F1, d < F1);
      F1 = select(F1, d, d < F1);
    }
  }
  return F2 - F1;
}

fn get_luminance(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn sobel(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
  let t = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, -texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let l = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  return sqrt(length(r - l) * length(r - l) + length(b - t) * length(b - t));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let coords = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let texel = 1.0 / resolution;

  let param1 = u.zoom_params.x; let param2 = u.zoom_params.y;
  let param3 = u.zoom_params.z; let param4 = u.zoom_params.w;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let scan_x = mouse.x;

  // Domain-warped UV displacement (signal drift)
  let warp = vec2<f32>(warpedFBM(uv * 3.0 + scan_x, time * 0.2),
                       warpedFBM(uv * 3.0 + scan_x + 10.0, time * 0.2)) * (0.03 * param4);
  let wuv = clamp(uv + warp, vec2<f32>(0.0), vec2<f32>(1.0));

  let scan_width = 0.15 * (1.0 + (param3 - 0.5) * 0.5);
  let dist = abs(wuv.x - scan_x);
  let in_scan = smoothstep(scan_width, scan_width - 0.01, dist);

  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let edge = sobel(uv, texel) * (1.0 + (param4 - 0.5) * 2.0);
  let lum = get_luminance(color);

  // Voronoi data-block pattern inside scan zone
  let dataBlock = smoothstep(0.05, 0.15, voronoiF2F1(wuv * (20.0 * (1.0 + (param3 - 0.5) * 1.0)) + time * 0.1));

  let grid_uv = fract(wuv * (40.0 * (1.0 + (param3 - 0.5) * 1.0)) + warp * 10.0);
  let grid = step(0.95, grid_uv.x) + step(0.95, grid_uv.y);

  let scan_color = vec3<f32>(0.0, lum * 0.5, lum * 0.8);
  let edge_color = vec3<f32>(0.0, 1.0, 0.8);
  let grid_color = vec3<f32>(0.0, 0.5, 0.0);
  let block_color = vec3<f32>(0.0, 0.8, 1.0) * dataBlock;

  var analyzed = mix(scan_color, edge_color, clamp(edge * 4.0, 0.0, 1.0));
  analyzed = max(analyzed, grid_color * grid);
  analyzed = mix(analyzed, analyzed + block_color, in_scan * param4);

  // Audio-reactive pulse: bass drives border, mids add glow, treble sharpens
  let audioPulse = 1.0 + bass * param2 * 4.0 + mids * param2 * 2.0;
  let borderGlow = 0.005 * (1.0 + bass * param2 * 0.5 + treble * 0.2);
  let border_line = smoothstep(scan_width - borderGlow, scan_width, dist) *
                    (1.0 - smoothstep(scan_width, scan_width + borderGlow, dist));
  analyzed = analyzed + vec3<f32>(1.0, 1.0, 1.0) * border_line * 4.0 * audioPulse;

  let intensity = 0.9 * (0.5 + param1);
  let dimAmount = 0.4 * (1.0 + (param1 - 0.5) * 0.4);
  color = mix(color * dimAmount, analyzed, in_scan * intensity);

  // Semantic alpha: scan zone + edge strength + audio
  let alpha = mix(0.4 + lum * 0.4, 0.95, in_scan * (0.5 + edge * 2.0) * (1.0 + bass * param2 * 0.5 + mids * 0.1));
  let finalAlpha = clamp(alpha, 0.0, 1.0);

  let finalColor = vec4<f32>(color, finalAlpha);

  textureStore(writeTexture, coords, finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
