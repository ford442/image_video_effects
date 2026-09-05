// Interactive PCB Traces — Manhattan routing, vias, and propagating signal packets.
// A/C stores ACES display RGBA for persistent phosphor-like trace glow. B is unused.

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

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let x = fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
  let y = fract(sin(dot(p, vec2<f32>(269.5, 183.3))) * 43758.5453);
  return vec2<f32>(x, y);
}

fn segmentDistance(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
  return length(pa - ba * h);
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
  let gridScale = 8.0 + u.zoom_params.x * 32.0;
  let pulseSpeed = 0.7 + u.zoom_params.y * 5.3;
  let glowAmount = 0.35 + u.zoom_params.z * 2.9;
  let background = 0.08 + u.zoom_params.w * 0.72;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;

  let grid = vec2<f32>(uv.x * aspect, uv.y) * gridScale;
  let cellId = floor(grid);
  let local = fract(grid);
  let random = hash22(cellId);
  let padCenter = 0.24 + random * 0.52;
  let horizontalFirst = random.x > 0.5;
  let edgeTarget = select(vec2<f32>(select(0.0, 1.0, random.y > 0.5), padCenter.y), vec2<f32>(padCenter.x, select(0.0, 1.0, random.y > 0.5)), horizontalFirst);
  let elbow = select(vec2<f32>(edgeTarget.x, padCenter.y), vec2<f32>(padCenter.x, edgeTarget.y), horizontalFirst);
  let primaryDistance = min(segmentDistance(local, padCenter, elbow), segmentDistance(local, elbow, edgeTarget));

  let branchDirection = select(vec2<f32>(0.0, select(-1.0, 1.0, random.x > 0.5)), vec2<f32>(select(-1.0, 1.0, random.x > 0.5), 0.0), horizontalFirst);
  let branchEnd = clamp(elbow + branchDirection * (0.18 + random.y * 0.2), vec2<f32>(0.05), vec2<f32>(0.95));
  let branchDistance = segmentDistance(local, elbow, branchEnd);
  let traceWidth = 0.022 + 0.007 * audio.z;
  let trace = 1.0 - smoothstep(traceWidth, traceWidth * 2.6, min(primaryDistance, branchDistance));
  let traceHalo = exp(-min(primaryDistance, branchDistance) * (18.0 + 8.0 / glowAmount));

  let padDistance = length(local - padCenter);
  let pad = 1.0 - smoothstep(0.105, 0.135, padDistance);
  let drill = 1.0 - smoothstep(0.03, 0.048, padDistance);
  let viaRing = clamp(pad - drill, 0.0, 1.0);
  let routeLength = distance(padCenter, elbow) + distance(elbow, edgeTarget);
  let routeCoordinate = (distance(local, padCenter) + dot(local - padCenter, normalize(edgeTarget - padCenter + vec2<f32>(0.0001)))) / max(routeLength, 0.1);
  let packetPhase = fract(routeCoordinate * 0.34 - time * pulseSpeed * 0.12 - random.x + audio.x * 0.08);
  let packet = exp(-pow((packetPhase - 0.5) * (18.0 + audio.y * 4.0), 2.0)) * (trace + viaRing);

  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDistance = length(pointerDelta);
  let hoverInjection = exp(-pointerDistance * pointerDistance * 22.0) * (traceHalo + viaRing);
  let heldInjection = select(0.0, exp(-pointerDistance * pointerDistance * 95.0), held) * (trace + viaRing);
  var clickPropagation = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.8) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.3 + pulseSpeed * 0.025 + audio.x * 0.04);
      clickPropagation += exp(-abs(rd - front) * 52.0) * exp(-age * 1.0) * (traceHalo + viaRing);
    }
  }

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceLuma = dot(source.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let substrate = mix(source.rgb * background, vec3<f32>(0.012, 0.085, 0.045) * (0.55 + sourceLuma), 0.62);
  let copper = vec3<f32>(1.05, 0.48, 0.08) * (0.55 + audio.x * 0.22);
  let solder = vec3<f32>(0.58, 0.72, 0.68);
  let signalColor = 0.6 + 0.4 * cos(TAU * (vec3<f32>(0.1, 0.45, 0.78) + packetPhase + audio.y * 0.08));
  let history = historyAt(uv, resolution);
  var hdr = substrate;
  hdr = mix(hdr, copper, trace * 0.78);
  hdr = mix(hdr, solder, viaRing * 0.86);
  hdr *= 1.0 - drill * 0.72;
  let signal = packet + hoverInjection * 0.45 + heldInjection * 0.9 + clickPropagation;
  hdr += signalColor * signal * glowAmount * (0.5 + audio.z * 0.45);
  hdr += copper * traceHalo * glowAmount * 0.12;
  hdr += history.rgb * clamp(signal * 0.055 + trace * 0.012, 0.0, 0.11);
  let alpha = clamp(0.18 + trace * 0.34 + viaRing * 0.42 + signal * 0.32 + source.a * background * 0.18, 0.0, 1.0);
  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
