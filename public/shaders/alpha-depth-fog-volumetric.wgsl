// Alpha Depth Fog Volumetric — layered turbulent extinction with spectral in-scattering.
// A/C packing remains [tone-mapped fogged display rgb, transmittance]. B and extraBuffer are unused.
// Premium mixed-eight upgrade: 2026-08-27.

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

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), w.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0)), w.x), w.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var q = p;
  var value = 0.0;
  var amplitude = 0.5;
  for (var i = 0; i < 4; i = i + 1) {
    value += noise(q) * amplitude;
    q = mat2x2<f32>(0.8, 0.6, -0.6, 0.8) * q * 2.07 + vec2<f32>(4.3, 8.1);
    amplitude *= 0.5;
  }
  return value;
}

fn safeCoord(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<i32> {
  return clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution),
               vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  return textureLoad(dataTextureC, safeCoord(uv, resolution), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);
  let depth = clamp(textureLoad(readDepthTexture, coord, 0).r, 0.0, 1.0);

  let density = mix(0.08, 2.6, u.zoom_params.x) * (1.0 + bass * 0.42);
  let height = mix(0.15, 1.35, u.zoom_params.y);
  let turbulence = mix(0.04, 1.0, u.zoom_params.z);
  let colorTemperature = u.zoom_params.w;
  let distanceThroughFog = max(1.0 - depth, 0.0);
  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDist = length(pointerDelta);
  let pointerClear = exp(-pointerDist * (8.0 + height * 3.0)) * select(0.18, 0.92, held);

  var clickDisturbance = 0.0;
  var clickSwirl = vec2<f32>(0.0);
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 3.6) {
      let delta = (uv - ripple.xy) * aspectVec;
      let rd = length(delta);
      let front = age * (0.21 + bass * 0.08);
      let shell = exp(-abs(rd - front) * 36.0) * exp(-age * 0.72);
      clickDisturbance += shell;
      clickSwirl += vec2<f32>(-delta.y, delta.x) / max(rd, 0.001) / aspectVec * shell;
    }
  }

  var opticalDepth = 0.0;
  var lightEnergy = 0.0;
  for (var layer = 0; layer < 7; layer = layer + 1) {
    let z = (f32(layer) + 0.5) / 7.0 * distanceThroughFog;
    let wind = vec2<f32>(time * (0.025 + mids * 0.035), -time * (0.012 + treble * 0.02));
    let layerUV = uv * mix(2.4, 7.8, z) + wind * (1.0 + z * 1.7) + clickSwirl * turbulence * 0.06;
    let billow = fbm(layerUV + vec2<f32>(z * 9.0, -z * 5.0));
    let vertical = exp(-max(uv.y - (1.0 - height * 0.72), 0.0) * (2.0 + height * 4.0));
    let stratum = mix(0.72, billow * 1.45, turbulence) * vertical;
    opticalDepth += stratum * density * distanceThroughFog / 7.0;
    lightEnergy += pow(max(billow - 0.35, 0.0), 2.0) * (1.0 - z) / 7.0;
  }

  opticalDepth *= 1.0 + clickDisturbance * (0.25 + turbulence * 0.4);
  opticalDepth *= 1.0 - pointerClear;
  let transmittance = clamp(exp(-opticalDepth), 0.0, 1.0);
  let warm = vec3<f32>(1.05, 0.68, 0.36);
  let neutral = vec3<f32>(0.64, 0.72, 0.78);
  let cool = vec3<f32>(0.28, 0.52, 1.08);
  let fogColor = mix(mix(warm, neutral, smoothstep(0.0, 0.5, colorTemperature)),
                     mix(neutral, cool, smoothstep(0.5, 1.0, colorTemperature)),
                     smoothstep(0.38, 0.62, colorTemperature));
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let silverLining = lightEnergy * (0.35 + treble * 0.72) + clickDisturbance * treble * 0.18;
  var hdr = source.rgb * transmittance + fogColor * (1.0 - transmittance) * (0.78 + mids * 0.15);
  hdr += fogColor * silverLining;
  let history = historyAt(uv - vec2<f32>(time * 0.00015, 0.0) - clickSwirl * 0.002, resolution);
  hdr = mix(hdr, history.rgb, clamp(0.02 + turbulence * 0.045, 0.0, 0.07));
  let display = aces(max(hdr, vec3<f32>(0.0)));
  let result = vec4<f32>(display, transmittance);

  textureStore(dataTextureA, coord, result);
  textureStore(writeTexture, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
