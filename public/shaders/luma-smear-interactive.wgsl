// ═══════════════════════════════════════════════════════════════════
//  Luma Smear Interactive (Kinetic Echo)
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-08-30
//  A packing: ACES display RGBA (trail energy in alpha)
//  Motion: chromatic R-lag / B-lead streaks + curl-advected exact-C trails
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

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u2.x), mix(c, d, u2.x), u2.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < 3; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.012;
  let n1 = fbm(p + vec2<f32>(eps, 0.0) + t);
  let n2 = fbm(p - vec2<f32>(eps, 0.0) + t);
  let n3 = fbm(p + vec2<f32>(0.0, eps) + t);
  let n4 = fbm(p - vec2<f32>(0.0, eps) + t);
  return vec2<f32>((n3 - n4) / (2.0 * eps), -(n1 - n2) / (2.0 * eps));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadC(uv: vec2<f32>, dims: vec2<f32>) -> vec4<f32> {
  let c = vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(0.999)) * dims);
  return textureLoad(dataTextureC, c, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binMid = plasmaBuffer[3].y;
  let binHi = plasmaBuffer[8].x;

  var spring = mouse;
  var springVel = vec2<f32>(0.0);
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    spring = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var pos = spring;
    var vel = springVel;
    if (extraBuffer[138] <= 0.5) {
      pos = mouse;
      vel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 11.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-3.0), vec2<f32>(3.0));
      pos += vel * dt;
    }
    extraBuffer[133] = pos.x;
    extraBuffer[134] = pos.y;
    extraBuffer[135] = vel.x;
    extraBuffer[136] = vel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    spring = pos;
    springVel = vel;
  }

  let decay = u.zoom_params.x;
  let lumaThreshold = u.zoom_params.y;
  let colorShift = u.zoom_params.z;
  let eraser = u.zoom_params.w;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(src.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let viscosity = mix(1.45, 0.28, depth);

  let aUv = vec2<f32>(uv.x * aspect, uv.y);
  let aMouse = vec2<f32>(spring.x * aspect, spring.y);
  let dist = distance(aUv, aMouse);
  let eraserMask = smoothstep(eraser * 0.28 + 0.02, eraser * 0.08, dist);
  let mouseGust = smoothstep(0.28, 0.0, dist);

  let smearAmt = max(0.0, luma - lumaThreshold) * (0.7 + decay * 1.4) * (1.0 + bass * 0.45);
  let curl = curl2D(uv * 3.2 + time * 0.16, time * 0.28) * (0.006 + mids * 0.004 + binMid * 0.002);
  let dir = normalize(aUv - aMouse + vec2<f32>(0.0001, 0.0));
  var velocity = dir * smearAmt * viscosity * 0.018 + curl;
  velocity = velocity + dir * bass * 0.012 * mouseGust;
  velocity = velocity + clamp(springVel * vec2<f32>(aspect, 1.0) * 0.04, vec2<f32>(-0.08), vec2<f32>(0.08));
  velocity = select(velocity, vec2<f32>(0.0), held && eraserMask > 0.55);

  var clickKick = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    let alive = age > 0.0 && age < 1.8;
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    clickKick = clickKick + select(0.0, exp(-abs(rd - age * 0.7) * 14.0) * exp(-age * 1.6), alive);
  }
  velocity = clamp(velocity * (1.0 + clickKick * 0.8), vec2<f32>(-0.09), vec2<f32>(0.09));

  let persist = mix(0.35, 0.92, decay);
  let shift = 0.55 + colorShift * 1.35;
  let prev = loadC(uv - velocity, dims);
  let rTrail = loadC(uv - velocity * (1.15 + shift * 0.25), dims).r;
  let bTrail = loadC(uv - velocity * (0.72 - colorShift * 0.12), dims).b;
  let chromaPrev = vec3<f32>(rTrail, prev.g, bTrail);

  var hdr = mix(src.rgb, chromaPrev, persist * smearAmt / max(smearAmt + 0.15, 0.001));
  hdr = mix(hdr, src.rgb, eraserMask * select(0.35, 1.0, held));
  hdr = hdr + vec3<f32>(treble * 0.08, treble * 0.05 + binHi * 0.04, clickKick * 0.12);
  let luma2 = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
  hdr = luma2 + (hdr - vec3<f32>(luma2)) * (1.15 + colorShift * 0.35);

  let rgb = acesToneMap(hdr * 1.06);
  let energy = clamp(smearAmt * 0.55 + persist * 0.25 + clickKick * 0.3 + prev.a * persist * 0.4, 0.08, 0.98);
  let outCol = vec4<f32>(rgb, energy);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
