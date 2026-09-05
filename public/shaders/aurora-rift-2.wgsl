// Aurora Rift 2 — magnetically folded oxygen/nitrogen emission curtains.
// A/C stores ACES display RGBA. B is unused. Source depth passes through.

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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let cell = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(cell), hash21(cell + vec2<f32>(1.0, 0.0)), s.x),
             mix(hash21(cell + vec2<f32>(0.0, 1.0)), hash21(cell + vec2<f32>(1.0)), s.x), s.y);
}

fn fbm3(p: vec2<f32>) -> f32 {
  return noise(p) * 0.57 + noise(p * 2.03 + 13.7) * 0.29 + noise(p * 4.11 - 7.9) * 0.14;
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
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let intensity = 0.25 + u.zoom_params.x * 2.5;
  let speed = 0.12 + u.zoom_params.y * 1.35;
  let depthWeight = u.zoom_params.z;
  let turbulence = 0.4 + u.zoom_params.w * 3.2;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let sourceDepth = textureLoad(readDepthTexture, coord, 0).r;

  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDistance = length(pointerDelta);
  let pointerBend = exp(-pointerDistance * pointerDistance * 9.0) * select(0.35, 1.15, held);
  var ionization = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.7) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.22 + audio.y * 0.055);
      ionization += exp(-abs(rd - front) * 48.0) * exp(-age * 0.9);
    }
  }

  let oxygenGreen = vec3<f32>(0.12, 1.25, 0.42);
  let oxygenRed = vec3<f32>(1.25, 0.16, 0.08);
  let nitrogenBlue = vec3<f32>(0.18, 0.36, 1.5);
  let nitrogenViolet = vec3<f32>(0.72, 0.18, 1.25);
  var accumulatedLight = vec3<f32>(0.0);
  var opticalDepth = 0.0;
  var curtainCoordinate = 0.0;

  for (var layer = 0; layer < 4; layer = layer + 1) {
    let lf = f32(layer);
    let parallax = 0.75 + lf * 0.24;
    let flow = vec2<f32>(time * speed * (0.08 + lf * 0.018), -time * speed * 0.015);
    let fieldUV = vec2<f32>(uv.x * (2.1 + lf * 0.45), uv.y * 1.35) * parallax;
    let lowField = fbm3(fieldUV + flow + vec2<f32>(lf * 9.7));
    let highField = fbm3(fieldUV * (1.8 + turbulence * 0.15) - flow * 0.7 - vec2<f32>(lf * 4.1));
    let magneticFold = sin(uv.x * (10.0 + turbulence * 4.0) + lowField * 5.0 + time * speed + lf * 1.7);
    let bend = pointerBend * (mouse.x - uv.x) * (0.75 + lf * 0.12);
    let centerY = 0.18 + lf * 0.135 + lowField * 0.32 + magneticFold * (0.035 + turbulence * 0.012) + bend;
    let width = 0.035 + highField * 0.055 + audio.y * 0.012;
    let ribbon = exp(-pow((uv.y - centerY) / max(width, 0.01), 2.0));
    let striation = 0.35 + 0.65 * pow(0.5 + 0.5 * sin((uv.x + highField * 0.12) * (82.0 + audio.z * 16.0)), 4.0);
    let density = ribbon * striation * (0.18 + lowField * 0.32) * (1.0 + ionization * 0.65);
    let altitude = clamp(1.0 - centerY, 0.0, 1.0);
    let oxygen = mix(oxygenRed, oxygenGreen, smoothstep(0.2, 0.75, altitude + audio.y * 0.12));
    let nitrogen = mix(nitrogenViolet, nitrogenBlue, smoothstep(0.0, 1.0, highField + audio.z * 0.25));
    let emission = mix(oxygen, nitrogen, clamp(0.18 + lf * 0.13 + audio.z * 0.14, 0.0, 0.72));
    let transmittance = exp(-opticalDepth * (1.35 + depthWeight * 0.7));
    accumulatedLight += emission * density * transmittance * intensity * (0.55 + audio.x * 0.3);
    opticalDepth += density * (0.55 + depthWeight * 0.45);
    curtainCoordinate += centerY * density;
  }

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let absorption = vec3<f32>(0.55, 0.28, 0.72) * opticalDepth;
  let transmitted = source.rgb * exp(-absorption);
  let historyUV = uv - vec2<f32>(speed * 0.0009, 0.0) + pointerDelta * pointerBend * 0.002;
  let history = historyAt(historyUV, resolution);
  var hdr = transmitted + accumulatedLight;
  hdr += history.rgb * clamp(0.025 + opticalDepth * 0.035, 0.0, 0.09);
  hdr += vec3<f32>(0.22, 0.5, 1.15) * ionization * (0.2 + audio.z * 0.35);
  let depthLayer = mix(1.0, mix(0.3, 1.0, sourceDepth), depthWeight);
  let alpha = clamp((1.0 - exp(-opticalDepth * 1.8)) * depthLayer + ionization * 0.12, 0.0, 1.0);
  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(sourceDepth, 0.0, 0.0, 0.0));
}
