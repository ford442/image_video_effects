// Alpha Aurora Bands — multi-layer geomagnetic curtains with discrete spectral emission bands (O 557.7nm, O 630nm, N2 427.8nm).
// A/C stores ACES display RGBA for atmospheric luminescence persistence; B is unused; depth passes through source depth.

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
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u_val = f * f * (3.0 - 2.0 * f);
  let a = hash12(i + vec2<f32>(0.0, 0.0));
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u_val.x), mix(c, d, u_val.x), u_val.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value += amplitude * valueNoise(p * frequency);
    amplitude *= 0.5;
    frequency *= 2.0;
  }
  return value;
}

fn auroraEmission(altitude: f32, particleEnergy: f32, treble: f32) -> vec3<f32> {
  // Oxygen green line: 100-200 km altitude (normalized 0.3-0.6)
  let greenLine = exp(-pow((altitude - 0.45) / 0.12, 2.0)) * particleEnergy * (1.0 + treble * 0.3);
  // Oxygen red line: 200-400 km altitude (normalized 0.6-0.9)
  let redLine = exp(-pow((altitude - 0.75) / 0.18, 2.0)) * particleEnergy * 0.65;
  // Nitrogen blue/violet line: 80-100 km altitude (normalized 0.1-0.3)
  let blueLine = exp(-pow((altitude - 0.22) / 0.11, 2.0)) * particleEnergy * (0.45 + treble * 0.4);
  return vec3<f32>(redLine, greenLine, blueLine);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let intensity = (0.3 + u.zoom_params.x * 1.8) * (1.0 + bass * 0.4);
  let curtainFrequency = mix(2.0, 9.0, u.zoom_params.y);
  let turbulence = (0.2 + u.zoom_params.z * 1.6) * (1.0 + mids * 0.35);
  let speed = (0.05 + u.zoom_params.w * 0.35) * (1.0 + mids * 0.2);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let mousePos = select(vec2<f32>(0.5, 0.5), rawMouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  let windDir = normalize(vec2<f32>(mousePos.x - 0.5, (mousePos.y - 0.5) * 0.5) + vec2<f32>(0.35, 0.0));
  let windStrength = length((mousePos - vec2<f32>(0.5)) * aspectVec) * 2.0 + select(0.5, 1.8, held);

  // Click ripple interactions = auroral substorms
  var ripplePerturb = vec2<f32>(0.0);
  var rippleEnergy = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 3.0) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.35 + bass * 0.15);
      let substorm = exp(-age * 0.8) * exp(-abs(rd - front) * 24.0);
      ripplePerturb += rDelta / max(rd, 0.0001) * substorm * 0.03;
      rippleEnergy += substorm * 1.5;
    }
  }

  var totalEmission = vec3<f32>(0.0);
  var totalAltitude = 0.0;

  for (var layer = 0; layer < 5; layer = layer + 1) {
    let layerF = f32(layer);
    let baseAltitude = 0.2 + layerF * 0.15;

    let noiseUV = vec2<f32>(
      (uv.x + ripplePerturb.x) * curtainFrequency + time * speed * windDir.x * windStrength + layerF * 3.2,
      (uv.y + ripplePerturb.y) * 2.2 + time * speed * 0.35
    );
    let curtainNoise = fbm2(noiseUV, 3);

    let curtainX = sin(uv.x * curtainFrequency * 3.14159 + layerF * 1.5 + time * 0.2) * 0.5 + 0.5;
    let curtainMask = smoothstep(0.28, 0.72, curtainNoise * curtainX + turbulence * 0.2);

    let altitudeVar = baseAltitude + sin(uv.y * 10.0 + time * 0.25 + layerF) * 0.08 + bass * 0.05;
    let altitude = clamp(altitudeVar, 0.0, 1.0);

    let particleEnergy = curtainMask * intensity * (1.0 + rippleEnergy + select(0.0, 0.6, held));
    let emission = auroraEmission(altitude, particleEnergy, treble);

    totalEmission += emission;
    totalAltitude += altitude * particleEnergy;
  }

  totalEmission = clamp(totalEmission, vec3<f32>(0.0), vec3<f32>(4.0));
  let avgAltitude = totalAltitude / (length(totalEmission) + 0.001);

  // Exact previous frame history load for atmospheric glow persistence
  let history = historyAt(uv - ripplePerturb * 0.5, resolution);

  var hdr = src.rgb * 0.8 + totalEmission;
  hdr += history.rgb * 0.055;

  let alpha = clamp(src.a * 0.7 + clamp(avgAltitude * 0.4 + length(totalEmission) * 0.25, 0.0, 0.9), 0.0, 1.0);
  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
