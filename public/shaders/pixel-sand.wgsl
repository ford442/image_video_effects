// ═══════════════════════════════════════════════════════════════════
//  Pixel Sand
//  Category: simulation
//  Features: granular, mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-12, 2026-11-15
//  Ideas: diagonal rest from up-diagonals; kinetic sparkle from energy; scene-depth 3D collision ledges & divergence-free streamfunction curl; live top-hopper Particle Density emitter & shear blackbody (§12.2F)
//  A packing: raw (density, vx, vy, kinetic energy)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn grainAt(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Incompressible 2D streamfunction curl (dPsi/dy, -dPsi/dx)
fn streamCurl(uv: vec2<f32>, time: f32, mids: f32) -> vec2<f32> {
  let t = time * (0.45 + mids * 0.55);
  let kx1 = 15.0;
  let ky1 = 13.0;
  let dPsiDx = kx1 * cos(uv.x * kx1 + t) * cos(uv.y * ky1 - t * 0.8)
    + 11.0 * cos((uv.x - uv.y) * 22.0 - t * 1.2);
  let dPsiDy = -ky1 * sin(uv.x * kx1 + t) * sin(uv.y * ky1 - t * 0.8)
    - 11.0 * cos((uv.x - uv.y) * 22.0 - t * 1.2);
  return vec2<f32>(dPsiDy, -dPsiDx) / 20.0;
}

fn blackbodySand(temp: f32) -> vec3<f32> {
  let c0 = vec3<f32>(1.35, 0.52, 0.08);
  let c1 = vec3<f32>(2.25, 0.28, 0.04);
  let c2 = vec3<f32>(2.85, 1.75, 0.45);
  let t = clamp(temp, 0.0, 1.0);
  return mix(mix(c0, c1, smoothstep(0.0, 0.55, t)), c2, smoothstep(0.45, 1.0, t));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= size.x || gid.y >= size.y) { return; }

  let p = vec2<i32>(gid.xy);
  let hi = vec2<i32>(size) - vec2<i32>(1);
  let res = vec2<f32>(size);
  let uv = (vec2<f32>(p) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

  let densityTarget = clamp(u.zoom_params.y, 0.0, 1.0);
  var s = grainAt(p, hi);
  if (time < 0.12 || dot(s, s) < 0.000001) {
    let src0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let seed = hash21(vec2<f32>(p));
    let initDensity = step(seed, clamp(densityTarget * (0.35 + uv.y * 0.65) + dot(src0.rgb, vec3<f32>(0.08)), 0.0, 1.0));
    s = vec4<f32>(initDensity, 0.0, 0.0, initDensity * 0.05);
  }

  let l = grainAt(p + vec2<i32>(-1, 0), hi);
  let r = grainAt(p + vec2<i32>(1, 0), hi);
  let t = grainAt(p + vec2<i32>(0, -1), hi);
  let b = grainAt(p + vec2<i32>(0, 1), hi);
  let ul = grainAt(p + vec2<i32>(-1, -1), hi);
  let ur = grainAt(p + vec2<i32>(1, -1), hi);

  let gravity = mix(0.015, 0.16, u.zoom_params.x) * (1.0 + audio.x * 0.35);
  let curlForce = mix(0.0, 0.18, u.zoom_params.z) * (1.0 + audio.y * 0.4);
  let bounce = mix(0.05, 0.82, u.zoom_params.w);

  // ── Idea 3: scene-depth 3D collision ledges & divergence-free streamfunction curl ──
  let curDepth = textureLoad(readDepthTexture, p, 0).r;
  let belowDepth = textureLoad(readDepthTexture, clamp(p + vec2<i32>(0, 1), vec2<i32>(0), hi), 0).r;
  let leftDepth = textureLoad(readDepthTexture, clamp(p + vec2<i32>(-1, 0), vec2<i32>(0), hi), 0).r;
  let rightDepth = textureLoad(readDepthTexture, clamp(p + vec2<i32>(1, 0), vec2<i32>(0), hi), 0).r;
  let depthLedge = smoothstep(0.03, 0.14, abs(belowDepth - curDepth));
  let depthSlopeX = clamp((rightDepth - leftDepth) * 3.0, -0.5, 0.5);
  let supportFloor = max(b.r, depthLedge * 0.90);

  let densityGrad = vec2<f32>(r.r - l.r, b.r - t.r) * 0.5;
  let sheet = max(s.r - supportFloor, 0.0);
  let avalanche = max(abs(densityGrad.x) - 0.08, 0.0);
  let curl = streamCurl(uv, time, audio.y);

  var velocity = s.gb * 0.91
    + vec2<f32>(-densityGrad.x * avalanche + depthSlopeX * depthLedge * gravity, gravity * (1.0 - supportFloor))
    + curl * curlForce * (0.18 + s.r * 0.85);

  let hitSupport = smoothstep(0.76, 0.90, supportFloor);
  let scatterSign = sign(hash21(vec2<f32>(p) * 0.73) - 0.5);
  let bouncedVy = -abs(velocity.y) * bounce;
  let bouncedVx = velocity.x + (scatterSign * avalanche + depthSlopeX * 0.45) * bounce;
  velocity = mix(velocity, vec2<f32>(bouncedVx, bouncedVy), hitSupport);

  let mq = (uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0);
  let md = length(mq) + 0.0001;
  let hover = exp(-md * 18.0);
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  velocity += normalize(vec2<f32>(-mq.y, mq.x) + vec2<f32>(0.0001)) * hover * (0.015 + held * (0.16 + audio.x * 0.06));
  velocity.y -= hover * held * (0.08 + bounce * 0.08);

  var shelves = 0.0;
  let count = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < count; i = i + 1u) {
    let e = u.ripples[i];
    let age = time - e.z;
    let isLive = f32(age >= 0.0 && age < 1.5);
    let safeAge = clamp(age, 0.0, 1.5);
    let q = (uv - e.xy) * vec2<f32>(aspect, 1.0);
    let d = length(q);
    let ring = isLive * exp(-safeAge * 2.0) * exp(-abs(d - safeAge * 0.32) * 78.0);
    velocity += normalize(q + vec2<f32>(0.0001)) * ring * 0.18;
    shelves += ring;
  }

  // ── Idea 4: live top-hopper Particle Density emitter & shear blackbody (§12.2F) ──
  let spoutWave = pow(0.5 + 0.5 * cos(uv.x * 18.8495 + sin(time * 0.55) * 1.4), 3.0);
  let hopperPour = exp(-uv.y * 44.0) * spoutWave * densityTarget * (0.055 + audio.x * 0.025);
  let bottomDrain = smoothstep(0.96, 1.0, uv.y) * (1.0 - densityTarget) * 0.035;

  let inflow = t.r * clamp(t.b, 0.0, 1.0) + l.r * max(l.g, 0.0) + r.r * max(-r.g, 0.0);
  let outflow = s.r * clamp(length(velocity), 0.0, 0.65);
  let diagRest = (1.0 - s.r) * (ul.r * step(0.55, l.r) + ur.r * step(0.55, r.r));
  let density = clamp(
    s.r + (inflow - outflow) * 0.11 + sheet * 0.04 - shelves * 0.025 + diagRest * 0.08 + hopperPour - bottomDrain,
    0.0,
    1.0
  );

  let shearRate = length(vec2<f32>(r.b - l.b, b.g - t.g)) * 0.5;
  let energy = clamp(mix(s.a, length(velocity) + shearRate * 0.65 + shelves + audio.z * density * 0.15, 0.16), 0.0, 1.0);
  let next = vec4<f32>(density, clamp(velocity.x, -1.0, 1.0), clamp(velocity.y, -1.0, 1.0), energy);
  textureStore(dataTextureA, p, next);

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let grainJitter = hash21(vec2<f32>(p));
  let grain = smoothstep(0.05, 0.55, density * (0.55 + densityTarget * 0.65) - grainJitter * 0.35);
  let speed = length(velocity);
  let thermalDrive = clamp(speed * 1.7 + shearRate * 1.4 + energy * 0.55 + audio.x * 0.22, 0.0, 1.0);
  let cool = vec3<f32>(0.08, 0.45, 1.55);

  var hdr = blackbodySand(thermalDrive);
  hdr = mix(hdr, src.rgb * 1.35 + vec3<f32>(0.25, 0.16, 0.06), clamp((1.0 - energy) * 0.42, 0.0, 0.42));
  hdr = mix(hdr, cool, clamp(audio.z * 0.35 + curlForce * 1.5, 0.0, 0.65));
  hdr *= grain * (0.45 + density * 0.9 + energy * 0.7);

  let sparklePhase = sin(grainJitter * 62.8 + time * (4.0 + speed * 8.0));
  let sparkle = energy * energy * smoothstep(0.75, 0.99, sparklePhase);
  hdr += vec3<f32>(2.4, 1.85, 0.55) * sparkle;
  hdr += shelves * vec3<f32>(1.6, 0.65, 0.12);
  hdr = mix(src.rgb, hdr, clamp(density * 0.82 + grain * 0.14, 0.0, 0.95));

  let alpha = clamp(src.a * 0.18 + density * 0.78 + energy * 0.20 + shelves * 0.25, 0.0, 1.0);
  let mapped = aces(max(hdr, vec3<f32>(0.0)));
  textureStore(writeTexture, p, vec4<f32>(mapped * alpha, alpha));
  textureStore(writeDepthTexture, p, vec4<f32>(clamp(mix(curDepth, 1.0 - density * 0.70 - energy * 0.08, 0.78), 0.0, 1.0), 0.0, 0.0, 0.0));
}
