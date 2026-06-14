// ═══ Oscilloscope Overlay ═══════════════════════════════════════════
//  Category: image
//  Features: mouse-driven, overlay, audio-reactive, hdr, aces-tone-map,
//            color-temperature, dither
//  Complexity: Medium
//  Upgraded: 2026-06-14

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
  zoom_params: vec4<f32>,  // x=Amplitude, y=Thickness, z=WaveOpacity, w=ScanAlpha
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const LUMA_W: vec3<f32> = vec3<f32>(0.2126, 0.7152, 0.0722);

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, LUMA_W);
}

fn toLinear(c: vec3<f32>) -> vec3<f32> {
  return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}

fn toSRGB(c: vec3<f32>) -> vec3<f32> {
  return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn huePreserveClamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  let L = luma(c);
  let s = min(1.0, max_lum / max(L, 1e-4));
  return c * s;
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn linearSrgbToOklab(c: vec3<f32>) -> vec3<f32> {
  let l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
  let m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
  let s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
  let l_ = pow(l, 1.0 / 3.0); let m_ = pow(m, 1.0 / 3.0); let s_ = pow(s, 1.0 / 3.0);
  return vec3<f32>(
    0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
    1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
    0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
  );
}

fn oklabToLinearSrgb(c: vec3<f32>) -> vec3<f32> {
  let l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
  let m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
  let s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
  let l = l_ * l_ * l_; let m = m_ * m_ * m_; let s = s_ * s_ * s_;
  return vec3<f32>(
     4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
  );
}

fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  return oklabToLinearSrgb(mix(linearSrgbToOklab(a), linearSrgbToOklab(b), t));
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

fn gridIntensity(uv: vec2<f32>, spacing: f32, thick: f32) -> f32 {
  let g = fract(uv / spacing + 0.5);
  let d = min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y)) * spacing;
  return smoothstep(thick, 0.0, d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let scanY = u.zoom_config.z;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let amplitude   = u.zoom_params.x * (1.0 + bass * 0.6);
  let thickness   = max(0.0005, u.zoom_params.y * 0.02);
  let waveOpacity = u.zoom_params.z;
  let scanAlpha   = u.zoom_params.w;

  // Sample background once; work in linear light for correct compositing.
  let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var col = toLinear(base.rgb);

  // Shared scanline sample drives both the scan indicator and the waveform.
  let scanSample = textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x, scanY), 0.0).rgb;
  let scanLuma = luma(toLinear(scanSample));

  // Audio-reactive color temperature: warm scan, shifting phosphor, desaturated grid.
  let temp = 2200.0 + 2600.0 * (0.5 + 0.5 * sin(time * 0.22)) + bass * 1600.0;
  let scanCol = toLinear(blackbodyRGB(temp));
  let phosphorCol = mixOkLab(toLinear(vec3<f32>(0.15, 0.95, 0.35)), toLinear(vec3<f32>(0.25, 0.75, 1.0)), 0.35 + mids * 0.35);
  let gridCol = toLinear(vec3<f32>(0.14, 0.30, 0.16)) * (0.7 + treble * 0.5);

  // Scan indicator with a soft outer halo.
  let distScan = abs(uv.y - scanY);
  let scanLine = smoothstep(thickness, 0.0, distScan) * scanAlpha;
  let scanHalo = smoothstep(thickness * 5.0, thickness, distScan) * scanAlpha * 0.25;

  // Luminance-driven waveform with a subtle audio ripple and high-frequency jitter.
  let ripple = sin(uv.x * TAU * 6.0 - time * 4.0) * 0.006 * mids;
  let jitter = sin(uv.x * TAU * 18.0 + time * 7.0) * 0.002 * treble;
  let waveY = 0.5 + (scanLuma - 0.5) * amplitude + ripple + jitter;
  let distWave = abs(uv.y - waveY);
  let waveVal = smoothstep(thickness * 1.4, 0.0, distWave) * waveOpacity;

  // Subtle oscilloscope grid.
  let gridVal = gridIntensity(uv, 0.1, 0.001) * 0.12;

  // Composite in linear HDR space.
  col = mix(col, scanCol * (1.0 + bass * 0.35), scanLine + scanHalo);
  col = col + phosphorCol * waveVal * (1.0 + treble * 0.45);
  col = col + gridCol * gridVal;

  // Depth-aware falloff keeps the overlay from flattening distant content.
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let effectIntensity = scanLine + scanHalo + waveVal * 0.85 + gridVal * 0.2;
  let bloomWeight = clamp(effectIntensity * (0.75 + depth * 0.45), 0.0, 1.0);

  // Tone map + dither stack.
  col = huePreserveClamp(col, 2.8);
  col = acesToneMap(col * (0.9 + mids * 0.2));
  col = toSRGB(col);
  let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
  col = col + vec3<f32>(dither);

  // Premultiplied-alpha writeback: alpha carries the bloom/compositing weight.
  textureStore(writeTexture, pixel, vec4<f32>(col * bloomWeight, bloomWeight));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
