// CRT TV — Composer batch cyber/digital/glitch
// Authentic phosphor physics: spring focus, held bulge, capped ripples,
// exact C persistence, three-band audio, ACES + semantic alpha.

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

fn curveUv(uv: vec2<f32>, curvature: f32) -> vec2<f32> {
  var centered = uv * 2.0 - 1.0;
  let distSq = dot(centered, centered);
  centered = centered * (1.0 + curvature * distSq);
  return centered * 0.5 + 0.5;
}

fn inverseCurveUv(uv: vec2<f32>, curvature: f32) -> vec2<f32> {
  var centered = uv * 2.0 - 1.0;
  let distSq = dot(centered, centered);
  centered = centered / (1.0 + curvature * distSq * 0.8);
  return centered * 0.5 + 0.5;
}

fn apertureGrille(uv: vec2<f32>, resolution: vec2<f32>) -> vec3<f32> {
  let pixelX = uv.x * resolution.x;
  let subpixel = fract(pixelX / 3.0) * 3.0;
  var mask = vec3<f32>(0.0);
  let slotWidth = 0.85;
  if (subpixel < slotWidth) { mask.r = 1.0; }
  else if (subpixel < 1.0 + slotWidth) { mask.g = 1.0; }
  else if (subpixel < 2.0 + slotWidth) { mask.b = 1.0; }
  return mask;
}

fn phosphorDecay(baseColor: vec3<f32>, time: f32, flicker: f32) -> vec3<f32> {
  let decayRates = vec3<f32>(2.5, 5.0, 10.0);
  let refreshFlicker = 1.0 - flicker * 0.03 * sin(time * 377.0);
  let humBar = 1.0 - flicker * 0.02 * sin(time * 6.28 * 0.5);
  var decayed = baseColor;
  decayed.r = pow(decayed.r, 1.0 / decayRates.r) * refreshFlicker * humBar;
  decayed.g = pow(decayed.g, 1.0 / decayRates.g) * refreshFlicker * humBar;
  decayed.b = pow(decayed.b, 1.0 / decayRates.b) * refreshFlicker * humBar;
  return decayed;
}

fn halationGlow(uv: vec2<f32>, baseColor: vec3<f32>, strength: f32, curvature: f32, resolution: vec2<f32>) -> vec3<f32> {
  if (strength < 0.01) { return vec3<f32>(0.0); }
  let invRes = 1.0 / resolution;
  var glow = vec3<f32>(0.0);
  var totalWeight = 0.0;
  let offsets = array<vec2<f32>, 5>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0) * invRes * 2.0, vec2<f32>(-1.0, 0.0) * invRes * 2.0,
    vec2<f32>(0.0, 1.0) * invRes * 2.0, vec2<f32>(0.0, -1.0) * invRes * 2.0
  );
  let weights = array<f32, 5>(0.4, 0.15, 0.15, 0.15, 0.15);
  for (var i = 0; i < 5; i = i + 1) {
    let sampleUV = uv + offsets[i];
    let flatSampleUV = inverseCurveUv(sampleUV, curvature);
    if (flatSampleUV.x >= 0.0 && flatSampleUV.x <= 1.0 && flatSampleUV.y >= 0.0 && flatSampleUV.y <= 1.0) {
      let sample = textureSampleLevel(readTexture, u_sampler, flatSampleUV, 0.0).rgb;
      let brightness = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
      glow += smoothstep(0.3, 0.8, brightness) * sample * weights[i];
      totalWeight += weights[i];
    }
  }
  if (totalWeight > 0.0) { glow /= totalWeight; }
  return glow * vec3<f32>(1.1, 0.95, 0.9) * strength * 2.0;
}

fn scanlines(uv: vec2<f32>, resolution: vec2<f32>, intensity: f32, time: f32, audioJitter: f32) -> f32 {
  let scanFreq = resolution.y * 0.5;
  let scanY = uv.y * scanFreq;
  let scanProfile = 0.5 + 0.5 * cos(fract(scanY) * 6.28318530718);
  let phosphorBright = smoothstep(0.0, 0.3, fract(scanY)) * smoothstep(1.0, 0.7, fract(scanY));
  let jitter = sin(time * 10.0 + uv.y * 100.0) * 0.02 * (1.0 + audioJitter * 5.0);
  let thickness = 0.85 + jitter;
  let scanDarken = 1.0 - intensity * 0.4 * (1.0 - smoothstep(thickness, 1.0, scanProfile));
  return scanDarken * (1.0 + intensity * 0.15 * phosphorBright);
}

fn chromaticAberration(uv: vec2<f32>, strength: f32) -> vec3<f32> {
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(strength, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(strength, 0.0), 0.0).b;
  return vec3<f32>(r, g, b);
}

fn crtVignette(uv: vec2<f32>, strength: f32) -> f32 {
  let centered = uv * 2.0 - 1.0;
  let dist = length(centered);
  let vig = 1.0 - smoothstep(0.6, 1.4, dist * (0.8 + strength * 0.4));
  return vig * (1.0 - abs(centered.x * centered.y) * 0.15 * strength);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
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

  let scanlineIntensity = u.zoom_params.x;
  let phosphorGlow = u.zoom_params.y;
  let halationStrength = u.zoom_params.z + treble * 0.5;
  let barrelAmount = u.zoom_params.w;

  var rippleFlash = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      rippleFlash += smoothstep(0.15, 0.0, length((uv - rp.xy) * vec2<f32>(aspect, 1.0))) * (1.0 - age);
    }
  }

  let mouseBulge = smoothstep(0.25, 0.0, length((uv - smoothMouse) * vec2<f32>(aspect, 1.0))) * select(0.0, 0.12, held);
  let curvature = barrelAmount * 0.15 * (1.0 + bass * 0.5 + mouseBulge + rippleFlash * 0.08);
  let flickerAmount = 0.5 + barrelAmount * 0.5 + mids * 0.2;
  let chromaticStr = 0.002 * barrelAmount + treble * 0.005;

  var crtUV = select(uv, curveUv(uv, curvature), barrelAmount > 0.01);
  if (crtUV.x < 0.0 || crtUV.x > 1.0 || crtUV.y < 0.0 || crtUV.y > 1.0) {
    textureStore(writeTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));
    let depth = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    return;
  }

  let baseSample = textureSampleLevel(readTexture, u_sampler, crtUV, 0.0);
  var color = chromaticAberration(crtUV, chromaticStr) * apertureGrille(crtUV, resolution);
  color *= scanlines(crtUV, resolution, scanlineIntensity, time, mids);
  color += halationGlow(crtUV, color, halationStrength, curvature, resolution);

  if (phosphorGlow > 0.01) {
    let brightness = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let bloom = smoothstep(0.4, 0.9, brightness) * phosphorGlow * 0.4;
    color = mix(color, pow(color, vec3<f32>(0.7)), phosphorGlow * 0.3);
    color += color * bloom;
  }

  color = phosphorDecay(color, time, flickerAmount);
  color *= crtVignette(uv, 0.5 + barrelAmount * 0.5);
  color *= 0.95 + fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453) * 0.05;
  color *= vec3<f32>(1.05, 1.02, 0.98);

  let prev = textureLoad(dataTextureC, coord, 0).rgb;
  color = mix(color, prev, 0.08 + phosphorGlow * 0.06);

  color = acesToneMap(color * (0.95 + bass * 0.05));

  let alpha = clamp(baseSample.a * 0.9 + rippleFlash * 0.15 + bass * 0.05, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
