// ═══════════════════════════════════════════════════════════════════
//  Neon Fluid Warp
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, semantic-alpha
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: viscous wake (pointer velocity from the (0,0) prev-mouse texel stretches the lens behind the motion, relaxing with liquidity); meniscus highlight (Blinn specular on the force-gradient normal of the lens rim); viscous hold (held pointer slows the runner/caustic clock by liquidity)
//  A packing: linear pre-ACES RGBA (14% exact-C history); (0,0) = prev mouse xy, last time, sentinel -7; (1,0) = wake velocity xy, viscous clock, sentinel -7
//  Motion: viscous curl jets + neon edge runners
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;
const SENTINEL: f32 = -7.0;

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  return v * inverseSqrt(max(dot(v, v), 1e-6));
}

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.50, 0.49, 0.53) + vec3<f32>(0.48, 0.42, 0.45)
    * cos(TAU * (vec3<f32>(1.0, 0.80, 0.55) * t + vec3<f32>(0.28, 0.18, 0.08)));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let v = max(x, vec3<f32>(0.0));
  return clamp((v * (2.51 * v + 0.03)) / (v * (2.43 * v + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn finite3(v: vec3<f32>) -> vec3<f32> {
  return clamp(select(vec3<f32>(0.0), v, v == v), vec3<f32>(0.0), vec3<f32>(16.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let mouse = u.zoom_config.yz;                 // raw pointer (the old extraBuffer spring never persisted)
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let warpStrength = u.zoom_params.x * 0.2;
  let radius = mix(0.06, 0.55, u.zoom_params.y);
  let glowIntensity = u.zoom_params.z;
  let liquidity = u.zoom_params.w * 0.5;
  let liquidityRaw = u.zoom_params.w;

  // ── State texels (every thread reads, only (0,0) and (1,0) write) ──
  let state0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let state1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let valid0 = state0.w == SENTINEL && all(state0.xyz == state0.xyz);
  let valid1 = state1.w == SENTINEL && all(state1.xyz == state1.xyz);
  let prevMouse = select(mouse, clamp(state0.xy, vec2<f32>(0.0), vec2<f32>(1.0)), valid0);
  let lastTime = select(time, state0.z, valid0);
  let prevWake = select(vec2<f32>(0.0), clamp(state1.xy, vec2<f32>(-1.0), vec2<f32>(1.0)), valid1);
  let prevClock = select(time, clamp(state1.z, 0.0, 1e6), valid1);
  let dt = clamp(time - lastTime, 0.0, 0.05);

  // IDEA 1: viscous wake — pointer velocity (uv/frame, aspect-corrected) feeds a wake vector
  // that relaxes slowly when the fluid is thick (liquidity) and quickly when it is thin.
  let rawVel = clamp((mouse - prevMouse) * aspectVec, vec2<f32>(-0.2), vec2<f32>(0.2));
  let relax = mix(0.30, 0.08, liquidityRaw);
  let wake = prevWake + (rawVel * 8.0 - prevWake) * relax;
  let wakeMag = min(length(wake), 0.6);
  let wakeDir = safeNormalize(wake);

  // IDEA 3: viscous hold — a "viscous clock" that runs at 1x when free and slows by liquidity
  // while the pointer is held, so runners and caustics thicken without a phase jump.
  let clockRate = select(1.0, 1.0 - liquidityRaw * 0.7, held);
  let viscousClock = prevClock + dt * clockRate;

  if (gid.x == 0u && gid.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mouse, time, SENTINEL));
  }
  if (gid.x == 1u && gid.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(1, 0), vec4<f32>(clamp(wake, vec2<f32>(-1.0), vec2<f32>(1.0)), viscousClock, SENTINEL));
  }

  var distVec = (uv - mouse) * aspectVec;
  let dist = length(distVec);
  let force = smoothstep(radius, 0.0, dist);
  let hold = select(1.0, 1.45, held);

  let jetPhase = time * (2.4 + bass * 1.8) + dist * 18.0;
  let jet = vec2<f32>(-distVec.y, distVec.x) * inverseSqrt(max(dot(distVec, distVec), 1e-6))
    * sin(jetPhase) * force * liquidity * 0.045;
  let ripple = sin(dist * 20.0 - time * (5.0 + mids * 2.0)) * liquidity * 0.05;
  let displaceDir = safeNormalize(distVec);
  var offset = (-displaceDir * force * warpStrength * hold * (1.0 + ripple)) + jet;

  // IDEA 1 (cont.): pixels behind the motion are dragged along the wake inside a wider,
  // softer lens, so the image smears out behind a moving pointer and settles as the wake relaxes.
  let behind = smoothstep(0.0, 0.7, -dot(displaceDir, wakeDir));
  let wakeLens = smoothstep(radius * 1.7, 0.0, dist);
  offset += -wakeDir * wakeMag * behind * wakeLens * warpStrength * 1.6;

  var click = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    let alive = age > 0.0 && age < 2.2;
    let rd = length((uv - r.xy) * aspectVec);
    click = click + select(0.0, exp(-abs(rd - age * 0.6) * 15.0) * exp(-age * 1.3), alive);
  }

  let sampleUV = clamp(uv + offset + displaceDir * click * 0.03, vec2<f32>(0.0), vec2<f32>(1.0));
  let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let hist = finite3(textureLoad(dataTextureC, coord, 0).rgb);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;

  let edge = 1.0 - smoothstep(0.0, 0.11 + treble * 0.03, abs(dist - radius * 0.8));
  let runner = pow(max(0.0, sin(atan2(distVec.y, distVec.x) * 7.0 - viscousClock * (6.0 + bass * 3.0)) * 0.5 + 0.5), 6.0)
    * edge * (0.65 + mids * 0.3);
  let glowFactor = force * (1.0 - force) * 4.0;
  let caustic = pow(max(0.0, sin(dist * 42.0 - viscousClock * (5.0 + bass * 1.5)) * 0.5 + 0.5), 5.0) * force;
  let neon = palette(time * 0.09 + dist * 1.3 + mids * 0.25 + treble * 0.08);
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // IDEA 2: meniscus highlight — the lens surface is tilted by the analytic gradient of the
  // force field (smoothstep(radius, 0, dist)), and a Blinn specular from a top-left light
  // draws a thin crescent on the lit side of the rim.
  let t = clamp(1.0 - dist / max(radius, 1e-4), 0.0, 1.0);
  let slope = 6.0 * t * (1.0 - t) * 1.5;                  // |d force / d dist| * radius * 1.5
  let surfNormal = normalize(vec3<f32>(displaceDir * slope, 1.0));
  let lightDir = normalize(vec3<f32>(-0.45, -0.6, 0.65));
  let halfVec = normalize(lightDir + vec3<f32>(0.0, 0.0, 1.0));
  // slope is symmetric in t, so gate to the outer rim (t < ~0.5) or the lobe
  // also fires on the inner slope next to the pointer.
  let meniscus = pow(max(dot(surfNormal, halfVec), 0.0), 64.0) * smoothstep(0.08, 0.5, slope)
    * (1.0 - smoothstep(0.35, 0.65, t)) * (0.5 + glowIntensity);

  var hdr = color.rgb * (0.58 + force * 0.28);
  hdr = hdr + neon * glowFactor * glowIntensity * luma * (3.0 + bass);
  hdr = hdr + vec3<f32>(0.42, 0.75, 1.0) * edge * glowIntensity * (0.7 + treble);
  hdr = hdr + vec3<f32>(1.0, 0.82, 0.46) * (caustic * 0.45 + runner * 0.85 + click * 0.4);
  hdr = hdr + vec3<f32>(0.85, 0.95, 1.0) * meniscus * 1.3;
  hdr = mix(hdr, hist, 0.14 * (1.0 - force));
  hdr = hdr * mix(1.0, 0.68, smoothstep(0.46, 1.0, length(uv - vec2<f32>(0.5)) * 1.414));

  let dither = (ign(vec2<f32>(gid.xy) + vec2<f32>(sin(time * 3.1), cos(time * 2.7)) * 11.0) - 0.5) / 255.0;
  let rgb = clamp(aces(hdr * 1.14) + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));
  let alpha = clamp(glowFactor * 0.35 + edge * 0.28 + runner * 0.25 + meniscus * 0.2 + color.a * 0.35, 0.08, 0.98);

  textureStore(writeTexture, coord, vec4<f32>(rgb, alpha));
  if (gid.y != 0u || gid.x > 1u) {
    textureStore(dataTextureA, coord, vec4<f32>(hdr, alpha));
  }
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
