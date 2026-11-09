// ═══════════════════════════════════════════════════════════════════
//  Cyber Rain EM
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: column lead-char bloom; EM wiper skew; Lorentz glyph curl; wiper meniscus lens; ionisation glyph density
//  A packing: ACES display RGBA in A; texel (0,0) = cursor state [mouse.xy, time, 0.777]
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735);
  let cs = cos(hue);
  return color * cs + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cs);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn electricField(pos: vec2<f32>, chargePos: vec2<f32>, charge: f32) -> vec2<f32> {
  let r = pos - chargePos;
  let dist = max(length(r), 0.001);
  return charge * normalize(r) / (dist * dist);
}

fn magneticField(pos: vec2<f32>, chargePos: vec2<f32>, velocity: vec2<f32>, charge: f32) -> f32 {
  let r = pos - chargePos;
  let dist = max(length(r), 0.001);
  return charge * (velocity.x * r.y - velocity.y * r.x) / (dist * dist * dist);
}

fn rain_packet(uv: vec2<f32>, time: f32, speed: f32) -> f32 {
  let head = fract(time * (1.5 + speed * 3.0));
  let d = abs(uv.y - head);
  return pow(max(0.0, 1.0 - d * 14.0), 5.0);
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

  let rainIntensity = u.zoom_params.x;
  let chargeStrength = u.zoom_params.y * 2.0;
  let fieldVis = u.zoom_params.z;
  let wiperSize = u.zoom_params.w * 0.5 * select(1.0, 1.3, held);

  let rawMouse = u.zoom_config.yz;
  // Rescue: extraBuffer springs are zeroed every frame; pointer velocity comes from
  // the previous cursor stored in A texel (0,0) (sentinel alpha 0.777).
  let mousePos = rawMouse;
  var mouseVel = vec2<f32>(0.0);
  let cur = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  if (abs(cur.a - 0.777) < 0.002) {
    let dtc = clamp(time - cur.z, 0.008, 0.1);
    mouseVel = clamp((rawMouse - cur.xy) / dtc, vec2<f32>(-3.0), vec2<f32>(3.0));
  }

  let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let wiper = smoothstep(wiperSize, wiperSize * 0.8, dist);
  // Idea 4 — wiper meniscus lens: thin water ring at the wiper rim refracts outward
  let rimD = (dist - wiperSize * 0.9) / max(wiperSize * 0.12, 0.002);
  let meniscus = exp(-rimD * rimD) * step(0.001, wiperSize);
  let radial = select(vec2<f32>(0.0), distVec / max(dist, 1e-4) / vec2<f32>(aspect, 1.0), dist > 1e-4);

  let eField = electricField(uv, mousePos, chargeStrength);
  var totalE = eField;
  var totalB = magneticField(uv, mousePos, mouseVel, chargeStrength);

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let orbitPhase = fp128_sum(fp128_mul(fp128(elapsed), fp128(2.0 + bass)), fp128(f32(i) * 1.256));
      let orbitAngle = fp128_val(orbitPhase);
      let orbitRadius = 0.05 + 0.1 * smoothstep(0.0, 1.0, elapsed);
      let orbitPos = mousePos + vec2<f32>(cos(orbitAngle), sin(orbitAngle)) * orbitRadius;
      let secondaryCharge = -chargeStrength * exp(-elapsed * 0.8);
      let secVel = vec2<f32>(-sin(orbitAngle), cos(orbitAngle)) * 2.0;
      totalE = totalE + electricField(uv, orbitPos, secondaryCharge);
      totalB = totalB + magneticField(uv, orbitPos, secVel, secondaryCharge);
    }
  }

  let fieldMag = length(totalE);
  let fieldDir = select(vec2<f32>(0.0), normalize(totalE), fieldMag > 0.0001);
  let packet = rain_packet(uv, time, rainIntensity);

  let prev = textureLoad(dataTextureC, pixel, 0);
  var blurredColor = vec3<f32>(0.0);
  let samples = 5;
  let blurStrength = rainIntensity * 0.08;
  for (var i = 0; i < samples; i++) {
    let offset = f32(i) * blurStrength * (1.0 - wiper);
    let sampleUV = uv + vec2<f32>(fieldDir.x * offset * 2.0, offset - blurStrength * 2.0);
    let col = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let brightness = max(col.r, max(col.g, col.b));
    blurredColor += col.rgb * (1.0 + smoothstep(0.6, 1.0, brightness) * 2.0);
  }
  blurredColor = blurredColor / f32(samples);

  let lensUV = clamp(uv - radial * meniscus * rimD * 0.012 * (1.0 + bass * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = textureSampleLevel(readTexture, u_sampler, lensUV, 0.0).rgb;
  var finalColor = mix(baseColor, blurredColor, rainIntensity * 0.8);
  finalColor = mix(finalColor, mix(finalColor, prev.rgb * 0.88, 0.12), packet * 0.25);

  // Idea 2 — EM wiper skew: shear rain columns along local E-field from mouse velocity
  let emSkew = dot(mouseVel, fieldDir) * fieldMag * 12.0;
  let rainPhase = fp128_sum(fp128_mul(fp128(time), fp128(10.0 * rainIntensity)), fp128(fieldDir.x * fieldMag * 5.0));
  // Idea 3 — Lorentz glyph curl: v×B bends columns sideways around a moving charge
  let lorentz = clamp(totalB * 0.04, -1.5, 1.5) * (1.0 - uv.y * 0.5);
  let rainUV = uv * vec2<f32>(20.0, 2.0) + vec2<f32>(fieldDir.x * fieldMag * 5.0 + emSkew + lorentz, fp128_val(rainPhase));
  let colId = floor(rainUV.x);
  let colFrac = fract(rainUV.y);
  let rainNoise = hash12(vec2<f32>(colId, floor(rainUV.y)));

  // Idea 1 — column lead-char bloom: brightest glyph at rain head with phosphor tail
  let colSpeed = 1.2 + hash12(vec2<f32>(colId, 0.37)) * 2.5;
  let headY = fract(time * colSpeed * rainIntensity + hash12(vec2<f32>(colId, 1.73)));
  let headDist = abs(colFrac - headY);
  let headWrap = min(headDist, 1.0 - headDist);
  let leadBloom = exp(-headWrap * headWrap * 180.0) * (1.0 + smoothstep(0.08, 0.0, headWrap) * 2.5);
  let phosphorTail = exp(-max(headWrap - 0.02, 0.0) * 28.0) * smoothstep(0.35, 0.0, headWrap);
  // Idea 5 — ionisation glyph density: strong |E| (+treble) lowers the glyph threshold
  let ion = clamp(fieldMag * 0.02, 0.0, 1.0) * (0.6 + treble * 0.6);
  let gTh = 0.88 - ion * 0.3;
  let glyphMask = smoothstep(gTh, gTh + 0.06, rainNoise) * rainIntensity * (1.0 - wiper);
  let drop = glyphMask * (leadBloom * 1.8 + phosphorTail * 0.55);

  let rainColor = hueShift(vec3<f32>(0.5, 0.7, 1.0), totalB * 2.0 + mids * 0.5);
  finalColor += rainColor * drop;
  finalColor += vec3<f32>(0.85, 1.0, 0.95) * leadBloom * glyphMask * 0.45;
  finalColor += vec3<f32>(0.2, 0.95, 1.0) * packet * fieldVis * (0.2 + treble * 0.3);

  let streamNoise = hash12(uv * 200.0 + fieldMag * 10.0 + time * 0.5);
  let streamline = smoothstep(0.4, 0.6, streamNoise) * fieldVis * smoothstep(0.0, 0.5, fieldMag);
  let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
  finalColor = mix(finalColor, fieldColor, streamline * 0.4);

  let coreGlow = exp(-dist * dist * 400.0) * chargeStrength;
  finalColor += vec3<f32>(0.6, 0.9, 1.0) * coreGlow * fieldVis;
  finalColor += vec3<f32>(0.7, 0.9, 1.0) * meniscus * (0.08 + max(rimD, 0.0) * 0.2);


  finalColor = acesToneMap(max(finalColor, vec3<f32>(0.0)));
  let alpha = clamp(fieldMag * 0.35 + drop * 0.4 + leadBloom * glyphMask * 0.25 + packet * 0.2 + bass * 0.08, 0.06, 0.96);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
  if (pixel.x == 0 && pixel.y == 0) {
    textureStore(dataTextureA, pixel, vec4<f32>(rawMouse, time, 0.777));
  } else {
    textureStore(dataTextureA, pixel, vec4<f32>(finalColor, alpha));
  }
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
