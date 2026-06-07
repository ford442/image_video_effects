// ═══════════════════════════════════════════════════════════════════
//  Chromatic Ghost Tunnel
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, chromatic, depth-aware,
//            aces-tone-map, oklab-mix, blackbody-temp, volumetric-fog, ign-dither
//  Complexity: High
//  Created: 2026-05-30
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

const PI: f32 = 3.14159265;

fn hash21(p: vec2<f32>) -> f32 {
  var q = fract(p * vec2<f32>(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}
fn hash11(n: f32) -> f32 {
  return fract(sin(n * 127.1 + 311.7) * 43758.5453);
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
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv01 = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let uv = (uv01 - 0.5) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mouseOffset = vec2<f32>(mouse.x * aspect, mouse.y) * 0.4;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let tunnelSpeed   = mix(0.2, 2.0, u.zoom_params.x);
  let spiralTwist   = mix(0.0, 3.0, u.zoom_params.y);
  let echoCount     = mix(2.0, 8.0, u.zoom_params.z);
  let flashIntensity = mix(0.0, 1.0, u.zoom_params.w);

  let tunnelUV = uv + mouseOffset;
  let dist = length(tunnelUV);
  let angle = atan2(tunnelUV.y, tunnelUV.x);

  let z = 1.0 / (dist + 0.01) + bass * 0.3;
  let moveZ = time * tunnelSpeed;
  let twist = angle + z * spiralTwist * (0.5 + mids) + moveZ;

  var col = vec3<f32>(0.0);
  var alpha = 0.0;
  let nRings = i32(clamp(echoCount, 2.0, 12.0));

  let warmCol = blackbodyRGB(2200.0 + bass * 3000.0);
  let coolCol = blackbodyRGB(7500.0 + treble * 4000.0);

  for (var i: i32 = 0; i < nRings; i++) {
    let fi = f32(i);
    let ringPhase = fract(z * 2.0 - fi * 0.15 + moveZ * 0.3);
    let ringRadius = ringPhase * 0.6;
    let ringWidth = 0.02 + ringPhase * 0.01;
    let ringDist = abs(dist - ringRadius);
    let ringMask = exp(-ringDist * ringDist / (ringWidth * ringWidth));

    let rOffset = bass * 0.03 * ringPhase;
    let gOffset = mids * 0.04 * ringPhase;
    let bOffset = treble * 0.02 * ringPhase;

    let ringR = exp(-abs(dist - (ringRadius + rOffset)) * abs(dist - (ringRadius + rOffset)) / (ringWidth * ringWidth));
    let ringG = exp(-abs(dist - (ringRadius + gOffset)) * abs(dist - (ringRadius + gOffset)) / (ringWidth * ringWidth));
    let ringB = exp(-abs(dist - (ringRadius + bOffset)) * abs(dist - (ringRadius + bOffset)) / (ringWidth * ringWidth));

    let flash = step(0.85, hash11(fi + time * 10.0 * treble)) * treble * flashIntensity;
    let flashMask = ringMask * (1.0 + flash * 3.0);
    let echoFade = 1.0 - fi / echoCount;

    let hue = ringPhase + fi * 0.1;
    let ringColRaw = vec3<f32>(
      0.5 + 0.5 * cos(6.28318 * (hue + 0.0 + bass * 0.1)),
      0.5 + 0.5 * cos(6.28318 * (hue + 0.33 + mids * 0.1)),
      0.5 + 0.5 * cos(6.28318 * (hue + 0.67 + treble * 0.1))
    );
    let ringCol = mixOkLab(ringColRaw * coolCol, warmCol, ringPhase * (1.0 + bass));

    col.r += ringR * ringCol.r * echoFade * flashMask * 1.5;
    col.g += ringG * ringCol.g * echoFade * flashMask * 1.5;
    col.b += ringB * ringCol.b * echoFade * flashMask * 1.5;
    alpha += ringMask * echoFade * flashMask;
  }

  let streak = sin(twist * 6.0) * 0.5 + 0.5;
  let streakMask = exp(-dist * dist * 4.0) * (1.0 - dist * 1.5);
  col += mixOkLab(vec3<f32>(0.4,0.6,1.0), warmCol, 0.3) * streak * streakMask * bass * 1.5;
  alpha += streakMask * bass * 0.5;

  let cStr = 0.005 + bass * 0.008;
  let cDir = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));
  let prevR = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (1.0 + mids), 0.0).r;
  let prevG = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (0.5 + treble), 0.0).g;
  let prevB = textureSampleLevel(dataTextureC, u_sampler, uv01 - cDir * cStr * (0.8 + bass * 0.5), 0.0).b;
  col = mix(col, vec3<f32>(prevR, prevG, prevB) * 0.9, 0.25 + bass * 0.05);

  let dispersed = vec3<f32>(
    col.r + mids * 0.06 * (1.0 - dist),
    col.g + bass * 0.04 * (1.0 - dist),
    col.b + treble * 0.08 * (1.0 - dist)
  );
  col = mix(col, dispersed, 0.4);

  let fog = exp(-dist * 1.5);
  col = col * fog + mixOkLab(vec3<f32>(0.01,0.01,0.03), coolCol * 0.1, 0.5) * (1.0 - fog);

  let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
  col = mix(col, col * coolCol * 1.2, (1.0 - smoothstep(0.0, 0.3, lum)) * 0.25);
  col = mix(col, col * warmCol * 1.3, smoothstep(0.5, 1.0, lum) * 0.3);

  col = hue_preserve_clamp(col, 5.0);
  col = aces(col);
  let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
  col = col + vec3<f32>(dither);

  alpha = clamp(alpha, 0.0, 1.0);
  let depthVal = clamp(1.0 - dist * 2.0, 0.0, 1.0) * alpha;
  let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
  let bloomWeight = pow(max(0.0, luma - 0.5), 2.0) * 3.0;
  let a = max(alpha, bloomWeight * 0.5);

  let outRGB = pow(col, vec3<f32>(1.0/2.2));
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outRGB * a, a));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(col, a));
}
