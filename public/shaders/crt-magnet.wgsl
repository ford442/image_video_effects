// CRT Magnet - Optimized Edition
// Category: retro-glitch
// Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba, aces-tone-map
// Complexity: Medium
// Transform: canonical noise/fbm, 16x16 workgroup, unified envelope/mouse state,
//            branchless aperture grille, hex-bloom, ACES tone map.

// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hashf(n: f32) -> f32 { return fract(sin(n * 127.1) * 43758.5453); }
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
  return s;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn spring(current: vec2<f32>, targetPos: vec2<f32>, velocity: ptr<function, vec2<f32>>, k: f32, damping: f32, dt: f32) -> vec2<f32> {
  let force = (targetPos - current) * k - *velocity * damping;
  *velocity = *velocity + force * dt;
  return current + *velocity * dt;
}

fn barrel(uv: vec2<f32>, k: f32) -> vec2<f32> {
  let d = uv - 0.5;
  let r2 = dot(d, d);
  return 0.5 + d * (1.0 + k * r2 + k * k * r2 * r2);
}

fn curl2(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.02;
  let n1 = fbm(p + vec2<f32>(e, 0.0) + t, 4);
  let n2 = fbm(p - vec2<f32>(e, 0.0) + t, 4);
  let n3 = fbm(p + vec2<f32>(0.0, e) + t, 4);
  let n4 = fbm(p - vec2<f32>(0.0, e) + t, 4);
  return vec2<f32>((n3 - n4) / (2.0 * e), (n2 - n1) / (2.0 * e));
}

fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let time = u.config.x;
  let uv01 = vec2<f32>(pixel) / res;
  let mousePos = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let magnetStrength = u.zoom_params.x;
  let bloomIntensity = u.zoom_params.y;
  let colorShift = u.zoom_params.z;
  let distortionRadius = u.zoom_params.w;

  let prevState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let env = bass_env(prevState.r, bass, 0.8, 0.15);
  let smoothMouse = prevState.gb;

  if (global_id.x == 0u && global_id.y == 0u) {
    var prevVel = textureLoad(dataTextureC, vec2<i32>(1, 0), 0).rg;
    var vel = prevVel;
    let newPos = spring(smoothMouse, mousePos, &vel, 8.0, 0.85, 0.016);
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(env, newPos.x, newPos.y, 0.0));
    textureStore(dataTextureA, vec2<i32>(1, 0), vec4<f32>(vel.x, vel.y, 0.0, 0.0));
  }

  let uv = barrel(uv01, 0.15);
  let aspect = res.x / res.y;
  let dVec = uv - smoothMouse;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  let fbmWarp = fbm(uv * 8.0 + time * 0.3, 4) * 0.3 + 0.7;
  let radius = distortionRadius * 0.4 + 0.05;
  let falloff = exp(-dist * dist / (radius * radius * fbmWarp));

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthAtten = mix(0.7, 1.0, depth);

  let field = magnetStrength * falloff * depthAtten * (1.0 + env * 2.0);

  let curl = curl2(uv * 6.0 + smoothMouse * 3.0, time * 0.2);
  let displacement = dVec * field * 4.0 + curl * field * 0.4;

  let beamR = clamp(uv - displacement * 1.35, vec2<f32>(0.0), vec2<f32>(1.0));
  let beamG = clamp(uv - displacement * 1.00, vec2<f32>(0.0), vec2<f32>(1.0));
  let beamB = clamp(uv - displacement * 0.70, vec2<f32>(0.0), vec2<f32>(1.0));
  var color = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, beamR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, beamG, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, beamB, 0.0).b
  );

  let tint = vec3<f32>(1.0 + colorShift * 0.3, 1.0, 1.0 - colorShift * 0.3);
  color = mix(color, color * tint, field * 0.5);

  const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>(0.0, 0.0),
    vec2<f32>(1.0, 0.0), vec2<f32>(0.5, 0.866),
    vec2<f32>(-0.5, 0.866), vec2<f32>(-1.0, 0.0),
    vec2<f32>(-0.5, -0.866), vec2<f32>(0.5, -0.866)
  );
  let bloomSize = (1.0 + bloomIntensity * 5.0) / max(res.x, res.y);
  var bloom = vec3<f32>(0.0);
  for (var i: i32 = 0; i < 7; i++) {
    let tapUV = clamp(uv - displacement + HEX_TAPS[i] * bloomSize, vec2<f32>(0.0), vec2<f32>(1.0));
    bloom += textureSampleLevel(readTexture, u_sampler, tapUV, 0.0).rgb;
  }
  bloom *= 0.142857;

  let bloomThreshold = smoothstep(0.6, 1.0, luma(color));
  color += bloom * bloomThreshold * bloomIntensity * (2.0 + mids * 1.5) + vec3<f32>(treble * 0.05);

  let stripe = f32(global_id.x % 3u);
  let grille = mix(mix(vec3<f32>(0.8, 0.8, 1.15), vec3<f32>(0.8, 1.15, 0.8), step(1.0, stripe)),
                   vec3<f32>(1.15, 0.8, 0.8), step(2.0, stripe));
  color *= mix(vec3<f32>(1.0), grille, clamp(field * 1.2, 0.0, 0.5));

  let vigUV = uv01 - 0.5;
  color *= 1.0 - smoothstep(0.25, 0.55, dot(vigUV, vigUV)) * 0.6;

  color = acesToneMap(color * (0.9 + mids * 0.2));

  let alpha = clamp(field * 1.5 + env * 0.3, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));

  if (global_id.x != 0u || global_id.y != 0u) {
    textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
  }
}
