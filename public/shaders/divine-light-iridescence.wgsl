// Divine Light Iridescence — volumetric Crepuscular god rays with thin-film interference and spectral rainbow shimmer.
// A/C stores ACES display RGBA for smooth volumetric beam persistence; B is unused; depth passes through source depth.

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

  let rayIntensity = (0.25 + u.zoom_params.x * 2.2) * (1.0 + bass * 0.45);
  let threshold = 0.15 + u.zoom_params.y * 0.6;
  let softness = 0.05 + u.zoom_params.z * 0.4;
  let rayCount = 4.0 + u.zoom_params.w * 16.0;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let lightPos = select(vec2<f32>(0.5, 0.25), rawMouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  // Click ripple interaction
  var rippleOffset = vec2<f32>(0.0);
  var rippleBurst = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.33 + bass * 0.1);
      let wave = sin((rd - front) * 58.0) * exp(-abs(rd - front) * 25.0) * exp(-age * 1.1);
      rippleOffset += rDelta / max(rd, 0.0001) * wave * 0.02;
      rippleBurst += abs(wave) * 0.2;
    }
  }

  // Vector to light source
  let deltaToLight = (lightPos - uv + rippleOffset);
  let toLightAspect = deltaToLight * aspectVec;
  let distToLight = length(toLightAspect);
  let lightAngle = atan2(toLightAspect.y, toLightAspect.x);

  // Angular beam pattern
  let beamPattern = pow(max(0.0, sin(lightAngle * rayCount + time * 0.5 + mids * 0.8)), 3.0);

  // Radial ray-marching
  let numSteps = 14;
  let stepDelta = deltaToLight / f32(numSteps);
  var marchUV = uv + rippleOffset;
  var rayAccum = vec3<f32>(0.0);
  var decay = 1.0;

  for (var s = 0; s < numSteps; s = s + 1) {
    marchUV -= stepDelta;
    let clampedUV = clamp(marchUV, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleCol = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0).rgb;
    let sampleLuma = dot(sampleCol, vec3<f32>(0.2126, 0.7152, 0.0722));
    let gate = smoothstep(threshold - softness, threshold + softness, sampleLuma);

    rayAccum += sampleCol * gate * decay;
    decay *= 0.94;
  }

  let rayDensity = (rayAccum / f32(numSteps)) * (0.4 + beamPattern * 0.6);

  // Thin-film iridescence calculation
  let toCenter = uv - vec2<f32>(0.5);
  let viewDist = length(toCenter);
  let cosTheta = sqrt(max(1.0 - viewDist * viewDist * 0.5, 0.01));
  let filmIOR = 1.65;
  let noiseVal = hash12(uv * 18.0 + time * 0.2) * 0.5 + hash12(uv * 32.0 - time * 0.15) * 0.25;
  let thickness = mix(300.0, 750.0, clamp(length(rayDensity), 0.0, 1.0)) * (0.8 + noiseVal * 0.4);
  let iridescent = thinFilmColor(thickness, cosTheta, filmIOR);

  let goldenBeam = vec3<f32>(1.0, 0.92, 0.75) * rayDensity * rayIntensity * 3.2;
  let iridBeam = iridescent * rayDensity * rayIntensity * 2.8;

  let fresnel = pow(1.0 - cosTheta, 2.5);
  let heldBoost = select(1.0, 1.5, held);
  let finalRays = mix(goldenBeam, iridBeam, 0.5 + fresnel * 0.5) * heldBoost;

  // Sun halo glow
  let halo = exp(-distToLight * distToLight * 28.0) * rayIntensity * (0.6 + bass * 0.4);
  let haloColor = mix(vec3<f32>(1.0, 0.94, 0.8), iridescent, 0.4) * halo;

  // Treble sparkle
  let sparkle = pow(max(0.0, sin(distToLight * 75.0 - time * 5.0 + treble * 4.0)), 14.0) * (treble * 0.2);

  // Exact previous frame history load for smooth volumetric accumulation
  let history = historyAt(uv - rippleOffset * 0.5, resolution);

  var hdr = sourceColor.rgb + finalRays + haloColor + vec3<f32>(sparkle + rippleBurst);
  hdr += history.rgb * 0.065;

  let rayLuma = dot(finalRays, vec3<f32>(0.2126, 0.7152, 0.0722));
  let finalAlpha = clamp(sourceColor.a * 0.5 + rayLuma * 0.5 + halo * 0.3 + rippleBurst * 0.1, 0.0, 1.0);

  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), finalAlpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
