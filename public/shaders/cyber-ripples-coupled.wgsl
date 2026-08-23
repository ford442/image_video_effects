// ═══════════════════════════════════════════════════════════════════
//  Cyber Ripples Coupled — Batch 67
//  fp128 ripple phase, exact-load fluid advection, spring mouse [133..138],
//  racing vortex packet, capped click bursts, held deepens vortex, ACES.
//  dataTextureA = SIM STATE (vel.xy, vorticity, density).
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

struct Fp128 {
  base: f32,
  mant: f32,
}

fn fp128(x: f32) -> Fp128 { return Fp128(x, 0.0); }
fn fp128_sum(a: Fp128, b: Fp128) -> Fp128 {
  let s = a.base + b.base;
  let e = (a.base - s) + b.base + a.mant + b.mant;
  let t = s + e;
  return Fp128(t, e - (t - s));
}
fn fp128_mul(a: Fp128, b: Fp128) -> Fp128 {
  let p = a.base * b.base;
  let e = a.base * b.mant + a.mant * b.base;
  let t = p + e;
  return Fp128(t, e - (t - p));
}
fn fp128_val(x: Fp128) -> f32 { return x.base + x.mant; }

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn load_bilinear(tex: texture_2d<f32>, uv: vec2<f32>, res: vec2<f32>) -> vec4<f32> {
  let p = uv * res - 0.5;
  let i0 = vec2<i32>(floor(p));
  let f = fract(p);
  let i1 = i0 + vec2<i32>(1, 1);
  let maxC = vec2<i32>(res) - vec2<i32>(1);
  let c00 = textureLoad(tex, clamp(i0, vec2<i32>(0), maxC), 0);
  let c10 = textureLoad(tex, clamp(vec2<i32>(i1.x, i0.y), vec2<i32>(0), maxC), 0);
  let c01 = textureLoad(tex, clamp(vec2<i32>(i0.x, i1.y), vec2<i32>(0), maxC), 0);
  let c11 = textureLoad(tex, clamp(i1, vec2<i32>(0), maxC), 0);
  return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

fn vortex_packet(uv: vec2<f32>, time: f32, speed: f32) -> f32 {
  let head = fract(time * (0.9 + speed * 2.5));
  return pow(max(0.0, 1.0 - abs(uv.x - head) * 12.0), 4.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let held = u.zoom_config.w > 0.5;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let speed = u.zoom_params.x * 5.0 + 1.0;
  let viscosity = mix(0.92, 0.99, u.zoom_params.y);
  let aberration = u.zoom_params.z * 0.05;
  let frequency = u.zoom_params.w * 50.0 + 10.0;

  let rawMouse = u.zoom_config.yz;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  var mousePos = rawMouse;
  var mouseVel = vec2<f32>(0.0);
  if (hasSpring && extraBuffer[138] > 0.5) {
    mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    mouseVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
    var springPos = mousePos;
    var springVel = mouseVel;
    if (extraBuffer[138] <= 0.5) {
      springPos = rawMouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 10.0;
      let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    mouseVel = springVel;
  }
  let mouseSpeed = length(mouseVel);

  let px = vec2<f32>(1.0) / resolution;
  let prevState = textureLoad(dataTextureC, pixel, 0);
  let prevVel = prevState.xy;
  let prevDens = prevState.w;

  let backUV = clamp(uv - prevVel * px * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
  let advected = load_bilinear(dataTextureC, backUV, resolution);
  var vel = advected.xy * viscosity;
  var dens = advected.w * viscosity;

  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mDist = length(toMouse);
  let mouseRadius = mix(0.03f, 0.15f, 0.5f) * select(1.0f, 1.25f, held);
  let influence = smoothstep(mouseRadius, 0.0, mDist);
  vel = vel + mouseVel * influence * 0.5;
  vel = vel + vec2<f32>(-mouseVel.y, mouseVel.x) * influence * mouseSpeed;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
      vel = vel + outward * rInfluence * 0.3;
      dens = dens + rInfluence * 0.5;
    }
  }

  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  vel = vel * smoothstep(0.05, 0.1, edgeDist);
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);
  let dist = distance(uvCorrected, mouseCorrected);
  let quantizedDist = floor(dist * 20.0) / 20.0;
  let wavePhase = fp128_sum(fp128_mul(fp128(quantizedDist), fp128(frequency)), fp128_mul(fp128(-time), fp128(speed)));
  let wave = sin(fp128_val(wavePhase));
  let strength = 1.0 / (dist * 5.0 + 0.5);
  let packet = vortex_packet(uv, time, speed);
  let displacement = vec2<f32>(wave) * strength * 0.01 + vel * 0.05 + vec2<f32>(packet * 0.008, 0.0);

  var displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let effAberration = aberration * (1.0 + dens) * (1.0 + treble * 0.2);
  let r = textureSampleLevel(readTexture, u_sampler, displacedUV + vec2<f32>(effAberration, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, displacedUV - vec2<f32>(effAberration, 0.0), 0.0).b;

  var color = vec3<f32>(r, g, b);
  color = color * mix(vec3<f32>(1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.3);
  let specNoise = hash12(uv * 300.0 + time * 2.0);
  color = color + vec3<f32>(0.9, 0.95, 1.0) * pow(specNoise, 20.0) * influence * dens * 3.0;
  color = color + vec3<f32>(0.2, 0.9, 1.0) * packet * (0.15 + mids * 0.2);
  color = acesToneMap(color);

  let vorticity = vel.x - vel.y;
  let alpha = clamp(dens * 0.4 + length(vel) * 0.5 + packet * 0.15 + bass * 0.06, 0.06, 0.96);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  textureStore(dataTextureA, pixel, vec4<f32>(vel, vorticity, dens));
  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
