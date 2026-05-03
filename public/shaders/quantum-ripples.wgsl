// ═══════════════════════════════════════════════════════════════════
//  Quantum Ripples
//  Category: image
//  Features: mouse-driven, interactive, audio-reactive
//  Complexity: Medium
//  Chunks: hash21, fbm2, waveField
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

const TAU = 6.28318530717958647692;
const PHI = 1.61803398874989484820;

// ═══ CHUNK: hash21 ═══
fn hash21(p: vec2<f32>) -> f32 {
  let q = fract(p * vec2<f32>(127.1, 311.7));
  return fract(dot(q, vec2<f32>(269.5, 183.3)));
}

// ═══ CHUNK: fbm2 ═══
fn fbm2(p: vec2<f32>, t: f32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var x = p;
  for (var i = 0; i < 4; i = i + 1) {
    v += a * sin(dot(x, vec2<f32>(1.2, 0.7)) * TAU + t * PHI);
    x = x * 2.03 + vec2<f32>(1.7, 3.1);
    a *= 0.5;
  }
  return v;
}

// ═══ CHUNK: waveField ═══
// Returns displacement vector from a wave source with FBM turbulence
fn waveField(uv: vec2<f32>, center: vec2<f32>, aspect: f32, t: f32,
             freq: f32, spd: f32, turb: f32) -> vec2<f32> {
  let dx = (uv.x - center.x) * aspect;
  let dy = uv.y - center.y;
  let d = sqrt(dx * dx + dy * dy);
  let dir = select(normalize(vec2<f32>(dx, dy)), vec2<f32>(0.0, 0.0), d < 0.001);
  let warp = fbm2(uv * 3.0 + dir * 2.0, t * 0.3) * turb;
  let phase = d * freq - t * spd + warp;
  let harmonic = sin(phase * PHI + TAU * 0.25) * 0.5;
  let w = (sin(phase) + harmonic) * exp(-d * 3.0) * 0.666;
  return dir * w;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  let uv = vec2<f32>(gid.xy) / res;
  let t = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = res.x / res.y;

  let freq = u.zoom_params.x * 24.0 + 2.0;
  let spd  = u.zoom_params.y * 6.0;
  let amp  = u.zoom_params.z * 0.12;
  let csh  = u.zoom_params.w;

  var disp = waveField(uv, mouse, aspect, t, freq, spd, 0.5);

  // Superpose ripple sources (max 8 for performance)
  let rippleCount = u32(u.config.y);
  for (var i = 0u; i < min(rippleCount, 8u); i = i + 1u) {
    let rp = u.ripples[i];
    let age = t - rp.z;
    let rf = freq * (1.0 + hash21(rp.xy) * 0.3);
    disp += waveField(uv, rp.xy, aspect, t, rf, spd * 0.7, 0.25) *
            exp(-age * 2.0) * 0.5;
  }

  let activeAmp = select(1.0, 2.0, u.zoom_config.w > 0.5);
  disp *= amp * activeAmp;

  let srcUV = uv - disp;
  let color = textureSampleLevel(readTexture, u_sampler, srcUV, 0.0);

  let energy = length(disp) / (amp * activeAmp + 0.001);
  var out = color.rgb;
  let shift = energy * csh * sin(t * 0.5) * 0.3;
  out.r += shift;
  out.b -= shift;

  let audio = plasmaBuffer[0].x;
  out += vec3<f32>(energy * audio * 0.15);

  textureStore(writeTexture, gid.xy,
               vec4<f32>(out, energy * (0.5 + audio * 0.5)));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
