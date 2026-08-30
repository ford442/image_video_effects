// ═══════════════════════════════════════════════════════════════════
//  Voronoi Zoom Turbulence
//  Category: geometric
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-08-30
//  A packing: ACES display RGBA (cell agitation in alpha)
//  Motion: per-cell zoom pulses + site-boundary shear conveyors
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn satBoost(rgb: vec3<f32>, amount: f32) -> vec3<f32> {
  let luma = dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  return clamp(luma + (rgb - vec3<f32>(luma)) * (1.0 + amount), vec3<f32>(0.0), vec3<f32>(2.5));
}

fn palette(t: f32) -> vec3<f32> {
  return 0.55 + 0.45 * cos(TAU * (vec3<f32>(1.0, 0.82, 0.58) * t + vec3<f32>(0.00, 0.18, 0.42)));
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
  let binA = plasmaBuffer[1].x;
  let binB = plasmaBuffer[4].y;
  let binC = plasmaBuffer[7].z;

  var spring = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    spring = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var pos = spring;
    var vel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      pos = mouse;
      vel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 10.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-2.5), vec2<f32>(2.5));
      pos += vel * dt;
    }
    extraBuffer[133] = pos.x;
    extraBuffer[134] = pos.y;
    extraBuffer[135] = vel.x;
    extraBuffer[136] = vel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    spring = pos;
  }

  let density = (3.0 + u.zoom_params.x * 5.0) * (1.0 + bass * 0.25 + binA * 0.08);
  let speed = u.zoom_params.y * (1.0 + mids * 0.45);
  let intensity = u.zoom_params.z * (1.0 + treble * 0.4);
  let mouseInfl = u.zoom_params.w;

  let uvScaled = vec2<f32>(uv.x * aspect, uv.y) * density;
  let iSt = floor(uvScaled);
  let fSt = fract(uvScaled);

  var minDist = 8.0;
  var second = 8.0;
  var minPoint = vec2<f32>(0.0);
  var cellId = vec2<f32>(0.0);
  var siteTan = vec2<f32>(1.0, 0.0);

  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      var point = hash22(iSt + neighbor);
      point = 0.5 + 0.5 * sin(time * (0.45 + speed * 0.35) + TAU * point);
      let diff = neighbor + point - fSt;
      let dist = length(diff);
      let closer = dist < minDist;
      second = select(min(second, dist), minDist, closer);
      minPoint = select(minPoint, diff, closer);
      cellId = select(cellId, iSt + neighbor, closer);
      minDist = min(minDist, dist);
    }
  }

  let edge = clamp((second - minDist) * 4.2, 0.0, 1.0);
  let randVal = hash12(cellId);
  let cellTime = time * (0.85 + speed) + randVal * 10.0;
  var zoomFactor = 1.0 + sin(cellTime) * 0.48 * intensity + cos(cellTime * 0.71) * 0.22 * intensity;

  let distMouse = length((uv - spring) * vec2<f32>(aspect, 1.0));
  let infl = smoothstep(0.55, 0.0, distMouse) * abs(mouseInfl);
  let agitate = sin(time * 9.2 + randVal * TAU) * infl * 1.8;
  let stabilize = infl;
  zoomFactor = select(mix(zoomFactor, 1.0, stabilize), zoomFactor + agitate, mouseInfl > 0.0);
  zoomFactor = clamp(zoomFactor, 0.18, 3.4);

  var pulse = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    let alive = age > 0.0 && age < 2.4;
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    let front = exp(-abs(rd - age * 0.55) * 18.0) * exp(-age * 1.4);
    pulse = pulse + select(0.0, front, alive);
  }
  zoomFactor = zoomFactor + pulse * 0.55;

  let offsetFromCenter = -minPoint;
  let zoomShift = offsetFromCenter * (1.0 / max(zoomFactor, 0.12) - 1.0);
  let shearDir = vec2<f32>(-minPoint.y, minPoint.x);
  let shearLen = max(length(shearDir), 0.001);
  let conveyor = (shearDir / shearLen) * (1.0 - edge) * (0.08 + mids * 0.04 + binB * 0.03)
    * sin(time * (4.2 + speed * 2.0) + randVal * TAU);
  let holdPull = select(0.0, 0.12, held) * smoothstep(0.4, 0.0, distMouse);

  let uvScaledNew = uvScaled + zoomShift + conveyor - minPoint * holdPull;
  let uvNew = clamp(vec2<f32>(uvScaledNew.x / aspect, uvScaledNew.y) / max(density, 0.001), vec2<f32>(0.0), vec2<f32>(1.0));

  let src = textureSampleLevel(readTexture, u_sampler, uvNew, 0.0);
  let hist = textureLoad(dataTextureC, coord, 0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvNew, 0.0).r;

  let hueT = randVal + time * 0.07 + binC * 0.12 + minDist * 0.35;
  var hdr = satBoost(src.rgb, 0.28 + treble * 0.2);
  hdr = mix(hdr, hdr * palette(hueT), 0.22 + edge * 0.18);
  hdr = hdr + palette(hueT + 0.33) * pulse * 0.35;
  hdr = mix(hdr, hist.rgb, 0.18 + edge * 0.12);

  let rgb = acesToneMap(hdr * 1.08);
  let agitation = clamp(abs(zoomFactor - 1.0) * 0.85 + (1.0 - edge) * 0.35 + pulse * 0.4, 0.08, 0.98);
  let outCol = vec4<f32>(rgb, mix(src.a, agitation, 0.55));

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
