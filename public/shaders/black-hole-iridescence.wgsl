// Black Hole Iridescence — Schwarzschild gravitational lensing, relativistic Doppler accretion disk, and thin-film interference.
// A/C stores ACES display RGBA for relativistic photon persistence; B is unused; depth passes through source depth.

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

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
  let g = 1.0 - abs(t - 0.45) * 2.5;
  let b = 1.0 - smoothstep(0.0, 0.45, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
  let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
  let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
  let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;
  var color = vec3<f32>(0.0);
  var sampleCount = 0.0;
  for (var lambda = 400.0; lambda <= 700.0; lambda = lambda + 30.0) {
    let phase = opd / lambda;
    let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
    color += wavelengthToRGB(lambda) * interference;
    sampleCount = sampleCount + 1.0;
  }
  return color / max(sampleCount, 1.0);
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

  let lensStrength = (0.2 + u.zoom_params.x * 1.8) * (1.0 + bass * 0.35);
  let eventHorizon = (0.05 + u.zoom_params.y * 0.32) * (1.0 + bass * 0.15);
  let diskGlow = 0.2 + u.zoom_params.z * 2.2;
  let iridescence = 0.3 + u.zoom_params.w * 1.8;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let singularity = select(vec2<f32>(0.5, 0.5), rawMouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  // Gravitational wave ripples from clicks
  var gwStrain = vec2<f32>(0.0);
  var gwLuminance = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.38 + bass * 0.15);
      // Quadrupole gravitational metric wave
      let theta = atan2(rDelta.y, rDelta.x);
      let wavePlus = sin((rd - front) * 60.0) * cos(2.0 * theta);
      let envelope = exp(-abs(rd - front) * 26.0) * exp(-age * 1.1);
      gwStrain += rDelta / max(rd, 0.0001) * wavePlus * envelope * 0.03;
      gwLuminance += abs(wavePlus * envelope) * 0.2;
    }
  }

  let delta = (uv - singularity + gwStrain) * aspectVec;
  let dist = length(delta);
  let dir = delta / max(dist, 0.0001);

  var finalRGB = vec3<f32>(0.0);
  var alpha = 1.0;

  let toCenter = uv - vec2<f32>(0.5);
  let viewDist = length(toCenter);
  let cosTheta = sqrt(max(1.0 - viewDist * viewDist * 0.5, 0.01));
  let filmIOR = 1.6;

  if (dist < eventHorizon) {
    // Inside event horizon — deep black with photon ring rim glow
    let rimRatio = dist / eventHorizon;
    let rimGlow = pow(smoothstep(0.75, 1.0, rimRatio), 4.0);
    let rimThickness = mix(250.0, 600.0, rimGlow);
    let rimIrid = thinFilmColor(rimThickness, cosTheta, filmIOR) * iridescence;

    finalRGB = rimIrid * rimGlow * (0.8 + treble * 0.4);
    alpha = mix(1.0, 0.85, rimGlow);
  } else {
    // Gravitational lensing deflection
    let distFromHorizon = dist - eventHorizon;
    let deflection = (lensStrength * 0.08) / (distFromHorizon * 4.5 + 0.06);
    let heldLensing = select(1.0, 1.5, held);
    let lensOffset = dir * deflection * heldLensing;
    let sampleUV = clamp(uv - vec2<f32>(lensOffset.x / aspect, lensOffset.y), vec2<f32>(0.0), vec2<f32>(1.0));
    let bg = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

    // Relativistic accretion disk
    let diskAngle = atan2(delta.y, delta.x);
    let diskRadius = dist / eventHorizon;
    let diskBand = smoothstep(1.0, 1.15, diskRadius) * (1.0 - smoothstep(1.3, 3.2, diskRadius));
    let diskFalloff = exp(-distFromHorizon * 14.0);

    // Relativistic Doppler beaming (approaching side is blueshifted & brighter)
    let orbitSpeed = 1.0 / sqrt(max(diskRadius, 0.8));
    let orbitalVelocity = sin(diskAngle - time * (2.2 + mids * 1.5)) * orbitSpeed;
    let dopplerFactor = 1.0 + orbitalVelocity * 0.55;
    let dopplerTint = mix(vec3<f32>(1.1, 0.4, 0.2), vec3<f32>(0.3, 0.7, 1.2), orbitalVelocity * 0.5 + 0.5);

    // Thin-film interference on the disk
    let noiseVal = hash12(uv * 16.0 + time * 0.15) * 0.5 + hash12(uv * 32.0 - time * 0.2) * 0.25;
    let thickness = mix(280.0, 780.0, diskFalloff) * (0.75 + noiseVal * 0.4);
    let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * iridescence;

    let fresnel = pow(1.0 - cosTheta, 2.5);
    let diskEmission = mix(dopplerTint, iridescent, fresnel * 0.6 + 0.3) * diskGlow * (diskFalloff * 2.8 + diskBand * 1.2) * dopplerFactor;

    // Synchrotron flares from treble
    let synchrotron = pow(max(0.0, sin(diskAngle * 12.0 - time * 8.0 + treble * 5.0)), 12.0) * diskFalloff * (treble * 0.4);

    finalRGB = bg + diskEmission + vec3<f32>(synchrotron);
    alpha = 1.0;
  }

  // Exact previous frame history load for relativistic photon accumulation
  let history = historyAt(uv - gwStrain * 0.5, resolution);

  var hdr = finalRGB + vec3<f32>(gwLuminance);
  hdr += history.rgb * 0.055;

  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
