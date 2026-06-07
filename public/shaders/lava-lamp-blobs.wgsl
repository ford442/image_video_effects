// ═══════════════════════════════════════════════════════════════════
//  Lava Lamp Blobs
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, oklab-mix,
//            blackbody-temp, subsurface-glow, ign-dither
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-07
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

fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(29.5, 11.3)));
}

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

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
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

fn blobField(p: vec2<f32>, time: f32, count: f32, speed: f32) -> f32 {
  var field = 0.0;
  for (var i = 0u; i < u32(count); i = i + 1u) {
    let fi = f32(i);
    let seed = hash22(vec2<f32>(fi, 11.7));
    let phase = fi * 6.28318 / count;
    let bx = sin(phase + time * speed * (0.3 + seed.x * 0.5)) * (0.5 + seed.x * 0.3);
    let by = -0.8 + fract(fi / count + time * speed * (0.1 + seed.y * 0.2)) * 1.6;
    let d = length(p - vec2<f32>(bx, by));
    let size = 0.12 + seed.y * 0.08;
    field = field + exp(-d * d / (size * size));
  }
  return field;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let blobCount = mix(2.0, 10.0, u.zoom_params.x);
  let riseSpeed = mix(0.05, 0.6, u.zoom_params.y);
  let melt = mix(0.0, 1.0, u.zoom_params.z);
  let heat = mix(0.3, 2.0, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p + mouse * 0.1;

  let blobs = blobField(p, time, blobCount, riseSpeed);
  let blobShape = smoothstep(0.5, 1.2, blobs);
  let blobHalo = smoothstep(0.2, 0.8, blobs) * (1.0 - blobShape);
  let blobCenter = smoothstep(1.0, 1.5, blobs);

  // Blackbody temperature: warm core, cool halo, driven by audio
  let coreTemp = 2000.0 + heat * 3000.0 + bass * 2000.0;
  let haloTemp = 6000.0 + mids * 4000.0;
  let coreCol = blackbodyRGB(coreTemp) * vec3<f32>(1.3, 1.0, 0.8);
  let haloCol = blackbodyRGB(haloTemp) * vec3<f32>(0.7, 0.9, 1.1);

  // Palette-driven variation for organic color shifts
  let paletteCol = palette(blobs * 2.0 + time * 0.3 + bass,
    vec3<f32>(0.5,0.5,0.5), vec3<f32>(0.5,0.5,0.5),
    vec3<f32>(1.0,1.0,0.5), vec3<f32>(0.0,0.1,0.2));

  // Subsurface scattering glow: light penetrates blob edges
  let sss = exp(-blobs * 2.0) * blobHalo * 0.6;
  // Fresnel rim: brighter at grazing angles (blob edges)
  let rim = pow(blobHalo, 3.0) * (1.0 + treble * 0.5);

  // 3-point lighting: key (warm core) + fill (cool halo) + rim (hot edge)
  var color = vec3<f32>(0.02, 0.02, 0.05);
  color = color + coreCol * blobShape * heat * (1.5 + bass * 0.5);
  color = color + mixOkLab(haloCol, paletteCol, 0.3) * blobHalo * melt * (0.8 + mids * 0.3);
  color = color + vec3<f32>(1.0, 0.85, 0.6) * sss * 0.5;
  color = color + vec3<f32>(1.2, 0.9, 0.7) * rim * 0.8;
  color = color + vec3<f32>(1.0, 0.95, 0.9) * blobCenter * treble * 1.2;

  // Volumetric haze (Beer-Lambert) for depth atmosphere
  let distFromCenter = length(p);
  let haze = exp(-distFromCenter * 1.2);
  color = color * haze + mixOkLab(vec3<f32>(0.02,0.02,0.05), haloCol * 0.08, 0.4) * (1.0 - haze);

  // Temporal feedback
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.9, 0.03 + bass * 0.01);

  // Tonemap & dither stack
  color = hue_preserve_clamp(color, 4.0);
  color = aces(color);
  let dither = (ign(vec2<f32>(gid.xy)) - 0.5) / 255.0;
  color = color + vec3<f32>(dither);

  // Bloom-weight alpha
  let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  let bloomWeight = pow(max(0.0, luma - 0.5), 2.0) * 3.0;
  let presence = sat(blobShape * 0.9 + blobHalo * 0.5);
  let alpha = sat(0.12 + presence * 0.88);
  let a = max(alpha, bloomWeight * 0.6);
  let depth = sat(0.9 - blobShape * 0.55 - blobHalo * 0.2);

  let outRGB = pow(color, vec3<f32>(1.0/2.2));
  textureStore(writeTexture, coord, vec4<f32>(outRGB * a, a));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(blobShape, blobHalo, heat, a));
}
