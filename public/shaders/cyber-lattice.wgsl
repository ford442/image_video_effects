// Cyber Lattice — layered perspective rails, thin-film traffic, and click waves.
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

fn thinFilm(phase: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(vec3<f32>(phase, phase + 2.0943951, phase + 4.1887902));
}

fn latticeMask(p: vec2<f32>, thickness: f32) -> f32 {
  let cell = abs(fract(p) - 0.5);
  let rail = min(cell.x, cell.y);
  return 1.0 - smoothstep(thickness, thickness + 0.035, rail);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let p = (uv - 0.5) * aspectVec;
  let time = u.config.x;
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

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
  let omega = 8.5 + mids * 1.5;
  let springDecay = exp(-omega * dt);
  let springDelta = springPos - rawMouse;
  let springTemp = (springVel + omega * springDelta) * dt;
  springVel = (springVel - omega * springTemp) * springDecay;
  springPos = rawMouse + (springDelta + springTemp) * springDecay;
  springPos = clamp(springPos, vec2<f32>(0.0), vec2<f32>(1.0));
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  let scale = 8.0 + u.zoom_params.x * 42.0;
  let distortion = 0.02 + u.zoom_params.y * 0.32;
  let glow = 0.25 + u.zoom_params.z * 2.4;
  let radius = 0.06 + u.zoom_params.w * 0.62;
  let springP = (springPos - 0.5) * aspectVec;
  let pointerDelta = p - springP;
  let pointerDist = length(pointerDelta);
  let pointerDir = pointerDelta / max(pointerDist, 0.0001);
  let pointerMask = smoothstep(radius, 0.0, pointerDist);

  var wave = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.8) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.30 + bass * 0.10);
      wave += sin((rd - front) * 58.0) * exp(-abs(rd - front) * 24.0) * exp(-age * 1.1);
    }
  }

  let heldStrength = select(0.28, 1.0, held);
  let peel = pointerDir * pointerMask * distortion * heldStrength;
  let waveWarp = pointerDir * wave * distortion * 0.18;
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let depthParallax = (depth - 0.5) * (0.06 + distortion * 0.08);

  let vanishingOffset = springP * 0.42;
  let q = p - vanishingOffset + peel + waveWarp;
  let horizon = 0.24 + abs(q.y) * 0.85 + depth * 0.12;
  let perspective0 = vec2<f32>(q.x / horizon, sign(q.y) * log(1.0 + abs(q.y) * 7.0)) * scale;
  let perspective1 = vec2<f32>((q.x + depthParallax) / (horizon + 0.28), q.y * 2.4) * scale * 0.62;
  let drift0 = vec2<f32>(time * (0.34 + bass * 0.55), -time * (0.12 + mids * 0.26));
  let drift1 = vec2<f32>(-time * (0.18 + mids * 0.30), time * (0.28 + treble * 0.42));
  let grid0 = perspective0 + drift0 + vec2<f32>(sin(q.y * 11.0 + time * 1.7), 0.0) * distortion * scale;
  let grid1 = perspective1 + drift1 + vec2<f32>(0.0, cos(q.x * 9.0 - time * 1.3)) * distortion * scale * 0.7;

  let thickness0 = 0.022 + pointerMask * 0.065 + treble * 0.012;
  let thickness1 = 0.015 + mids * 0.009;
  let mask0 = latticeMask(grid0, thickness0);
  let mask1 = latticeMask(grid1, thickness1) * 0.72;
  let cell0 = floor(grid0);
  let cell1 = floor(grid1);
  let traffic0 = pow(0.5 + 0.5 * sin(cell0.x * 0.91 + cell0.y * 1.37 - time * (4.0 + bass * 4.0)), 12.0) * mask0;
  let traffic1 = pow(0.5 + 0.5 * cos(cell1.x * 1.21 - cell1.y * 0.77 + time * (3.0 + mids * 5.0)), 14.0) * mask1;
  let filmPhase = (grid0.x + grid0.y * 0.73) * 0.65 + depth * 8.0 + time * (0.8 + treble);
  let film = thinFilm(filmPhase);
  let film2 = thinFilm(filmPhase * 1.31 + 1.7);

  let sourceUV = clamp(uv + (peel + waveWarp) / aspectVec + vec2<f32>(depthParallax, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let source = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
  let history = historyAt(uv - springVel * 0.018 - waveWarp / aspectVec * 0.35, resolution);
  let railColor = film * mask0 + film2.bgr * mask1;
  let trafficColor = vec3<f32>(0.25, 1.35, 1.8) * traffic0 * (0.35 + bass)
                   + vec3<f32>(1.7, 0.25, 1.2) * traffic1 * (0.3 + treble);
  var hdr = source.rgb * (0.74 + 0.16 * (1.0 - max(mask0, mask1)));
  hdr += railColor * glow * (0.28 + mids * 0.35);
  hdr += trafficColor * glow * 0.65;
  hdr += thinFilm(wave * 2.0 + time * 0.2) * abs(wave) * glow * 0.45;
  hdr = mix(hdr, history.rgb, clamp(0.04 + max(mask0, mask1) * 0.11, 0.0, 0.18));
  let display = aces(max(hdr, vec3<f32>(0.0)));
  let latticeAlpha = clamp(source.a * 0.28 + max(mask0, mask1) * (0.45 + glow * 0.12) + traffic0 * 0.25 + traffic1 * 0.2, 0.0, 1.0);
  let result = vec4<f32>(display, latticeAlpha);

  textureStore(writeTexture, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, result);
}
