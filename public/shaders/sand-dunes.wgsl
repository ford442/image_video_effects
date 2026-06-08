// ═══════════════════════════════════════════════════════════════════
//  Sand Dunes — Visualist Upgrade
//  Category: generative
//  Features: generative, audio-reactive, bagnold-physics, anisotropic-fbm,
//            wind-erosion, separation-bubble, upgraded-rgba,
//            oklab-palette, blackbody-sun, beer-lambert-haze, ign-dither
//  Complexity: High
//  Created: 2026-05-31
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
  return fract(sin(q) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
    mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x),
    u.y
  );
}

fn fBm(p: vec2<f32>, octaves: i32) -> f32 {
  var val = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    val = val + amp * noise2(p * freq);
    amp = amp * 0.5;
    freq = freq * 2.03;
  }
  return val;
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
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let duneScale = u.zoom_params.x * 4.0 + 2.0;
  let windBase = u.zoom_params.y * 0.5;
  let erosion = u.zoom_params.z;
  let shadowDepth = u.zoom_params.w;

  // Wind direction from mouse + mids
  let windAngle = (mouse.x - 0.5) * 1.5 + (mids - 0.5) * 0.8;
  let windDir = vec2<f32>(cos(windAngle), sin(windAngle));
  let windSpeed = windBase + bass * 0.3;
  let t = time * windSpeed;

  // Anisotropic fBm stretched along wind direction
  let p = uv * duneScale;
  let aniso = vec2<f32>(dot(p, windDir), dot(p, vec2<f32>(-windDir.y, windDir.x))) * vec2<f32>(2.5, 1.0);
  let height = fBm(aniso + vec2<f32>(t * 0.3, 0.0), 5) * 0.5 + 0.5;

  // Separation bubble at crests (lee side)
  let slope = (fBm(aniso + vec2<f32>(0.01, 0.0) + vec2<f32>(t * 0.3, 0.0), 5)
             - fBm(aniso - vec2<f32>(0.01, 0.0) + vec2<f32>(t * 0.3, 0.0), 5)) * 25.0;
  let crest = smoothstep(0.3, 0.7, height) * smoothstep(0.0, -0.4, slope);
  let bubble = crest * 0.25 * (1.0 + bass * 0.5);

  // Ripple superposition on dune flanks
  let rippleCoord = p * 8.0 + windDir * t * 2.0;
  let ripple1 = sin(rippleCoord.x * 3.0 + rippleCoord.y * 1.5) * 0.5 + 0.5;
  let ripple2 = sin(rippleCoord.x * 5.0 - rippleCoord.y * 2.0 + t * 1.5) * 0.5 + 0.5;
  let rippleMask = smoothstep(0.6, 0.9, ripple1 * ripple2) * erosion * (0.5 + abs(slope) * 2.0);

  // Desert palette in OkLab for smooth transitions
  let lit = vec3<f32>(0.92, 0.72, 0.42);
  let mid = vec3<f32>(0.72, 0.45, 0.22);
  let shadow = vec3<f32>(0.42, 0.28, 0.14);
  let umber = vec3<f32>(0.28, 0.18, 0.10);

  // 3-point lighting with blackbody color temperatures
  let sunTemp = 4500.0 + bass * 2500.0;
  let keyLight = blackbodyRGB(sunTemp);
  let fillLight = blackbodyRGB(8000.0) * 0.35;
  let rimLight = blackbodyRGB(6000.0) * 0.5;

  // Shadow with soft penumbra
  let shadowMask = smoothstep(0.2, -0.6, slope) * shadowDepth;
  let duneColor = mixOkLab(lit, mixOkLab(mid, shadow, shadowMask * 0.7), shadowMask);

  // Approximate normal for lighting
  let normalApprox = normalize(vec3<f32>(-slope * 2.0, 1.0, 0.5));
  let sunDir = normalize(vec3<f32>(0.6, 0.8, 0.2));
  let key = max(0.0, dot(normalApprox, sunDir));
  let fill = max(0.0, dot(normalApprox, normalize(vec3<f32>(-0.4, 0.6, 0.3)))) * 0.6;
  let rim = pow(1.0 - max(0.0, dot(normalApprox, vec3<f32>(0.0, 0.0, 1.0))), 3.0);
  var hdr = duneColor * (keyLight * key + fillLight * fill) + rimLight * rim * crest;

  // Subsurface scattering on slip faces
  let sss = smoothstep(-0.8, -0.2, slope) * crest * vec3<f32>(0.55, 0.30, 0.12) * 0.5;
  hdr = hdr + sss;

  // Saltation sparkles from treble
  let sparkleCoord = uv * 120.0 + windDir * t * 10.0;
  let sparkle = step(0.997 - treble * 0.003, fract(sin(dot(sparkleCoord, vec2<f32>(12.9898, 78.233))) * 43758.5453));
  let sparkleColor = vec3<f32>(1.0, 0.95, 0.85) * sparkle * treble * (0.5 + smoothstep(0.0, -0.3, slope));
  hdr = hdr + sparkleColor * 2.0;

  // Wind shadows behind mouse
  let mouseDist = length(uv - mouse);
  let windShadow = smoothstep(0.15, 0.0, mouseDist) * smoothstep(0.0, 0.5, dot(normalize(uv - mouse), windDir));
  hdr = hdr * (1.0 - windShadow * 0.4);

  // Ripple detail with OkLab umber blend
  hdr = mix(hdr, mixOkLab(umber, shadow, 0.5) * keyLight, rippleMask * 0.6);

  // Beer-Lambert atmospheric haze by depth
  let hazeDensity = depth * 0.45 * (1.0 + bass * 0.2);
  let skyColor = mixOkLab(vec3<f32>(0.82, 0.72, 0.58), vec3<f32>(0.55, 0.65, 0.85), 0.3);
  let transmittance = exp(-hazeDensity * 1.5);
  hdr = hdr * transmittance + skyColor * (1.0 - transmittance) * 0.5;

  // Tonemap & dither stack
  hdr = hue_preserve_clamp(hdr, 5.0);
  let mapped = aces(hdr * 1.3);
  let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
  let color = pow(mapped, vec3<f32>(1.0 / 2.2)) + vec3<f32>(dither);

  let sandDensity = 0.75 + height * 0.2 + rippleMask * 0.1;
  let windExposure = 0.6 + windSpeed * 0.4;
  let bloomWeight = clamp(sandDensity * windExposure * transmittance, 0.0, 1.0);
  let a = bloomWeight;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color * a, a));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color * a, a));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(height * 0.5 + bubble, 0.0, 0.0, 0.0));
}
