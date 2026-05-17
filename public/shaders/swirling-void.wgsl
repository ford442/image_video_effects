// ═══════════════════════════════════════════════════════════════════
//  Swirling Void
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Upgraded: OkLab mix, blackbody temperature, ACES tonemap, IGN dither
//  Created: 2026-05-10
//  By: The Visualist
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
fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 40000.0) / 100.0;
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (t <= 66.0) { r = 1.0; }
  else { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
  if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
  else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
  if (t >= 66.0) { b = 1.0; }
  else if (t <= 19.0) { b = 0.0; }
  else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
  return vec3<f32>(r, g, b);
}
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  let s = min(1.0, max_lum / max(l, 1e-4));
  return c * s;
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
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);
  let aspect = u.config.z / u.config.w;
  let mouse = u.zoom_config.yz;
  let strength = u.zoom_params.x * 5.0;
  let radius = u.zoom_params.y;
  let darkness = u.zoom_params.z;
  let audioReact = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let reactiveStrength = strength * (1.0 + bass * audioReact);
  let uv_centered = uv - mouse;
  let uv_corrected = vec2<f32>(uv_centered.x * aspect, uv_centered.y);
  let dist = length(uv_corrected);
  let angle = atan2(uv_corrected.y, uv_corrected.x);
  let influence = exp(-dist * (10.0 * (1.1 - radius)));
  let twist = reactiveStrength * influence;
  let final_angle = angle + twist;
  let new_uv_corrected = vec2<f32>(cos(final_angle), sin(final_angle)) * dist;
  let new_uv = vec2<f32>(new_uv_corrected.x / aspect, new_uv_corrected.y) + mouse;
  let color = textureSampleLevel(readTexture, u_sampler, new_uv, 0.0).rgb;
  // Event horizon sizing
  let hole_size = 0.04 + 0.08 * darkness;
  let voidEdge = smoothstep(hole_size, hole_size * 3.0, dist);
  // Accretion disk: blackbody glow peaking just outside horizon
  let glowRing = hole_size * 1.6;
  let glowDist = abs(dist - glowRing) / glowRing;
  let glowT = 1200.0 + 6800.0 * (1.0 - smoothstep(0.0, 0.8, glowDist));
  let glowRGB = blackbodyRGB(glowT) * 4.0;
  let glowMix = (1.0 - smoothstep(0.0, 0.6, glowDist)) * (1.0 - voidEdge) * darkness;
  // Volumetric darkening toward void center
  let darken = mix(0.15, 1.0, voidEdge * (1.0 - darkness * 0.3));
  // Process in linear, OkLab mix toward blackbody glow
  let linearColor = pow(color, vec3<f32>(2.2));
  let mixed = mixOkLab(linearColor * darken, glowRGB, glowMix * (1.0 + bass * audioReact * 0.5));
  // HDR clamp, ACES tonemap, IGN dither
  let clamped = hue_preserve_clamp(mixed, 6.0);
  let tonemapped = aces(clamped);
  let dither = (ign(vec2<f32>(coord)) - 0.5) / 255.0;
  let srgb = pow(max(tonemapped + vec3<f32>(dither), vec3<f32>(0.0)), vec3<f32>(1.0/2.2));
  let a = clamp(voidEdge, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(srgb * a, a));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
