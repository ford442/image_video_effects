// ═══════════════════════════════════════════════════════════════════
//  Color Blindness
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Low
//  Upgraded: 2026-09-06
//  Ideas: continuous type mix; confusion-axis assist from unused param
//  A packing: display RGBA
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn mixMat(a: mat3x3<f32>, b: mat3x3<f32>, t: f32) -> mat3x3<f32> {
  return mat3x3<f32>(
    mix(a[0], b[0], t),
    mix(a[1], b[1], t),
    mix(a[2], b[2], t)
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(gid.xy) / resolution;
  let coord = vec2<i32>(gid.xy);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let typeParam = clamp(u.zoom_params.x, 0.0, 1.0);
  let severity = clamp(u.zoom_params.y * (1.0 + bass * 0.4), 0.0, 1.0);
  let splitMode = u.zoom_params.z > 0.5;
  let assist = clamp(u.zoom_params.w, 0.0, 1.0);

  let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let color = original.rgb;

  let protan = mat3x3<f32>(
    vec3<f32>(0.567, 0.558, 0.0),
    vec3<f32>(0.433, 0.442, 0.242),
    vec3<f32>(0.0, 0.0, 0.758)
  );
  let deutan = mat3x3<f32>(
    vec3<f32>(0.625, 0.7, 0.0),
    vec3<f32>(0.375, 0.3, 0.3),
    vec3<f32>(0.0, 0.0, 0.7)
  );
  let tritan = mat3x3<f32>(
    vec3<f32>(0.95, 0.0, 0.0),
    vec3<f32>(0.05, 0.433, 0.475),
    vec3<f32>(0.0, 0.567, 0.525)
  );

  let t = typeParam * 2.0;
  var m = mixMat(protan, deutan, clamp(t, 0.0, 1.0));
  m = mixMat(m, tritan, clamp(t - 1.0, 0.0, 1.0));

  var simulated = mix(color, m * color, severity);

  let showOriginal = splitMode && (uv.x < u.zoom_config.y);
  var finalColor = select(simulated, color, showOriginal);

  let seamDist = abs(uv.x - u.zoom_config.y);
  let seam = select(0.0, smoothstep(0.004, 0.0, seamDist) * mids, splitMode);
  finalColor = clamp(finalColor + seam, vec3<f32>(0.0), vec3<f32>(1.0));

  let shift = length(simulated - color);
  let hatch = step(0.55, fract((uv.x + uv.y) * 90.0));
  finalColor = mix(finalColor, mix(finalColor, vec3<f32>(shift), hatch * 0.65), assist * smoothstep(0.04, 0.18, shift));

  let display = acesToneMap(finalColor);
  let alpha = clamp(original.a * 0.6 + shift + seam, 0.0, 1.0);
  let outCol = vec4<f32>(display, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
