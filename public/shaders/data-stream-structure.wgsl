// ═══════════════════════════════════════════════════════════════════
//  data-stream-structure — Batch 60
//  Structure-tensor LIC data streams: spring cursor, capped ripples,
//  held vortex, hex packet geometry, exact C trail mask, ACES + audio.
//  Upgraded: 2026-10-19
//  Ideas: packet framing (gaps + lit 4-bit headers travelling with each strip);
//         lane collisions where the tensor is isotropic but textured
//  A packing: (trail, lum, flowAngle, alpha) — unchanged
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3))));
  return fract(n * 43758.5453);
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let len = length(v);
  return select(v / len, vec2<f32>(1.0, 0.0), len < 0.0001);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn cyberPalette(t: f32) -> vec3<f32> {
  let a = vec3<f32>(0.5, 0.5, 0.5);
  let b = vec3<f32>(0.5, 0.5, 0.5);
  let c = vec3<f32>(1.0, 1.0, 1.0);
  let d = vec3<f32>(0.0, 0.33, 0.67);
  return a + b * cos(TAU * (c * t + d));
}

fn sampleLuma(uv: vec2<f32>, pixelSize: vec2<f32>, dx: i32, dy: i32) -> f32 {
  let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
  let s = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  return dot(s, vec3<f32>(0.299, 0.587, 0.114));
}

fn structureTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
  let gx =
    -1.0 * sampleLuma(uv, pixelSize, -1, -1) +
    -2.0 * sampleLuma(uv, pixelSize, -1,  0) +
    -1.0 * sampleLuma(uv, pixelSize, -1,  1) +
     1.0 * sampleLuma(uv, pixelSize,  1, -1) +
     2.0 * sampleLuma(uv, pixelSize,  1,  0) +
     1.0 * sampleLuma(uv, pixelSize,  1,  1);
  let gy =
    -1.0 * sampleLuma(uv, pixelSize, -1, -1) +
    -2.0 * sampleLuma(uv, pixelSize,  0, -1) +
    -1.0 * sampleLuma(uv, pixelSize,  1, -1) +
     1.0 * sampleLuma(uv, pixelSize, -1,  1) +
     2.0 * sampleLuma(uv, pixelSize,  0,  1) +
     1.0 * sampleLuma(uv, pixelSize,  1,  1);
  return vec4<f32>(gx * gx, gy * gy, gx * gy, 0.0);
}

fn smoothTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
  var sum = vec4<f32>(0.0);
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      sum += structureTensor(uv + offset, pixelSize);
    }
  }
  return sum / 9.0;
}

fn hexGrid(uv: vec2<f32>, scale: f32) -> f32 {
  let p = uv * scale;
  let q = vec2<f32>(p.x * 1.7320508 + p.y, p.y * 2.0);
  let pi = floor(q);
  let pf = fract(q);
  let d1 = length(pf - vec2<f32>(0.5, 0.5));
  let d2 = length(pf - vec2<f32>(0.0, 1.0));
  return 1.0 - smoothstep(0.02, 0.08, min(d1, d2));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixelSize = 1.0 / res;
  let time = u.config.x;
  let aspect = res.x / res.y;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let speed = clamp(u.zoom_params.x, 0.0, 1.0) * (1.0 + bass * 0.35);
  let density = clamp(u.zoom_params.y, 0.0, 1.0);
  let turbulence = clamp(u.zoom_params.z, 0.0, 1.0) * (1.0 + mids * 0.25);
  let glow = clamp(u.zoom_params.w, 0.0, 1.0);

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 10.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let uvAspect = uv * vec2<f32>(aspect, 1.0);
  let mouseAspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
  let interactDist = length(uvAspect - mouseAspect);
  let interactRadius = mix(0.15, 0.42, turbulence) * select(1.0, 1.35, held);
  let interact = smoothstep(interactRadius, 0.0, interactDist) * turbulence;

  var rippleBoost = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.2) {
      let rAspect = vec2<f32>(rp.x * aspect, rp.y);
      let rDist = length(uvAspect - rAspect);
      rippleBoost += smoothstep(0.14, 0.0, rDist) * (1.0 - age * 0.85);
    }
  }

  let tensor = smoothTensor(uv, pixelSize);
  let Jxx = tensor.x;
  let Jyy = tensor.y;
  let Jxy = tensor.z;
  let trace = Jxx + Jyy;
  let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
  let lambda1 = (trace + diff) * 0.5;
  let lambda2 = (trace - diff) * 0.5;
  let coherency = select(0.0, (lambda1 - lambda2) / (lambda1 + lambda2 + 0.0001), lambda1 + lambda2 > 0.0001);

  var eigenvec = vec2<f32>(1.0, 0.0);
  if (abs(Jxy) > 0.0001 || abs(Jxx - lambda1) > 0.0001) {
    eigenvec = safeNormalize(vec2<f32>(lambda1 - Jyy, Jxy));
  }

  let toMouse = safeNormalize(uvAspect - mouseAspect);
  let vortex = interact * sin(atan2(toMouse.y, toMouse.x) * 3.0 - time * 4.0) * 0.08;
  eigenvec = safeNormalize(eigenvec + vec2<f32>(-toMouse.y, toMouse.x) * vortex);

  let numStrips = 20.0 + density * 120.0 + treble * 20.0;
  let stripIdx = floor(dot(uv, eigenvec) * numStrips);
  let rand = fract(sin(stripIdx * 12.9898) * 43758.5453);
  let flowSpeed = (rand * 0.5 + 0.5) * speed * 0.6;
  let perp = vec2<f32>(-eigenvec.y, eigenvec.x);

  let xOffset = (interact + rippleBoost * 0.5) * sin(dot(uv, perp) * 12.0 + time * 6.0) * 0.06;

  var sampleUV = uv;
  sampleUV = sampleUV + eigenvec * (time * flowSpeed);
  sampleUV = sampleUV + perp * xOffset;
  sampleUV = fract(sampleUV);

  if (rand > 0.75) {
    sampleUV = sampleUV + eigenvec * (sin(time * 12.0 + stripIdx) * 0.015);
  }

  // Idea 2 — lane collisions: where the tensor is isotropic but textured
  // (corners, clutter: low coherency, non-zero trace) a lane has no direction,
  // so packets collide — per-cell bytes re-hash in short slots and jump.
  let collision = (1.0 - coherency) * smoothstep(0.002, 0.03, trace) * density;
  let collideCell = floor(uv * vec2<f32>(48.0, 27.0));
  let collideSlot = floor(time * 9.0 + rand * 3.0);
  let collideRoll = hash12(collideCell + vec2<f32>(collideSlot, stripIdx * 0.37));
  let collideHit = step(1.0 - collision * 0.6, collideRoll);
  sampleUV = sampleUV + (hash22(collideCell + collideSlot) - 0.5) * 0.06 * collideHit;

  let color = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let lum = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let hex = hexGrid(uv + eigenvec * time * 0.02, 28.0 + density * 40.0);
  let digitalColor = mix(
    vec3<f32>(0.0, lum * 1.8, lum * 0.25),
    cyberPalette(fract(stripIdx * 0.07 + time * 0.05)),
    glow * 0.55
  );

  let blockCoord = floor(uv * vec2<f32>(50.0, 30.0));
  let noise = hash12(vec2<f32>(stripIdx, blockCoord.y) + vec2<f32>(0.0, time));
  let bright = step(0.96, noise * (sin(time * 2.5 + stripIdx) * 0.5 + 0.5));

  var outputColor = mix(color.rgb, digitalColor, glow);
  outputColor = outputColor + vec3<f32>(0.0, bright * glow * 1.2, bright * glow * 0.3);
  outputColor = mix(outputColor, outputColor * 1.4 + cyberPalette(lum) * 0.2, hex * glow * 0.35);

  let flowAngle = atan2(eigenvec.y, eigenvec.x) * 0.15915 + 0.5;
  let flowColor = cyberPalette(flowAngle + bass * 0.1);
  outputColor = mix(outputColor, flowColor * lum * 2.2, glow * 0.35);

  // Idea 1 — packet framing: each strip is cut along its length into packets
  // that travel with that strip's speed; a dark inter-packet gap and a lit
  // 4-bit header at the leading edge, in the strip's palette colour.
  let packetCoord = dot(uv, perp) * numStrips * 0.22 - time * flowSpeed * 9.0;
  let packetId = floor(packetCoord);
  let packetLocal = fract(packetCoord);
  let packetGap = 1.0 - smoothstep(0.0, 0.035, packetLocal) * smoothstep(1.0, 0.965, packetLocal);
  let headerSpan = 0.16;
  // packetCoord falls with time, so packets move toward +local: the header
  // rides the high end of each packet.
  let inHeader = step(1.0 - headerSpan, packetLocal) * (1.0 - packetGap);
  let bitIdx = floor(clamp((packetLocal - (1.0 - headerSpan)) / headerSpan, 0.0, 0.999) * 4.0);
  let headerBit = step(0.5, hash12(vec2<f32>(packetId * 4.0 + bitIdx, stripIdx)));
  let headerColor = cyberPalette(fract(stripIdx * 0.07 + 0.5));
  outputColor = outputColor * (1.0 - packetGap * glow * 0.55);
  outputColor = outputColor + headerColor * inHeader * mix(0.15, 1.0, headerBit) * glow * 0.6;
  outputColor = outputColor + vec3<f32>(0.0, 0.9, 0.35) * collideHit * glow * 0.25;

  let band = min(u32(uv.x * 8.0), 7u);
  outputColor += cyberPalette(fract(time * 0.1 + f32(band) * 0.12)) * plasmaBuffer[band + 1u].x * 0.08;

  let prevTrail = textureLoad(dataTextureC, coord, 0).r;
  let trail = clamp(prevTrail * 0.92 + (interact + rippleBoost) * 0.12, 0.0, 1.0);
  outputColor = mix(outputColor, outputColor * 1.15 + vec3<f32>(0.1, 0.4, 0.2), trail * 0.25);

  outputColor = acesToneMap(outputColor * (0.95 + bass * 0.1));
  let alpha = clamp(0.55 + lum * 0.25 + glow * 0.2 + interact * 0.15, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(outputColor, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(trail, lum, fract(flowAngle), alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
