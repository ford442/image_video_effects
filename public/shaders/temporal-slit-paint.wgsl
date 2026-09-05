// ═══════════════════════════════════════════════════════════════════
//  Temporal Slit Paint
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-08-30
//  A packing: raw canvas RGBA (linear paint / coverage) — display is ACES on writeTexture
//  Motion: velocity-stretched brush + traveling slit-head runners
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadC(c: vec2<i32>, maxC: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(c, vec2<i32>(0), maxC), 0);
}

fn brushMask(local: vec2<f32>, size: f32, shapeType: i32, softness: f32) -> f32 {
  var d = length(local);
  let box = length(max(abs(local) - vec2<f32>(size * 0.72), vec2<f32>(0.0)));
  let starA = atan2(local.y, local.x);
  let n = 5.0;
  let sector = TAU / n;
  let a = fract(starA / sector + 0.5) * sector - sector * 0.5;
  let star = cos(a) * length(local);
  let p = pow(pow(abs(local.x), 2.5) + pow(abs(local.y), 2.5), 0.4);
  d = mix(mix(d, p, select(0.0, 1.0, shapeType == 1)), mix(star, box, select(0.0, 1.0, shapeType == 3)), select(0.0, 1.0, shapeType >= 2));
  let inner = size * (1.0 - softness);
  return 1.0 - smoothstep(inner, size, d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let maxC = vec2<i32>(i32(dims.x) - 1, i32(dims.y) - 1);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binA = plasmaBuffer[1].y;
  let binB = plasmaBuffer[5].z;

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
      let omega = 14.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-4.0), vec2<f32>(4.0));
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

  let brushSize = mix(0.01, 0.2, u.zoom_params.x) * (1.0 + bass * 0.15);
  let shapeType = i32(clamp(u.zoom_params.y * 3.0 + 0.5, 0.0, 3.0));
  let softness = u.zoom_params.z;
  let diffusion = u.zoom_params.w;

  let speed = length(springVel);
  let velAng = atan2(springVel.y, springVel.x + 0.0001);
  let stretch = 1.0 + clamp(speed * 0.55, 0.0, 2.2);
  var local = (uv - spring) * vec2<f32>(aspect, 1.0);
  let ca = cos(-velAng);
  let sa = sin(-velAng);
  local = vec2<f32>(local.x * ca - local.y * sa, local.x * sa + local.y * ca);
  local.x = local.x / stretch;

  let mask = brushMask(local, brushSize, shapeType, softness);
  let slitHead = exp(-abs(local.y) * (18.0 + treble * 8.0)) * smoothstep(brushSize * 1.6, 0.0, abs(local.x));
  let runner = pow(max(0.0, sin(local.x * 28.0 - time * (7.0 + mids * 3.0)) * 0.5 + 0.5), 5.0) * slitHead;

  var click = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    let alive = age > 0.0 && age < 2.0;
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    click = click + select(0.0, exp(-abs(rd - age * 0.5) * 14.0) * exp(-age * 1.4), alive);
  }

  let hist = loadC(coord, maxC);
  let n1 = loadC(coord + vec2<i32>(1, 0), maxC);
  let n2 = loadC(coord + vec2<i32>(-1, 0), maxC);
  let n3 = loadC(coord + vec2<i32>(0, 1), maxC);
  let n4 = loadC(coord + vec2<i32>(0, -1), maxC);
  let laplacian = (n1 + n2 + n3 + n4) * 0.25;
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let stamp = max(mask * select(0.15, 1.0, held), runner * 0.65 + click * 0.45);
  var canvas = mix(hist, vec4<f32>(current.rgb, 1.0), clamp(stamp, 0.0, 1.0));
  canvas = mix(canvas, laplacian, diffusion * 0.12);
  canvas.a = clamp(mix(hist.a * 0.992, 1.0, stamp) + runner * 0.08, 0.0, 1.0);

  textureStore(dataTextureA, coord, canvas);

  var hdr = mix(current.rgb, canvas.rgb, canvas.a);
  hdr = hdr + vec3<f32>(0.95, 0.55, 1.0) * runner * (0.25 + binA * 0.1);
  hdr = hdr + vec3<f32>(0.4, 0.9, 1.0) * click * 0.22;
  let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
  hdr = luma + (hdr - vec3<f32>(luma)) * (1.15 + binB * 0.2);
  let rgb = acesToneMap(hdr * 1.06);
  let alpha = clamp(canvas.a * 0.7 + stamp * 0.35 + depth * 0.1, 0.08, 0.98);

  textureStore(writeTexture, coord, vec4<f32>(rgb, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
