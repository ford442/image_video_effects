// Aurora Borealis — flowing atmospheric ribbons with curl noise, oxygen/nitrogen emission spectra, and geomagnetic interaction.
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

fn auroraRibbon(x: f32, t: f32, ribbonId: f32) -> vec2<f32> {
  let freq1 = 1.0 + ribbonId * 0.45;
  let freq2 = 2.0 + ribbonId * 0.3;
  let y1 = sin(x * freq1 * PI * 2.0 + t * 0.35) * 0.14;
  let y2 = sin(x * freq2 * PI * 2.0 + t * 0.5 + ribbonId) * 0.09;
  return vec2<f32>(x, 0.48 + y1 + y2);
}

fn auroraColor(height: f32, intensity: f32, treble: f32) -> vec3<f32> {
  let green = vec3<f32>(0.18, 0.95, 0.42);
  let red = vec3<f32>(0.92, 0.28, 0.22);
  let purple = vec3<f32>(0.65, 0.22, 0.88) * (1.0 + treble * 0.3);
  var col = green;
  if (height < 0.3) {
    col = green;
  } else if (height < 0.6) {
    col = mix(green, red, (height - 0.3) / 0.3);
  } else {
    col = mix(red, purple, (height - 0.6) / 0.4);
  }
  return col * intensity;
}

fn stars(uv: vec2<f32>, time: f32) -> vec3<f32> {
  let starUV = uv * 120.0;
  let starHash = hash2(floor(starUV));
  let star = step(0.988, starHash);
  let twinkle = sin(time * 3.5 + starHash * 10.0) * 0.5 + 0.5;
  return vec3<f32>(star * twinkle);
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

  let numRibbons = i32(3.0 + u.zoom_params.x * 5.0);
  let flowSpeed = (0.2 + u.zoom_params.y * 0.6) * (1.0 + mids * 0.25);
  let ribbonWidth = 0.02 + u.zoom_params.z * 0.06;
  let glowIntensity = (0.4 + u.zoom_params.w * 1.5) * (1.0 + bass * 0.35);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let mousePos = select(vec2<f32>(0.5, 0.5), rawMouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  // Click ripple interactions = geomagnetic shock pulses
  var ripplePerturb = vec2<f32>(0.0);
  var rippleGlow = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.35 + bass * 0.12);
      let wave = sin((rd - front) * 52.0) * exp(-abs(rd - front) * 22.0) * exp(-age * 1.1);
      ripplePerturb += rDelta / max(rd, 0.0001) * wave * 0.035;
      rippleGlow += abs(wave) * 0.25;
    }
  }

  let mouseInfluence = smoothstep(0.55, 0.0, length((uv - mousePos) * aspectVec));

  // Starfield in background
  let starField = stars(uv + ripplePerturb * 0.2, time) * (0.6 + treble * 0.4);

  var auroraRGB = vec3<f32>(0.0);
  var auroraCoverage = 0.0;

  for (var i: i32 = 0; i < numRibbons; i = i + 1) {
    let fi = f32(i);
    let ribbonBase = auroraRibbon(uv.x + ripplePerturb.x, time * flowSpeed, fi);

    let curl = curlNoise(vec2<f32>(uv.x * 2.2, time * 0.2), time);
    var ribbonPos = ribbonBase + curl * 0.08 * (1.0 + bass * 0.4);

    if (hasMouse) {
      let toMouse = mousePos - ribbonPos;
      ribbonPos += toMouse * mouseInfluence * select(0.2, 0.45, held);
    }

    let dist = abs(uv.y + ripplePerturb.y - ribbonPos.y);
    let width = ribbonWidth * (1.0 + fi * 0.25);
    let ribbonShape = smoothstep(width, 0.0, dist);

    let intensityMod = (sin(uv.x * 10.0 + fi * 1.5 + time * 1.2) * 0.5 + 0.5) * (1.0 + bass * 0.3);
    let height = clamp((uv.y - 0.3) / 0.45, 0.0, 1.0);
    let color = auroraColor(height, intensityMod * glowIntensity, treble);

    let glow = smoothstep(width * 3.5, width, dist) * glowIntensity * 0.45;
    let contribution = color * (ribbonShape + glow);
    let alpha = ribbonShape * 0.8 + glow * 0.25;

    auroraRGB += contribution * (1.0 - auroraCoverage);
    auroraCoverage = min(auroraCoverage + alpha, 1.0);
  }

  // Curtain ray modulation
  let curtainRays = sin((uv.x + uv.y * 0.5) * 45.0 + time * 0.4) * 0.5 + 0.5;
  auroraRGB *= 0.85 + curtainRays * 0.25;

  // Composite background with stars and aurora
  let bg = mix(src.rgb, src.rgb * 0.65 + starField * 0.35, 0.4);
  var hdr = bg + auroraRGB + vec3<f32>(rippleGlow);

  // Exact previous frame history load for continuous atmospheric persistence
  let history = historyAt(uv - ripplePerturb * 0.5, resolution);
  hdr += history.rgb * 0.06;

  let alpha = clamp(src.a * 0.7 + auroraCoverage * 0.6 + length(starField) * 0.2, 0.0, 1.0);
  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
