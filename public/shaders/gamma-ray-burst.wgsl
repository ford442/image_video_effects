// ═══════════════════════════════════════════════════════════════════
//  Gamma Ray Burst v2
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Very High
//  Chunks From: gamma-ray-burst, relativistic-jet
//  Upgraded: 2026-05-30
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

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn synchrotron_spectrum(t: f32, freq: f32) -> vec3<f32> {
  let peak = 0.55 + t * 0.25;
  let r = exp(-pow((freq - peak) * 3.5, 2.0));
  let g = exp(-pow((freq - peak + 0.12) * 4.0, 2.0));
  let b = exp(-pow((freq - peak + 0.22) * 5.0, 2.0));
  return vec3<f32>(r, g * 0.85, b * 0.65);
}

fn film_grain(uv: vec2<f32>, t: f32) -> f32 {
  return hash12(uv * 512.0 + t * 73.0) * 0.06 - 0.03;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let aspect = resolution.x / resolution.y;
  let intensity = u.zoom_params.x;
  let decay = max(u.zoom_params.y, 0.02);
  let jetSpread = mix(2.0, 24.0, u.zoom_params.z);
  let exposure = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let p = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = max(length(p), 0.0005);
  let angle = atan2(p.y, p.x);

  let burstPhase = floor(time * 1.5);
  let burstDecay = exp(-fract(time * 1.5) * 3.0);
  let burstTrigger = step(0.65, bass) * burstDecay;

  let lorentz = 1.0 / sqrt(max(1.0 - dist * dist * 0.8, 0.001));
  let dopplerBeaming = pow(lorentz, 3.0);
  let magneticSpiral = sin(angle * jetSpread + dist * 12.0 - time * 3.0 + burstPhase);
  let jetCore = exp(-dist * (4.0 + decay * 16.0)) * dopplerBeaming;
  let jetWings = exp(-abs(magneticSpiral) * (1.5 + decay * 6.0) - dist * (1.2 + decay * 4.0)) * 0.6;
  let burst = intensity * (jetCore * 0.5 + jetWings * 0.5) * (0.4 + burstTrigger * 1.6);

  let aberrationMag = burst * 0.025 * (1.0 + bass * 0.5) * (1.0 + dist * 0.5);
  let chromaDir = normalize(p + vec2<f32>(0.0001));
  let uvR = clamp(uv + chromaDir * aberrationMag * 1.2 / aspect, vec2<f32>(0.001), vec2<f32>(0.999));
  let uvG = clamp(uv + chromaDir * aberrationMag * 0.6 / aspect, vec2<f32>(0.001), vec2<f32>(0.999));
  let uvB = clamp(uv - chromaDir * aberrationMag * 0.9 / aspect, vec2<f32>(0.001), vec2<f32>(0.999));

  let sampled = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
  );

  let freq = dist * 2.0 + mids * 0.3;
  let synchro = synchrotron_spectrum(treble, freq) * burst * 4.0;
  let hdrFlare = vec3<f32>(1.0, 0.78 + mids * 0.18, 0.35 + treble * 0.25) * burst * (1.2 + exposure * 1.5);
  let core = smoothstep(0.06, 0.0, dist) * vec3<f32>(1.0, 0.95, 0.85) * (0.6 + burstTrigger);

  let extinction = depth * 0.35 * (1.0 - burst * 0.3);
  let scattered = sampled * (0.7 + exposure * 0.5) * (1.0 - extinction);
  var hdr = scattered + synchro + hdrFlare + core * (0.5 + bass * 0.35);
  hdr = hdr + film_grain(uv, time);

  let tonemapped = aces_tonemap(hdr);
  let jetIntensity = burst * dopplerBeaming;
  let alpha = clamp((1.0 - extinction) * (0.12 + jetIntensity * 0.5 + burstTrigger * 0.2), 0.06, 0.92);
  let outDepth = clamp(depth + jetIntensity * 0.08, 0.0, 1.0);
  let finalPixel = vec4<f32>(tonemapped, alpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(burst, dopplerBeaming, magneticSpiral, alpha));
}
