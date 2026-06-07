// ═══════════════════════════════════════════════════════════════════
//  Aurora Curtain — Visualist Upgrade
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, chapman-layer,
//            kelvin-helmholtz, temporal-flow, upgraded-rgba,
//            oklab-mix, blackbody-stars, mie-scatter, ign-dither
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

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

  let layerBase = 3 + i32(u.zoom_params.x * 5.0);
  let flowSpeed = u.zoom_params.y * 0.4;
  let curtainWidth = 0.25 + u.zoom_params.z * 0.4;
  let colorShift = u.zoom_params.w;

  let aspect = res.x / res.y;
  let p = uv * vec2<f32>(aspect, 1.0);

  // Mouse drags magnetic zenith
  let magZenith = vec2<f32>(mouse.x * aspect, mouse.y);
  let distToZenith = length(p - magZenith);

  var hdr = vec3<f32>(0.0);
  var excitation = 0.0;
  var bloom = 0.0;

  // Aurora palette anchors for OkLab blending
  let cRed = vec3<f32>(0.85, 0.25, 0.15);
  let cGreen = vec3<f32>(0.25, 0.95, 0.35);
  let cBlue = vec3<f32>(0.35, 0.45, 0.95);
  let cPink = vec3<f32>(0.95, 0.35, 0.75);

  for (var i = 0; i < layerBase; i = i + 1) {
    let fi = f32(i);
    let t = time * flowSpeed * (0.4 + fi * 0.12);
    let altitude = fi / f32(layerBase);

    // Curtain displacement with Kelvin-Helmholtz folding
    let baseY = 0.15 + fi * 0.18 + (mouse.y - 0.5) * 0.2;
    let khx = p.x * (2.5 + fi * 0.8) + t + fi * 1.9;
    let kh = sin(khx) * 0.06 + sin(khx * 2.7 - t * 1.4) * 0.03 * (1.0 + mids);
    let khInstability = noise2(vec2<f32>(p.x * 4.0 + t, fi * 3.0)) * 0.04 * mids;
    let curtainY = baseY + kh + khInstability + (distToZenith * 0.08 * (1.0 - altitude));

    let dist = abs(p.y - curtainY);
    let thickness = curtainWidth * (0.7 + fi * 0.08) * (1.0 + bass * 0.25);
    let glow = smoothstep(thickness, 0.0, dist);

    // Smooth OkLab altitude palette (branchless where possible)
    var layerColor: vec3<f32>;
    if (altitude < 0.35) {
      layerColor = mixOkLab(cRed, cGreen, altitude / 0.35);
    } else if (altitude < 0.65) {
      layerColor = mixOkLab(cGreen, cBlue, (altitude - 0.35) / 0.30);
    } else {
      layerColor = mixOkLab(cBlue, cPink, (altitude - 0.65) / 0.35);
    }

    // Color shift and rayed bands from treble
    let rayBands = sin(p.x * 18.0 + fi * 3.7 + treble * 5.0) * 0.5 + 0.5;
    let rayMask = smoothstep(0.55, 0.95, rayBands) * treble * 0.4;
    layerColor = mix(layerColor, layerColor * 1.5, rayMask);

    // Audio-reactive blackbody temperature shift
    let tempShift = blackbodyRGB(3000.0 + bass * 5000.0);
    layerColor = mix(layerColor, layerColor * tempShift * 1.4, colorShift * 0.3);

    let layerIntensity = glow * (0.5 + fi * 0.08) * (1.0 + bass * 0.35);
    hdr = hdr + layerColor * layerIntensity * 1.5;
    excitation = excitation + layerIntensity;
    bloom = bloom + glow * (0.3 + bass * 0.2);
  }

  // Star field with blackbody temperatures
  let starHash = hash21(floor(uv * 800.0));
  let star = step(0.998, starHash);
  let twinkle = sin(time * 2.5 + starHash * 20.0) * 0.5 + 0.5;
  let starTemp = mix(3000.0, 9000.0, hash21(floor(uv * 800.0) + vec2<f32>(1.0, 2.0)));
  let starColor = blackbodyRGB(starTemp) * star * twinkle * 0.5;
  hdr = hdr + starColor;

  // Rayleigh scattering + Mie haze
  let atmosScatter = smoothstep(0.0, 0.5, uv.y) * vec3<f32>(0.08, 0.12, 0.22) * (1.0 + mids * 0.3);
  let miePhase = pow(1.0 + uv.y, 1.5);
  let mieHaze = vec3<f32>(0.18, 0.15, 0.12) * miePhase * 0.06 * (1.0 + bass * 0.2);
  hdr = hdr + atmosScatter + mieHaze;

  // HDR bloom on curtain folds
  hdr = hdr + vec3<f32>(0.4, 0.7, 0.5) * bloom * 0.35;

  // Beer-Lambert atmospheric extinction by depth
  let extinction = depth * 0.35 * (1.0 + bass * 0.15);
  hdr = hdr * exp(-extinction * 0.8);

  // Tonemap & dither stack
  hdr = hue_preserve_clamp(hdr, 6.0);
  let mapped = aces(hdr * 1.2);
  let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
  let color = pow(mapped, vec3<f32>(1.0 / 2.2)) + vec3<f32>(dither);

  let transparency = 1.0 - smoothstep(0.0, 0.4, uv.y) * 0.25;
  let bloomWeight = clamp(excitation * transparency * (0.6 + depth * 0.4), 0.0, 1.0);
  let a = bloomWeight;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color * a, a));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color * a, a));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(excitation * 0.4, 0.0, 0.0, 0.0));
}
