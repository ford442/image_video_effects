// ═══════════════════════════════════════════════════════════════════
//  Tone Histogram Apply (Pass 2)
//  Category: post-processing
//  Features: multi-pass-2, histogram, auto-exposure, color-grade
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
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<atomic<u32>>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

var<workgroup> wgExposure: f32;
var<workgroup> wgMeanLuma: f32;
var<workgroup> wgContrast: f32;
var<workgroup> wgSaturation: f32;
var<workgroup> wgPeakBinNorm: f32;

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let p = select(vec4<f32>(c.bg, -1.0, 2.0 / 3.0), vec4<f32>(c.gb, 0.0, -1.0 / 3.0), c.b < c.g);
  let q = select(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), p.x < c.r);
  let d = q.x - min(q.w, q.y);
  let e = 1e-5;
  return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let rgb = clamp(abs(fract(c.x + vec3<f32>(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
  return c.z * mix(vec3<f32>(1.0), rgb, c.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(
  @builtin(global_invocation_id) gid: vec3<u32>,
  @builtin(local_invocation_index) lidx: u32,
) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let coord = vec2<i32>(gid.xy);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  if (lidx == 0u) {
    let totalPixels = max(1.0, f32(atomicLoad(&extraBuffer[1])));
    var weighted = 0.0;
    var cumulative = 0.0;
    var p05 = 0u;
    var p95 = 255u;

    let lowCut = totalPixels * 0.05;
    let highCut = totalPixels * 0.95;

    for (var b = 0u; b < 256u; b = b + 1u) {
      let count = f32(atomicLoad(&extraBuffer[3u + b]));
      weighted = weighted + f32(b) * count;
      cumulative = cumulative + count;
      if (cumulative <= lowCut) { p05 = b; }
      if (cumulative <= highCut) { p95 = b; }
    }

    let meanLuma = clamp((weighted / totalPixels) / 255.0, 0.001, 1.0);
    let target = mix(0.35, 0.65, clamp(u.zoom_params.x, 0.0, 1.0));
    let exposure = clamp(target / meanLuma, 0.5, 3.5);

    let tonalSpan = max(4.0, f32(max(1u, p95 - p05)));
    let contrast = mix(0.85, 1.55, clamp(u.zoom_params.y, 0.0, 1.0)) * (255.0 / tonalSpan);
    let saturation = mix(0.80, 1.55, clamp(u.zoom_params.z, 0.0, 1.0));
    let peakBin = atomicLoad(&extraBuffer[2]);

    wgMeanLuma = meanLuma;
    wgExposure = exposure;
    wgContrast = contrast;
    wgSaturation = saturation;
    wgPeakBinNorm = f32(peakBin) / 255.0;
  }
  workgroupBarrier();

  var color = src.rgb * wgExposure;
  color = color / (vec3<f32>(1.0) + color);
  color = clamp((color - 0.5) * wgContrast + 0.5, vec3<f32>(0.0), vec3<f32>(1.0));

  var hsv = rgb2hsv(color);
  hsv.y = clamp(hsv.y * wgSaturation, 0.0, 1.0);

  let peakBin = u32(wgPeakBinNorm * 255.0);
  let psychoMode = u.zoom_params.w > 0.5;
  if (psychoMode && (peakBin < 40u || peakBin > 215u)) {
    let shift = 0.08 * sin(u.config.x * 0.9 + f32(peakBin) * 0.05);
    hsv.x = fract(hsv.x + shift);
  }

  let outColor = hsv2rgb(hsv);

  textureStore(writeTexture, coord, vec4<f32>(outColor, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(wgExposure / 3.5, wgMeanLuma, wgPeakBinNorm, wgSaturation));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
