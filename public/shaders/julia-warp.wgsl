// Julia Warp — derivative-aware orbit traps and refractive complex dynamics.
// A/C stores ACES display RGBA. B is unused.

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

fn complexMultiply(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn spectrum(t: f32) -> vec3<f32> {
  return 0.52 + 0.48 * cos(TAU * (vec3<f32>(0.02, 0.35, 0.68) + t));
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
  let intensity = 0.02 + u.zoom_params.x * 0.16;
  let juliaScale = 0.8 + u.zoom_params.y * 2.5;
  let depthWeight = u.zoom_params.z;
  let maxIterations = 18 + i32(u.zoom_params.w * 46.0);
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;

  let mouseComplex = (mouse - 0.5) * vec2<f32>(1.35, -1.05);
  let animatedC = vec2<f32>(
    -0.72 + cos(time * (0.17 + audio.y * 0.04)) * 0.16,
    0.19 + sin(time * (0.23 + audio.z * 0.035)) * 0.18
  );
  let c = mix(animatedC, mouseComplex, select(0.18, 0.62, held));
  let heldZoom = select(1.0, 0.58 + 0.08 * sin(time * 1.7), held);
  let centered = (uv - mouse * 0.18 - vec2<f32>(0.41)) * aspectVec * juliaScale * heldZoom;

  var z = centered;
  var derivative = vec2<f32>(1.0, 0.0);
  var orbitTrap = 10.0;
  var axisTrap = 10.0;
  var escapedAt = f32(maxIterations);
  var lastRadius = length(z);
  for (var i = 0; i < 64; i = i + 1) {
    if (i >= maxIterations) { break; }
    derivative = complexMultiply(2.0 * z, derivative);
    z = complexMultiply(z, z) + c;
    let radius = length(z);
    orbitTrap = min(orbitTrap, abs(radius - (0.52 + audio.y * 0.08)));
    axisTrap = min(axisTrap, min(abs(z.x), abs(z.y)));
    lastRadius = radius;
    if (dot(z, z) > 64.0) {
      escapedAt = f32(i);
      break;
    }
    derivative = clamp(derivative, vec2<f32>(-10000.0), vec2<f32>(10000.0));
  }

  let smoothIteration = escapedAt - log2(max(log2(max(lastRadius, 1.0001)), 0.0001));
  let iterationPhase = clamp(smoothIteration / f32(maxIterations), 0.0, 1.0);
  let derivativeMagnitude = max(length(derivative), 0.001);
  let distanceEstimate = clamp(0.5 * log(max(lastRadius, 1.0001)) * lastRadius / derivativeMagnitude, 0.0, 1.0);
  let derivativeDirection = derivative / derivativeMagnitude;
  let trapRidge = exp(-orbitTrap * (32.0 + audio.z * 14.0));
  let axisEngraving = exp(-axisTrap * 45.0);

  var shock = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.24 + audio.x * 0.04);
      shock += sin((rd - front) * 64.0) * exp(-abs(rd - front) * 38.0) * exp(-age * 1.05);
    }
  }

  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerLens = exp(-dot(pointerDelta, pointerDelta) * 16.0);
  let refractiveDirection = normalize(vec2<f32>(derivativeDirection.x - derivativeDirection.y, derivativeDirection.x + derivativeDirection.y) + vec2<f32>(0.0001));
  let displacement = refractiveDirection * intensity * (trapRidge * 0.65 + distanceEstimate * 0.35) * (1.0 + audio.x * 0.3)
                   + (pointerDelta / max(length(pointerDelta), 0.0001)) * pointerLens * select(0.006, 0.022, held)
                   + normalize(pointerDelta + vec2<f32>(0.0001)) * shock * 0.012;
  let warpedUV = clamp(uv + displacement / aspectVec, vec2<f32>(0.0), vec2<f32>(1.0));
  let source = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
  let chroma = refractiveDirection / aspectVec * (0.001 + u.zoom_params.x * 0.004 + audio.z * 0.0015);
  let red = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + chroma, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let blue = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV - chroma, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let history = historyAt(uv - displacement * 0.35, resolution);

  let orbitColor = spectrum(iterationPhase + trapRidge * 0.23 + time * 0.025 + audio.y * 0.08);
  var hdr = vec3<f32>(red, source.g, blue);
  hdr += orbitColor * (trapRidge * 0.85 + axisEngraving * 0.25) * (0.55 + audio.z * 0.5);
  hdr += history.rgb * clamp(0.025 + trapRidge * 0.055, 0.0, 0.095);
  let edgeDistance = min(min(warpedUV.x, 1.0 - warpedUV.x), min(warpedUV.y, 1.0 - warpedUV.y));
  let edgeFade = smoothstep(0.0, 0.055, edgeDistance);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r;
  let alpha = clamp(source.a * edgeFade * (0.45 + distanceEstimate * 0.35) + trapRidge * 0.38 + abs(shock) * 0.12, 0.0, 1.0);
  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth * (1.0 + iterationPhase * depthWeight * 0.1), 0.0, 0.0, 0.0));
}
