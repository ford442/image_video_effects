// ═══════════════════════════════════════════════════════════════════
//  Plasma Mandala
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-06-06
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ACES filmic tonemap
fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 2D hash
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Smooth noise
fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

// FBM for plasma texture
fn fbm2(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var amp = 0.5;
  var pp = p;
  for (var i = 0u; i < 5u; i++) {
    v += amp * noise2(pp);
    pp *= 2.0;
    amp *= 0.5;
  }
  return v;
}

// Plasma function — sum of trig waves
fn plasma(p: vec2<f32>, t: f32, mids: f32) -> f32 {
  let s1 = sin(p.x * 3.0 + t * 1.1);
  let s2 = sin(p.y * 3.0 + t * 0.9);
  let s3 = sin((p.x + p.y) * 2.0 + t * 1.3);
  let r = length(p);
  let s4 = sin(r * 5.0 - t * 2.0 + mids * 1.5);
  return 0.25 * (s1 + s2 + s3 + s4);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);

  let t = u.config.x;
  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let symmetry   = mix(3.0,  12.0, u.zoom_params.x); // petal count
  let spin_speed = mix(0.1,   1.0, u.zoom_params.y) * (1.0 + bass * 0.4);
  let zoom_amt   = mix(0.5,   3.0, u.zoom_params.z);
  let glow_scale = mix(0.5,   3.0, u.zoom_params.w) * (1.0 + mids * 0.3);

  // Mouse influence — pull center toward cursor
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mouse_pull = mouse * 0.3 * u.zoom_config.w;

  // Center-relative coords, aspect-corrected
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  p = p - mouse_pull;

  // Radial mandala: fold into one petal via angular repeat
  let angle = atan2(p.y, p.x);
  let r = length(p) * zoom_amt;

  // Quantise angle to symmetry sectors and mirror within each sector
  let sector_angle = 3.14159265 / symmetry;
  let folded_angle = abs(fract(angle / (2.0 * sector_angle) + 0.5) * 2.0 * sector_angle - sector_angle);

  // Spinning mandala
  let spin = t * spin_speed;
  let px = r * cos(folded_angle + spin);
  let py = r * sin(folded_angle + spin);
  let mp = vec2<f32>(px, py);

  // Plasma field on folded coords
  let plasma_val = plasma(mp, t, mids);

  // FBM detail layer
  let detail = fbm2(mp * 3.0 + vec2<f32>(t * 0.2, t * 0.15));

  // Combine for richness
  let field = plasma_val * 0.6 + detail * 0.4;

  // Hue cycling — audio-driven shift
  let hue_base = fract(field * 0.5 + t * 0.07 + bass * 0.2);
  let hue2 = fract(hue_base + 0.33);
  let hue3 = fract(hue_base + 0.67);

  var col = vec3<f32>(
    0.5 + 0.5 * cos(6.2832 * hue_base),
    0.5 + 0.5 * cos(6.2832 * hue2),
    0.5 + 0.5 * cos(6.2832 * hue3)
  );

  // Radial vignette and glow ring
  let vignette = 1.0 - smoothstep(0.6, 1.4, r);
  let ring_glow = exp(-abs(r - 0.5) * 6.0) * glow_scale;

  col = col * vignette + vec3<f32>(ring_glow * 0.3 * (1.0 + treble * 0.5));

  // Treble sparkle — high-freq shimmer
  let spark = hash21(uv + vec2<f32>(t * 0.01)) * treble * 0.15;
  col += spark;

  // Tonemap
  col = aces(col * glow_scale);

  // Alpha: driven by luminance + glow ring + mouse influence
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let mouse_influence = length(mouse_pull) * 0.3;
  let alpha = clamp(luma * 0.7 + ring_glow * 0.2 + mouse_influence * 0.1, 0.0, 1.0);

  // Depth: radial distance encodes depth (center is near)
  let depth = clamp(1.0 - r * 0.5, 0.0, 1.0);

  let final_color = vec4<f32>(acesToneMap(col * 1.1), alpha);
  textureStore(writeTexture,      coord, final_color);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, final_color);
}
