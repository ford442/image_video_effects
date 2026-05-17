// ═══════════════════════════════════════════════════════════════════
//  Directional Glitch
//  Category: interactive-mouse
//  Features: mouse-driven, glitch, audio-reactive, hdr, tonemapped
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Pixelocity Shader Upgrade Swarm — Phase A
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
// ── OkLab color mixing ────────────────────────────────────────────
fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
  let l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
  let m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
  let s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
  let l_ = pow(l, 1.0/3.0); let m_ = pow(m, 1.0/3.0); let s_ = pow(s, 1.0/3.0);
  return vec3<f32>(0.2104542553*l_+0.7936177850*m_-0.0040720468*s_,
                   1.9779984951*l_-2.4285922050*m_+0.4505937099*s_,
                   0.0259040371*l_+0.7827717662*m_-0.8086757660*s_);
}
fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
  let l_ = c.x+0.3963377774*c.y+0.2158037573*c.z;
  let m_ = c.x-0.1055613458*c.y-0.0638541728*c.z;
  let s_ = c.x-0.0894841775*c.y-1.2914855480*c.z;
  let l = l_*l_*l_; let m = m_*m_*m_; let s = s_*s_*s_;
  return vec3<f32>(4.0767416621*l-3.3077115913*m+0.2309699292*s,
                  -1.2684380046*l+2.6097574011*m-0.3413193965*s,
                  -0.0041960863*l-0.7034186147*m+1.7076147010*s);
}
fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}
// ── Blackbody temperature ─────────────────────────────────────────
fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 40000.0) / 100.0;
  var r = 1.0; var g = 0.0; var b = 0.0;
  if (t > 66.0) { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
  if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
  else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
  if (t >= 66.0) { b = 1.0; }
  else if (t > 19.0) { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
  return vec3<f32>(r, g, b);
}
// ── Tonemap & dither stack ────────────────────────────────────────
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  return c * min(1.0, max_lum / max(l, 1e-4));
}
fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let audio_mod = 1.0 + bass * 0.5;

  let intensity = u.zoom_params.x;
  let radius = u.zoom_params.y;
  let scatter = u.zoom_params.z;
  let angle_bias = u.zoom_params.w;

  let uv_c = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_c = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = distance(uv_c, mouse_c);

  let angle = atan2(uv.y - mouse.y, uv.x - mouse.x) + angle_bias * 6.28;

  let block_id = floor(uv * 50.0);
  let noise = fract(sin(dot(block_id, vec2<f32>(12.9898, 78.233) + time)) * 43758.5453);

  let mask = smoothstep(radius, 0.0, dist);
  let is_glitch = step(1.0 - scatter, noise);

  let disp = is_glitch * intensity * mask * 0.1 * audio_mod;
  let shift = vec2<f32>(cos(angle), sin(angle)) * disp;

  // Chromatic aberration with HDR boost
  let sr = textureSampleLevel(readTexture, u_sampler, uv - shift, 0.0);
  let sg = textureSampleLevel(readTexture, u_sampler, uv - shift * 1.5, 0.0);
  let sb = textureSampleLevel(readTexture, u_sampler, uv - shift * 2.0, 0.0);
  var glitch = vec3<f32>(sr.r, sg.g, sb.b) * (1.0 + disp * 12.0);

  // Blackbody temperature tint driven by bass + local noise
  let temp = mix(2200.0, 14000.0, clamp(bass * 0.7 + noise * 0.4, 0.0, 1.0));
  glitch = glitch * blackbodyRGB(temp);

  // Static spark noise
  let spark = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
  glitch = glitch + vec3<f32>(spark * mask * intensity * 0.6 * audio_mod);

  // Mix original and glitch in OkLab for smooth perceptual blending
  let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let mixFactor = mask * is_glitch * intensity;
  var color = mixOkLab(original, glitch, mixFactor);

  // HDR pipeline: hue-preserve clamp → ACES → IGN dither
  color = hue_preserve_clamp(color, 3.0);
  color = aces(color);
  let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
  color = color + vec3<f32>(dither);

  // Premultiplied alpha writeback
  let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  let alpha = clamp(mix(1.0, 0.35 + 0.65 * luma, mixFactor), 0.3, 1.0);
  let a = clamp(alpha, 0.0, 1.0);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color * a, a));

  // Depth pass-through
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
