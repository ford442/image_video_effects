// Waveform Glitch — Composer batch cyber/digital/glitch
// Oscilloscope Lissajous + signal aliasing: spring cursor, held burst,
// capped ripples, exact C phosphor trails, three-band audio, ACES + semantic alpha.

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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn lissajous(uv: vec2<f32>, t: f32, freqX: f32, freqY: f32, phase: f32, thickness: f32) -> f32 {
  let centered = uv * 2.0 - 1.0;
  var minDist = 1.0;
  let steps = 64.0;
  for (var i = 0.0; i < steps; i += 1.0) {
    let pt = i * TAU / steps;
    let lx = sin(freqX * pt + t);
    let ly = sin(freqY * pt + t + phase);
    let dist = length(centered - vec2<f32>(lx, ly) * 0.8);
    minDist = min(minDist, dist);
  }
  return smoothstep(thickness, thickness * 0.2, minDist);
}

fn signalAliasing(uv: vec2<f32>, sampleRate: f32) -> vec2<f32> {
  return floor(uv * sampleRate) / sampleRate;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let aspect = res.x / max(res.y, 1.0);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 9.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let waveIntensity = u.zoom_params.x * (1.0 + bass * 0.8) * select(1.0, 1.3, held);
  let vhsIntensity = u.zoom_params.y * (1.0 + mids * 0.5);
  let aliasingFactor = mix(200.0, 20.0, u.zoom_params.z);
  let scopeIntensity = u.zoom_params.w;

  var rippleWarp = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.2) {
      rippleWarp += smoothstep(0.14, 0.0, length((uv - rp.xy) * vec2<f32>(aspect, 1.0))) * (1.0 - age * 0.85);
    }
  }

  let mousePull = (uv - smoothMouse) * exp(-length((uv - smoothMouse) * vec2<f32>(aspect, 1.0)) * 6.0) * 0.02 * select(0.0, 1.0, held);
  let aliasedUV = signalAliasing(uv + mousePull, aliasingFactor + treble * 50.0);

  let beatFreq = time * (1.0 + bass * 2.0);
  let waveX = sin(aliasedUV.y * 50.0 + beatFreq) * 0.05 * waveIntensity;
  let waveY = cos(aliasedUV.x * 40.0 - beatFreq * 0.8) * 0.03 * waveIntensity;
  let displacedUV = clamp(aliasedUV + vec2<f32>(waveX + rippleWarp * 0.03, waveY), vec2<f32>(0.0), vec2<f32>(1.0));

  let baseSample = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  let r = textureSampleLevel(readTexture, u_sampler, displacedUV + vec2<f32>(0.01 * vhsIntensity, 0.0), 0.0).r;
  let g = baseSample.g;
  let b = textureSampleLevel(readTexture, u_sampler, displacedUV - vec2<f32>(0.01 * vhsIntensity, 0.0), 0.0).b;
  var col = vec3<f32>(r, g, b);

  let lissX = 3.0 + floor(mids * 2.0);
  let lissY = 2.0 + floor(bass * 2.0);
  let lissPhase = PI * 0.25 * treble;
  let lissPattern = lissajous(uv, time * 2.0, lissX, lissY, lissPhase, 0.02 + bass * 0.02);
  col += vec3<f32>(0.2, 1.0, 0.4) * lissPattern * scopeIntensity * 2.0;

  let scanline = sin(uv.y * res.y * PI) * 0.2 + 0.8;
  let blanking = step(0.05, fract(time * 5.0 + uv.y * 2.0));
  col = col * scanline * mix(1.0, blanking, vhsIntensity * 0.5);

  let bandBin = min(u32(uv.x * 8.0), 7u) + 1u;
  col += vec3<f32>(0.0, plasmaBuffer[bandBin].x * 0.08, plasmaBuffer[bandBin].y * 0.04) * scopeIntensity;

  let prev = textureLoad(dataTextureC, pixel, 0);
  let persistence = mix(0.15, 0.55, u.zoom_params.z);
  let trail = mix(col, prev.rgb, persistence * (0.85 + bass * 0.1));
  col = mix(col, trail, 0.55 + bass * 0.15);

  col = acesToneMap(col * (0.95 + bass * 0.05));

  let waveMag = abs(waveX) + abs(waveY) + lissPattern * scopeIntensity;
  let alpha = clamp(baseSample.a * (1.0 - waveMag * 0.2) + waveMag * 0.35 + rippleWarp * 0.15, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
