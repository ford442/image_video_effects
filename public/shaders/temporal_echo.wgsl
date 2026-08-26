// Temporal Echo — depth-weighted orbital transport with chromatic exact history.
// A/C stores raw HDR echo RGB plus semantic alpha; writeTexture is ACES display.
// B and extraBuffer are intentionally unused.

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

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  let p = mix(vec4<f32>(c.bg, k.wz), vec4<f32>(c.gb, k.xy), step(c.b, c.g));
  let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
  let d = q.x - min(q.w, q.y);
  let e = 1.0e-10;
  return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let decayRate = 0.018 + u.zoom_params.x * 0.125;
  let hueSpeed = u.zoom_params.y * 0.42;
  let chromaSpread = u.zoom_params.z * 0.020;
  let depthInfluence = clamp(u.zoom_params.w, 0.0, 1.0);
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDist = length(pointerDelta);
  let tangent = vec2<f32>(-pointerDelta.y, pointerDelta.x) / max(pointerDist, 0.0001);
  let orbitMask = smoothstep(0.72, 0.0, pointerDist);
  let heldGain = select(0.32, 1.0, held);

  var echoFront = 0.0;
  var frontVector = vec2<f32>(0.0);
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 3.0) {
      let delta = (uv - ripple.xy) * aspectVec;
      let dist = length(delta);
      let front = age * (0.25 + bass * 0.10);
      let pulse = sin((dist - front) * 66.0) * exp(-abs(dist - front) * 25.0) * exp(-age * 0.9);
      echoFront += pulse;
      frontVector += delta / max(dist, 0.0001) * pulse;
    }
  }

  let orbitalSpeed = (0.0015 + hueSpeed * 0.018) * orbitMask * heldGain *
                     mix(0.35, 1.35, depth * depthInfluence) * (1.0 + mids * 0.6);
  let orbitOffset = tangent / aspectVec * orbitalSpeed;
  let frontOffset = frontVector / aspectVec * (0.003 + chromaSpread * 0.35);
  let breathing = vec2<f32>(sin(time * (0.7 + bass)), cos(time * (0.53 + mids))) *
                  (0.0008 + chromaSpread * 0.15);
  let echoUV = clamp(uv - orbitOffset - frontOffset - breathing, vec2<f32>(0.0), vec2<f32>(1.0));
  let chromaDir = normalize(tangent + frontVector * 0.4 + vec2<f32>(0.0001)) / aspectVec;
  let spread = chromaSpread * (0.25 + orbitMask * 0.75) * (1.0 + treble * 0.45);
  let previousR = historyAt(echoUV + chromaDir * spread, resolution);
  let previousG = historyAt(echoUV, resolution);
  let previousB = historyAt(echoUV - chromaDir * spread, resolution);
  var previousColor = vec3<f32>(previousR.r, previousG.g, previousB.b);
  let previousAlpha = max(previousR.a, max(previousG.a, previousB.a));

  var hsv = rgb2hsv(max(previousColor, vec3<f32>(0.0)));
  hsv.x = fract(hsv.x + hueSpeed * (0.009 + mids * 0.006) + echoFront * 0.012);
  hsv.y = clamp(hsv.y * (0.99 + treble * 0.04), 0.0, 1.0);
  previousColor = hsv2rgb(hsv);

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let brightness = dot(current.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let effectiveDecay = clamp(decayRate * (1.0 - depth * depthInfluence * 0.68) *
                                   (1.0 - bass * 0.22), 0.004, 0.18);
  let persistence = 1.0 - effectiveDecay;
  let injection = clamp(0.07 + brightness * 0.24 + bass * 0.08 +
                        abs(echoFront) * 0.08 + orbitMask * select(0.0, 0.06, held),
                        0.05, 0.42);
  var rawHDR = previousColor * persistence + current.rgb * injection;
  rawHDR += current.rgb * abs(echoFront) * (0.08 + bass * 0.14);
  rawHDR += vec3<f32>(0.18, 0.42, 0.95) * orbitMask * treble * 0.025;
  rawHDR = clamp(rawHDR, vec3<f32>(0.0), vec3<f32>(8.0));
  let rawAlpha = clamp(previousAlpha * persistence + current.a * injection +
                       orbitMask * heldGain * 0.035 + abs(echoFront) * 0.07, 0.0, 1.0);
  let rawState = vec4<f32>(rawHDR, rawAlpha);
  let display = vec4<f32>(aces(rawHDR), rawAlpha);

  textureStore(dataTextureA, coord, rawState);
  textureStore(writeTexture, coord, display);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
