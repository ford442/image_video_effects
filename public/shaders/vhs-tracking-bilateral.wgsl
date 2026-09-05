// VHS Tracking Bilateral — Composer batch cyber/digital/glitch cohort 3
// AR(1) capstan jitter, chroma phase noise, control-track dropouts, tracking-band
// bilateral smoothing, spring tracking bar, held freeze, click dropout pulses,
// exact C smear, ACES + semantic alpha.

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

fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32> {
  return vec3<f32>(
    dot(rgb, vec3<f32>(0.299, 0.587, 0.114)),
    dot(rgb, vec3<f32>(-0.14713, -0.28886, 0.436)),
    dot(rgb, vec3<f32>(0.615, -0.51499, -0.10001))
  );
}

fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32> {
  return vec3<f32>(
    yuv.x + 1.13983 * yuv.z,
    yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z,
    yuv.x + 2.03211 * yuv.y
  );
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 10.0;
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

  let trackingError = u.zoom_params.x;
  let chromaNoiseAmt = u.zoom_params.y;
  let spatialSigma = mix(0.5, 4.0, u.zoom_params.z);
  let colorSigma = mix(0.05, 0.5, u.zoom_params.w);
  let pixelSize = 1.0 / resolution;

  let trackingY = smoothMouse.y;
  let bandDist = abs(uv.y - trackingY);
  let inTrackingBand = 1.0 - smoothstep(0.0, 0.08 + trackingError * 0.12, bandDist);
  let freezeMix = select(1.0, 0.35, held);

  let scanlineIndex = floor(uv.y * resolution.y);
  let arJitter = (noise(vec2<f32>(scanlineIndex * 0.1, time * 0.3)) - 0.5) * trackingError * 0.02 * freezeMix;
  let jitteredUV = vec2<f32>(uv.x + arJitter, uv.y);

  var yuv = rgbToYuv(textureSampleLevel(readTexture, u_sampler, jitteredUV, 0.0).rgb);
  let phaseNoise = sin(uv.y * 120.0 + time * (2.0 + trackingError * 5.0)) * chromaNoiseAmt * 0.1;
  yuv.y += (noise(uv * 300.0 + vec2<f32>(time * 50.0, 0.0)) - 0.5) * chromaNoiseAmt * 0.4 + phaseNoise;
  yuv.z += (noise(uv * 320.0 + vec2<f32>(0.0, time * 45.0)) - 0.5) * chromaNoiseAmt * 0.4 + phaseNoise * 0.7;
  yuv.x += (noise(uv * 200.0 + time * 60.0) - 0.5) * chromaNoiseAmt * 0.08;

  var color = yuvToRgb(yuv);

  let dropoutBase = uv.y * 20.0 - time * 2.0;
  let dropoutPhase = fract(dropoutBase);
  let dropoutEnvelope = exp(-dropoutPhase * 10.0);
  let dropoutRand = hash2(vec2<f32>(floor(dropoutBase), time * 0.5));
  let dropoutActive = step(1.0 - trackingError * 0.3, dropoutRand);
  color += (noise(uv * 500.0 + time * 100.0) - 0.5) * dropoutEnvelope * dropoutActive * 0.5;

  let headSwitchY = trackingY + sin(time * 2.0) * 0.02;
  let headSwitchBand = smoothstep(0.03, 0.0, abs(uv.y - headSwitchY));
  color += (hash2(vec2<f32>(uv.x * 100.0, time * 30.0)) - 0.5) * headSwitchBand * trackingError * 0.3;

  let center = color;
  var accumColor = vec3<f32>(0.0);
  var accumWeight = 0.0;
  let maxRadius = min(i32(ceil(spatialSigma * 2.5)), 5);
  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let neighbor = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
      let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
      let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * spatialSigma * spatialSigma + 0.001));
      let colorDist = length(neighbor - center);
      let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001));
      let weight = spatialWeight * rangeWeight * inTrackingBand;
      accumColor += neighbor * weight;
      accumWeight += weight;
    }
  }
  if (accumWeight > 0.001) {
    color = mix(color, accumColor / accumWeight, 0.6 * inTrackingBand);
  }

  var clickPulse = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.5) {
      let radius = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      clickPulse = max(clickPulse, exp(-age * 2.0) * (1.0 - smoothstep(0.0, 0.1, radius)));
    }
  }
  color += vec3<f32>(0.9, 0.85, 0.75) * clickPulse * 0.4;

  let scanline = sin(uv.y * resolution.y * 0.5 * 3.14159) * 0.5 + 0.5;
  let luma = rgbToYuv(color).x;
  color *= mix(1.0, scanline * mix(0.7, 1.0, luma), 0.15);

  let quantizationSteps = 32.0 + (1.0 - chromaNoiseAmt) * 64.0;
  color = floor(color * quantizationSteps) / quantizationSteps;
  color = mix(vec3<f32>(luma), color, 0.85) * 0.92 + 0.05;

  let prev = textureLoad(dataTextureC, coord, 0).rgb;
  color = mix(color, prev, 0.06 * trackingError + clickPulse * 0.08);

  color = acesToneMap(color * (0.95 + bass * 0.05));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let alpha = clamp(depth * 0.85 + inTrackingBand * 0.1 + clickPulse * 0.2 + bass * 0.05, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
