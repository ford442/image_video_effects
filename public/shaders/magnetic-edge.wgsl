// Magnetic Edge — anisotropic edge-field attraction with spectral flux trails.
// A/C stores tone-mapped display RGBA. B is intentionally unused.
// extraBuffer[133..138] stores the single-writer pointer spring.

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

const TAU: f32 = 6.28318530718;

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<i32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  return clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution),
               vec2<i32>(0), hi);
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  return textureLoad(dataTextureC, historyCoord(uv, resolution), 0);
}

fn spectrum(t: f32) -> vec3<f32> {
  return 0.55 + 0.45 * cos(TAU * (vec3<f32>(0.02, 0.35, 0.68) + t));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let texel = vec2<f32>(1.0) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  // Critically damped magnetic pointer. Only invocation (0,0) commits state.
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  var springPos = rawMouse;
  var springVel = vec2<f32>(0.0);
  var previousTime = time;
  var initialized = false;
  if (hasSpring) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    previousTime = extraBuffer[137];
    initialized = extraBuffer[138] > 0.5;
  }
  if (!initialized) {
    springPos = rawMouse;
    springVel = vec2<f32>(0.0);
  }
  let dt = clamp(time - previousTime, 1.0 / 240.0, 1.0 / 20.0);
  let omega = 10.0 + bass * 2.0;
  let decay = exp(-omega * dt);
  let delta = springPos - rawMouse;
  let temp = (springVel + omega * delta) * dt;
  springVel = (springVel - omega * temp) * decay;
  springPos = rawMouse + (delta + temp) * decay;
  springPos = clamp(springPos, vec2<f32>(0.0), vec2<f32>(1.0));
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let lumL = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let lumR = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let lumT = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let lumB = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let gradient = vec2<f32>(lumR - lumL, lumB - lumT);
  let gradMag = length(gradient);
  let normal = gradient / max(gradMag, 0.0001);
  let tangent = vec2<f32>(-normal.y, normal.x);

  let pullStrength = (0.018 + u.zoom_params.x * 0.12) * (1.0 + bass * 0.65);
  let radius = 0.08 + u.zoom_params.y * 0.62;
  let edgeThreshold = 0.015 + u.zoom_params.z * 0.22;
  let glowAmount = 0.1 + u.zoom_params.w * 1.8;
  let edge = smoothstep(edgeThreshold, edgeThreshold * 2.8 + 0.001, gradMag);

  let pointerDelta = (springPos - uv) * aspectVec;
  let pointerDist = length(pointerDelta);
  let radial = pointerDelta / max(pointerDist, 0.0001);
  let influence = smoothstep(radius, 0.0, pointerDist);
  let alignment = abs(dot(radial, normal));
  let anisotropicField = normalize(mix(tangent * sign(dot(radial, tangent) + 0.0001), normal * sign(dot(radial, normal) + 0.0001), 0.28 + alignment * 0.62) + radial * 0.34);

  var shock = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.4) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.32 + bass * 0.08);
      shock += sin((rd - front) * 78.0) * exp(-abs(rd - front) * 34.0) * exp(-age * 1.35);
    }
  }

  let heldGain = select(0.7, 1.8, held);
  let displacement = (anisotropicField * influence * edge * heldGain + radial * shock * 0.45) * pullStrength;
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let depthShift = normal * (depth - 0.5) * edge * 0.012;
  let sampleUV = clamp(uv + displacement + depthShift, vec2<f32>(0.0), vec2<f32>(1.0));
  let displaced = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

  let fluxPhase = atan2(pointerDelta.y, pointerDelta.x) * (5.0 + u.zoom_params.y * 7.0)
                + pointerDist * (42.0 + mids * 10.0) - time * (2.0 + bass * 3.0);
  let fluxLines = pow(0.5 + 0.5 * sin(fluxPhase + shock * 5.0), 10.0) * influence * edge;
  let fluxColor = spectrum(fluxPhase / TAU + time * 0.08 + treble * 0.12);
  let history = historyAt(uv - displacement * 0.45 - springVel * 0.025, resolution);

  let chroma = normal * edge * glowAmount * (0.0015 + treble * 0.0025);
  let red = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + chroma, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let blue = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - chroma, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var hdr = vec3<f32>(red, displaced.g, blue);
  hdr += fluxColor * fluxLines * glowAmount * (0.5 + treble);
  hdr += vec3<f32>(0.05, 0.65, 1.15) * edge * influence * glowAmount * (0.18 + mids * 0.35);
  hdr = mix(hdr, history.rgb, clamp(0.05 + edge * influence * 0.14, 0.0, 0.22));
  let display = aces(max(hdr, vec3<f32>(0.0)));
  let alpha = clamp(center.a * 0.35 + edge * (0.35 + influence * 0.45) + fluxLines * 0.35, 0.0, 1.0);
  let result = vec4<f32>(display, alpha);

  textureStore(writeTexture, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, result);
}
