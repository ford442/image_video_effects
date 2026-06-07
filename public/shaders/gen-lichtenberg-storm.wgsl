// gen-lichtenberg-storm.wgsl — Visualist upgrade
// Lichtenberg discharge with OkLab mixing, blackbody temperature, atmospheric depth

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

fn h12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn h13(p: vec3<f32>) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn n2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(h12(i + vec2<f32>(0.0, 0.0)), h12(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(h12(i + vec2<f32>(0.0, 1.0)), h12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var x = p;
  for (var i = 0; i < 5; i++) {
    v += a * n2(x);
    x *= 2.0;
    a *= 0.5;
  }
  return v;
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

fn licht(p: vec2<f32>, seed: vec2<f32>, branches: f32, jitter: f32, t: f32) -> f32 {
  let d = p - seed;
  let r = length(d);
  let a = atan2(d.y, d.x);
  let w = fbm(d * 3.0 + t * 0.1) * jitter * 3.0;
  let dend = fbm(vec2<f32>(a * branches + w, r * 6.0));
  return max(smoothstep(0.12, 0.0, r), smoothstep(0.55, 0.45, dend) * smoothstep(0.6, 0.0, r));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
  let uv = vec2<f32>(gid.xy) / res;
  let t = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let jitter = u.zoom_params.x;
  let glow = u.zoom_params.y;
  let stormFreq = u.zoom_params.z;
  let afterglow = u.zoom_params.w;
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;
  let storm = smoothstep(0.9, 1.0, sin(t * stormFreq * 3.0) * 0.5 + 0.5);
  var energy = 0.0;
  let branches = mix(8.0, 24.0, jitter);
  let numSeeds = 3u + u32(bass * 3.0);
  for (var i = 0u; i < numSeeds; i++) {
    let fi = f32(i);
    let seed = vec2<f32>(h13(vec3<f32>(fi, floor(t * 0.3 * stormFreq), 0.0)), h13(vec3<f32>(fi, floor(t * 0.3 * stormFreq), 1.0)));
    energy = max(energy, licht(uv, seed + vec2<f32>(sin(t * 0.2 + fi), cos(t * 0.15 + fi)) * 0.1, branches, jitter, t));
  }
  let bassPulse = step(0.7, bass) * storm;
  if (bassPulse > 0.0) {
    let bs = vec2<f32>(h13(vec3<f32>(t, 0.0, 0.0)), h13(vec3<f32>(t, 0.0, 1.0)));
    energy = max(energy, licht(uv, bs, branches * 1.5, jitter, t) * bassPulse);
  }
  let clickCount = u32(u.config.y);
  for (var i = 0u; i < min(clickCount, 10u); i++) {
    let rt = t - u.ripples[i].z;
    let rdecay = exp(-rt * 2.0);
    if (rdecay > 0.01) {
      energy = max(energy, licht(uv, u.ripples[i].xy, branches, jitter, t) * rdecay);
    }
  }
  let thick = mix(0.5, 2.0, mids);
  energy = smoothstep(0.0, 1.0 / thick, energy);
  energy = max(energy, prev * mix(0.7, 0.98, afterglow));

  // Atmospheric depth: attenuate distant branches (Beer-Lambert)
  let atmosDist = length(uv - 0.5) * 1.4;
  let atmos = exp(-atmosDist * 2.5);

  // Blackbody temperature layers: cool plasma → hot core
  let coolPlasma = blackbodyRGB(1800.0 + storm * 1200.0);
  let warmArc = blackbodyRGB(4500.0 + mids * 2500.0);
  let hotCore = blackbodyRGB(8000.0 + treble * 6000.0);

  let hot = smoothstep(0.6, 1.0, energy);
  let warm = smoothstep(0.3, 0.6, energy);

  // OkLab mix for smooth tonal transitions
  var col = mixOkLab(coolPlasma * 0.3, warmArc, warm);
  col = mixOkLab(col, hotCore, hot);

  // HDR tip glow with treble sparkle
  col += hotCore * energy * energy * 3.0 * glow;
  col += vec3<f32>(0.8, 0.95, 1.0) * hot * (1.0 + bass * 0.5 + treble * 0.8) * glow;
  col += vec3<f32>(1.0) * h12(vec2<f32>(gid.xy) + fract(t * 20.0)) * treble * hot * 5.0;

  // Phosphorescent afterglow with split-tone via OkLab
  let decayCol = mixOkLab(vec3<f32>(0.2, 0.0, 0.4), vec3<f32>(0.0, 0.6, 0.3), prev);
  col += decayCol * prev * afterglow * 0.4 * atmos;

  // Storm field background
  let field = fbm(uv * 4.0 + t * 0.2) * 0.04;
  col += coolPlasma * field * (1.0 + storm);

  // Atmospheric attenuation
  col *= atmos;

  // Tonemap & Dither Stack
  col = hue_preserve_clamp(col, 10.0);
  col = aces(col * glow * 1.6);
  let dither = (ign(vec2<f32>(gid.xy)) - 0.5) / 255.0;
  col += vec3<f32>(dither);

  // Bloom-weight alpha + premultiplied write
  let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
  let bloomWeight = pow(max(0.0, luma - 0.4), 2.0) * 3.0 + energy * 0.2;
  let a = clamp(bloomWeight, 0.0, 1.0);
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(col * a, a));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(energy, 0.0, 0.0, 0.0));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(energy * 0.5 + 0.2 + storm * 0.15, 0.0, 0.0, 0.0));
}
