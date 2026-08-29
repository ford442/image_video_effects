// Aurora Borealis Iridescence — geomagnetic aurora ribbons with curl-noise advection, thin-film interference, and spectral shimmer.
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

const PI: f32 = 3.14159265359;

fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
  let q = fract(p * 0.1031);
  return fract((q.x + q.y) * q.z);
}

fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
  let eps = 0.01;
  let n = hash3(vec3<f32>(p, time * 0.1));
  let nx = hash3(vec3<f32>(p + vec2<f32>(eps, 0.0), time * 0.1));
  let ny = hash3(vec3<f32>(p + vec2<f32>(0.0, eps), time * 0.1));
  return vec2<f32>(ny - n, n - nx) / eps;
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

  let ribbonCount = 2.0 + u.zoom_params.x * 6.0;
  let flowSpeed = 0.2 + u.zoom_params.y * 1.5;
  let ribbonWidth = 0.02 + u.zoom_params.z * 0.08;
  let iridescence = 0.3 + u.zoom_params.w * 1.8;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let mousePos = select(vec2<f32>(0.5, 0.35), rawMouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  // Click ripple interaction
  var rippleOffset = vec2<f32>(0.0);
  var rippleWave = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.32 + bass * 0.12);
      let wave = sin((rd - front) * 56.0) * exp(-abs(rd - front) * 24.0) * exp(-age * 1.1);
      rippleOffset += rDelta / max(rd, 0.0001) * wave * 0.025;
      rippleWave += abs(wave) * 0.25;
    }
  }

  // Viewing angle for thin-film interference
  let toCenter = uv - vec2<f32>(0.5);
  let viewDist = length(toCenter);
  let cosTheta = sqrt(max(1.0 - viewDist * viewDist * 0.5, 0.01));
  let filmIOR = 1.45 + iridescence * 0.2;

  let mouseInfluence = exp(-length((uv - mousePos) * aspectVec) * 3.0);
  let stormBoost = select(1.0, 1.6, held);

  var auroraTotal = vec3<f32>(0.0);
  var totalAlpha = 0.0;

  let maxRibbons = 8;
  for (var i = 0; i < maxRibbons; i = i + 1) {
    if (f32(i) >= ribbonCount) { break; }
    let fi = f32(i);

    // Harmonic wave curves
    let freq1 = 1.0 + fi * 0.45;
    let freq2 = 2.2 + fi * 0.35;
    let waveY1 = sin(uv.x * freq1 * PI * 2.0 + time * flowSpeed * 0.4) * (0.12 + bass * 0.06);
    let waveY2 = sin(uv.x * freq2 * PI * 2.0 + time * flowSpeed * 0.6 + fi) * 0.08;

    let curl = curlNoise(vec2<f32>(uv.x * 2.5, time * 0.15 + fi * 0.5), time) * (0.05 + mids * 0.04);
    let magneticPull = (mousePos.y - 0.5) * mouseInfluence * 0.3;

    let ribbonY = 0.35 + fi * 0.06 + waveY1 + waveY2 + curl.y + magneticPull + rippleOffset.y;
    let distY = abs(uv.y - ribbonY);

    let ribbonShape = smoothstep(ribbonWidth * (1.0 + fi * 0.25), 0.0, distY);
    let ribbonGlow = smoothstep(ribbonWidth * 3.5, ribbonWidth * 0.5, distY) * 0.45;

    // Atmospheric oxygen & nitrogen aurora base colors
    let heightFactor = clamp((uv.y - 0.2) / 0.5, 0.0, 1.0);
    let greenIon = vec3<f32>(0.2, 0.95, 0.45);
    let redIon = vec3<f32>(0.92, 0.25, 0.35);
    let purpleIon = vec3<f32>(0.65, 0.2, 0.85);

    var baseAuroraCol = greenIon;
    if (heightFactor < 0.5) {
      baseAuroraCol = mix(greenIon, redIon, heightFactor / 0.5);
    } else {
      baseAuroraCol = mix(redIon, purpleIon, (heightFactor - 0.5) / 0.5);
    }

    // Thin-film iridescent interference layer
    let noiseVal = hash2(uv * 14.0 + time * 0.1 + fi) * 0.5 + hash2(uv * 28.0 - time * 0.15) * 0.25;
    let thickness = mix(320.0, 780.0, ribbonShape) * (0.75 + noiseVal * 0.4);
    let iridCol = thinFilmColor(thickness, cosTheta, filmIOR) * iridescence;

    let fresnel = pow(1.0 - cosTheta, 2.5);
    let ribbonCol = mix(baseAuroraCol, iridCol, fresnel * 0.55 + 0.25) * stormBoost;

    let intensity = (0.6 + 0.4 * sin(uv.x * 8.0 + fi * 1.5 + time * flowSpeed)) * (1.0 + bass * 0.4);
    let layerCol = ribbonCol * intensity * (ribbonShape + ribbonGlow);
    let layerAlpha = (ribbonShape * 0.8 + ribbonGlow * 0.3) * intensity;

    auroraTotal += layerCol * (1.0 - totalAlpha);
    totalAlpha = clamp(totalAlpha + layerAlpha, 0.0, 1.0);
  }

  // Vertical curtain rays
  let curtainRays = pow(max(0.0, sin(uv.x * 90.0 + curlNoise(uv * 3.0, time).x * 5.0)), 6.0) * (0.2 + treble * 0.3);
  auroraTotal += vec3<f32>(0.4, 0.9, 0.6) * curtainRays * totalAlpha;

  // Composite over underlying source image
  let history = historyAt(uv - rippleOffset * 0.5, resolution);

  var hdr = sourceColor.rgb * (1.0 + auroraTotal * 0.4) + auroraTotal * 1.4 + vec3<f32>(rippleWave);
  hdr += history.rgb * 0.06;

  let finalAlpha = clamp(sourceColor.a * 0.6 + totalAlpha * 0.5 + rippleWave * 0.1, 0.0, 1.0);

  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), finalAlpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
