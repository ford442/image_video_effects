// ═══════════════════════════════════════════════════════════════════
//  Tesseract Fold
//  Category: image
//  Features: mouse-driven
//  Complexity: Medium
//  Upgraded: HDR, ACES tone mapping, iridescent color grading,
//            atmospheric vignette, branchless mirror, bloom alpha
// ═══════════════════════════════════════════════════════════════════

// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
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
// ───────────────────────────────────────────────────────────────

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Folds, y=Mirror, z=Shift, w=Zoom
  ripples: array<vec4<f32>, 50>,
};

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
  let a = x * (2.51 * x + 0.03);
  let b = x * (2.43 * x + 0.59) + 0.14;
  return clamp(a / b, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;

  let folds = u.zoom_params.x * 5.0 + 1.0;
  let mirror_str = u.zoom_params.y;
  let dim_shift = u.zoom_params.z;
  let zoom = mix(0.5, 2.0, u.zoom_params.w);

  var p = (uv - mouse);
  p.x *= aspect;

  let r = length(p);
  let a = atan2(p.y, p.x);
  let base_angle = 3.14159 / folds;

  for (var i = 0; i < 3; i++) {
    p = abs(p);
    p -= vec2<f32>(0.2 * dim_shift);
    let angle = base_angle * (1.0 + 0.3 * sin(time + f32(i) * 1.7));
    let c = cos(angle);
    let s = sin(angle);
    p = vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
  }

  p = p / zoom;

  var final_uv = mouse + p / vec2<f32>(aspect, 1.0);
  final_uv = mix(final_uv, abs(final_uv - 0.5) + 0.5, smoothstep(0.4, 0.6, mirror_str));

  let aberration = 0.008 * dim_shift + 0.002 * sin(time * 2.0);
  let col = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0).rgb;
  let cr = textureSampleLevel(readTexture, u_sampler, final_uv + vec2<f32>(aberration, 0.0), 0.0).r;
  let cb = textureSampleLevel(readTexture, u_sampler, final_uv - vec2<f32>(aberration, 0.0), 0.0).b;

  var color = pow(vec3<f32>(cr, col.g, cb), vec3<f32>(2.2));

  let hue = (a / 3.14159) * 0.5 + 0.5;
  let grade = palette(hue + r * 2.0 + time * 0.1,
                      vec3<f32>(0.5, 0.5, 0.5),
                      vec3<f32>(0.5, 0.5, 0.5),
                      vec3<f32>(1.0, 1.0, 0.8),
                      vec3<f32>(0.0, 0.15, 0.25));
  color = mix(color, color * grade * 2.0, 0.25);

  let dist = length(uv - mouse);
  let vignette = exp(-dist * dist * 4.0);
  color = mix(color * 0.2, color, vignette);

  color = pow(aces_tone_map(color), vec3<f32>(1.0 / 2.2));

  let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  let bloom = pow(max(0.0, luma - 0.5), 2.0) * 3.0;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, bloom));
}
