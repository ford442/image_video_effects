// ═══════════════════════════════════════════════════════════════════
//  Phantom Lag
//  Category: visual-effects
//  Features: temporal-echo, multi-tap-delay, mouse-velocity-driven, audio-reactive,
//            chromatic-echo, spring-damper-bass, aces-tone-map, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-07-12
// ═══════════════════════════════════════════════════════════════════

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

const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn spring_damper(prev: f32, goal: f32, vel: ptr<function, f32>, k: f32, d: f32) -> f32 {
  let force = (goal - prev) * k;
  (*vel) = (*vel) + force;
  (*vel) = (*vel) * (1.0 - d);
  return prev + (*vel);
}

fn sampleEcho(uv: vec2<f32>, chroma: f32) -> vec3<f32> {
  let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let cR = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let cB = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let w = chroma * c0.a;
  var out = c0.rgb;
  out.r = mix(c0.r, cR.r, w);
  out.b = mix(c0.b, cB.b, w);
  return out;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / resolution;

  let bassRaw = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouseDown = u.zoom_config.w;

  var bassVel = 0.0;
  let bass = spring_damper(extraBuffer[3], bassRaw, &bassVel, 0.1, 0.08);
  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[3] = bass;
  }

  let decay = clamp(0.85 + u.zoom_params.x * 0.13 + bass * 0.05, 0.0, 0.99);
  let echoDistance = u.zoom_params.y * 0.08 * (1.0 + mids * 0.3);
  let tapCountF = clamp(u.zoom_params.z * 4.0 + 1.0, 1.0, 5.0);
  let hueShift = clamp(u.zoom_params.w, 0.0, 1.0);
  let chromaAmt = 0.002 + treble * 0.004;

  let prevMouse = vec2<f32>(extraBuffer[0], extraBuffer[1]);
  let mouse = u.zoom_config.yz;
  let mouseVel = mouse - prevMouse;
  let speed = clamp(length(mouseVel) * 60.0, 0.0, 1.5);

  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[0] = mouse.x;
    extraBuffer[1] = mouse.y;
    extraBuffer[2] = speed;
  }

  let velLen = max(length(mouseVel), 1e-4);
  let echoDir = mouseVel / velLen;
  let sharpness = mix(1.0, 0.4, mouseDown);
  let baseStep = echoDir * echoDistance * (1.0 + speed * 0.5) * sharpness;

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  var accum = vec3<f32>(0.0);
  var w = 0.0;
  var tapWeight = 1.0;
  for (var i = 1; i <= 5; i++) {
    let tapActive = step(f32(i), tapCountF);
    let dist = baseStep * f32(i) / pow(PHI, f32(i - 1));
    let tapUV = clamp(uv - dist, vec2<f32>(0.0), vec2<f32>(1.0));
    let tap = textureSampleLevel(dataTextureC, u_sampler, tapUV, 0.0).rgb;
    let tapChroma = sampleEcho(tapUV, chromaAmt * f32(i) * 0.5);
    let blendedTap = mix(tap, tapChroma, tapActive * 0.35);
    accum += blendedTap * tapWeight * tapActive;
    w += tapWeight * tapActive;
    tapWeight *= mix(1.0, decay, tapActive);
  }
  let echoes = accum / max(w, 1e-4);

  var newHistory = mix(current.rgb, echoes, decay);

  let rot = hueShift * (0.4 + bass * 0.6);
  let cycled = vec3<f32>(newHistory.g, newHistory.b, newHistory.r);
  newHistory = mix(newHistory, cycled, rot * step(0.01, hueShift));

  let aspect = resolution.x / max(resolution.y, 1.0);
  let dMouse = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let cursorMask = exp(-dMouse * dMouse * 4.0);
  let perp = vec2<f32>(-echoDir.y, echoDir.x);
  let stretchUV = clamp(uv + perp * speed * 0.01 * cursorMask, vec2<f32>(0.0), vec2<f32>(1.0));
  let stretch = textureSampleLevel(dataTextureC, u_sampler, stretchUV, 0.0).rgb;
  newHistory = mix(newHistory, stretch, cursorMask * speed * 0.4);

  newHistory = acesToneMap(newHistory * (0.95 + mids * 0.15));

  let luma = dot(newHistory, vec3<f32>(0.299, 0.587, 0.114));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(luma * decay * 0.7 + cursorMask * 0.2 + depth * 0.1 + treble * 0.05, 0.0, 1.0);
  let finalAlpha = mix(current.a, alpha, 0.85);

  let finalColor = vec4<f32>(newHistory, finalAlpha);

  textureStore(writeTexture, coord, finalColor);
  textureStore(dataTextureA, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
