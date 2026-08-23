// ═══════════════════════════════════════════════════════════════
//  Digital Waves — Batch 61
//  Interference wave field: spring cursor vortex, held amplify,
//  capped ripples, hex quantize, RGB split, ACES + audio bands.
// ═══════════════════════════════════════════════════════════════

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

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn cyberPalette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.28318 * (vec3<f32>(1.0) * t + vec3<f32>(0.0, 0.33, 0.67)));
}

fn digitalWavePattern(uv: vec2<f32>, time: f32, depth: f32, scale: f32, detail: f32) -> f32 {
  let waveFreq = mix(8.0, 28.0, scale) + depth * 10.0 * detail;
  let waveSpeed = mix(1.0, 4.0, detail);
  var pattern = 0.0;
  pattern += sin(uv.x * waveFreq + time * waveSpeed) * 0.5;
  pattern += sin(uv.y * waveFreq * 0.82 - time * waveSpeed * 0.7) * 0.3;
  pattern += sin((uv.x + uv.y) * waveFreq * 0.55 + time * waveSpeed * 1.15) * 0.2;
  return pattern;
}

fn scanlines(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
  let line = sin((uv.y * 300.0 + time * 50.0) * PI);
  return 1.0 - pow(abs(line), 0.5) * intensity;
}

fn glitchBlocks(uv: vec2<f32>, time: f32, amt: f32) -> vec2<f32> {
  let blockSize = mix(0.02, 0.08, amt);
  let blockPos = floor(uv / blockSize);
  let random = hash21(blockPos + floor(time * 5.0));
  let offset = select(vec2<f32>(0.0), vec2<f32>(
    (hash21(blockPos * 2.0 + time) - 0.5) * 0.1,
    (hash21(blockPos * 3.0 + time) - 0.5) * 0.05
  ), random > 0.92);
  return uv + offset;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let intensity = clamp(u.zoom_params.x, 0.0, 1.0) * (1.0 + bass * 0.3);
  let speed = mix(0.5, 3.0, u.zoom_params.y);
  let scale = clamp(u.zoom_params.z, 0.0, 1.0);
  let detail = clamp(u.zoom_params.w, 0.0, 1.0);

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring) { smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]); }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) { springPos = mouse; springVel = vec2<f32>(0.0); }
    else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 9.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let wavePattern = digitalWavePattern(uv, time * speed, depth, scale, detail);

  let uvAspect = uv * vec2<f32>(aspect, 1.0);
  let mouseAspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
  let interact = smoothstep(0.25, 0.0, length(uvAspect - mouseAspect)) * intensity * select(1.0, 1.4, held);

  var rippleBoost = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.4) {
      let rDist = length(uvAspect - vec2<f32>(rp.x * aspect, rp.y));
      rippleBoost += smoothstep(0.12, 0.0, rDist) * (1.0 - age * 0.75);
    }
  }

  let waveDisplacement = vec2<f32>(
    sin(wavePattern * PI + interact * 4.0) * 0.025,
    cos(wavePattern * PI + rippleBoost * 3.0) * 0.025
  ) * intensity * (1.0 - depth * 0.5);

  var displacedUV = clamp(uv + waveDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));
  displacedUV = glitchBlocks(displacedUV, time, intensity);

  let pixelSize = mix(0.001, 0.006, 1.0 - scale);
  let pixelatedUV = floor(displacedUV / pixelSize) * pixelSize + pixelSize * 0.5;
  displacedUV = mix(displacedUV, pixelatedUV, intensity * 0.35 * detail);

  let splitAmount = abs(sin(time * 0.5)) * 0.006 * intensity * (1.0 + depth);
  let splitAngle = wavePattern + time * 0.3;
  let offset = vec2<f32>(cos(splitAngle), sin(splitAngle)) * splitAmount;
  var color = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(displacedUV - offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  color *= scanlines(uv, time, 0.12 + intensity * 0.08);
  color += hash21(uv * resolution + time * 10.0) * 0.04 * intensity;
  color = floor(color * mix(8.0, 24.0, detail)) / mix(8.0, 24.0, detail);
  color += cyberPalette(wavePattern * 0.5 + time * 0.05) * abs(sin(time * 2.0)) * intensity * 0.08;
  color += vec3<f32>(0.0, 1.0, 1.0) * rippleBoost * 0.35;

  let band = min(u32(uv.x * 8.0), 7u);
  color += cyberPalette(fract(time * 0.08 + f32(band) * 0.1)) * plasmaBuffer[band + 1u].x * 0.06;

  color = acesToneMap(color * (0.95 + bass * 0.1));
  let alpha = clamp(0.55 + intensity * 0.25 + interact * 0.15, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(wavePattern, depth, rippleBoost, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
