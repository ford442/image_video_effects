// Cyber Rain EM — Composer batch cyber/digital/glitch
// fp128 field integration, spring mouse, racing rain packets,
// orbital click charges, held widens wiper, ACES + semantic alpha.

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
      let omega = 9.0;
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

  let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let wiper = smoothstep(wiperSize, wiperSize * 0.8, dist);

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

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  var finalColor = mix(baseColor, blurredColor, rainIntensity * 0.8);
  finalColor = mix(finalColor, mix(finalColor, prev.rgb * 0.88, 0.12), packet * 0.25);

  let rainPhase = fp128_sum(fp128_mul(fp128(time), fp128(10.0 * rainIntensity)), fp128(fieldDir.x * fieldMag * 5.0));
  let rainUV = uv * vec2<f32>(20.0, 2.0) + vec2<f32>(fieldDir.x * fieldMag * 5.0, fp128_val(rainPhase));
  let rainNoise = hash12(floor(rainUV));
  let drop = smoothstep(0.9, 0.95, rainNoise) * rainIntensity * (1.0 - wiper);

  let rainColor = hueShift(vec3<f32>(0.5, 0.7, 1.0), totalB * 2.0 + mids * 0.5);
  finalColor += rainColor * drop;
  finalColor += vec3<f32>(0.2, 0.95, 1.0) * packet * fieldVis * (0.2 + treble * 0.3);

  let streamNoise = hash12(uv * 200.0 + fieldMag * 10.0 + time * 0.5);
  let streamline = smoothstep(0.4, 0.6, streamNoise) * fieldVis * smoothstep(0.0, 0.5, fieldMag);
  let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
  finalColor = mix(finalColor, fieldColor, streamline * 0.4);

  let coreGlow = exp(-dist * dist * 400.0) * chargeStrength;
  finalColor += vec3<f32>(0.6, 0.9, 1.0) * coreGlow * fieldVis;

  let band = min(u32(uv.x * 8.0), 7u);
  finalColor += vec3<f32>(0.04, 0.1, 0.14) * plasmaBuffer[band + 1u].x * fieldMag * 0.15;

  finalColor = acesToneMap(finalColor);
  let alpha = clamp(fieldMag * 0.35 + drop * 0.4 + packet * 0.2 + bass * 0.08, 0.06, 0.96);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
