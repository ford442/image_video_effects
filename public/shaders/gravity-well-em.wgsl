// ═══════════════════════════════════════════════════════════════════
//  Gravity Well EM
//  Category: advanced-hybrid
//  Features: gravitational-lensing, electromagnetic-fields, chromatic, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-09-11
//  Ideas: photon ring halo; frame-drag hue shear
//  A packing: ACES display RGBA
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / res;
  let time = u.config.x;

  let strength = u.zoom_params.x;
  let radius = u.zoom_params.y * 0.4;
  let aberration = u.zoom_params.z * 0.1;
  let density = u.zoom_params.w;
  let chargeStrength = strength * 2.0;
  let colorRotation = aberration * 3.14159;

  let aspect = res.x / res.y;
  let mouse = u.zoom_config.yz;

  let d_vec_raw = uv - mouse;
  let d_vec_aspect = vec2<f32>(d_vec_raw.x * aspect, d_vec_raw.y);
  let dist = length(d_vec_aspect);

  var finalColor = vec3<f32>(0.0);
  var finalAlpha = 1.0;
  var distortionMag = 0.0;

  if (dist > radius) {
    let distSurface = dist - radius;
    let falloff = 1.0 / (pow(distSurface, density) * 10.0 + 1.0);
    let pull = strength * falloff;
    distortionMag = pull;

    var dir = normalize(d_vec_aspect);
    let shift_aspect = dir * pull * 0.1;
    let shift = vec2<f32>(shift_aspect.x / aspect, shift_aspect.y);
    let sample_uv_center = uv - shift;

    let hasMouseBuf = arrayLength(&extraBuffer) > 134u;
    var prevMouse = mouse;
    if (hasMouseBuf) {
      prevMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
      if (gid.x == 0u && gid.y == 0u) {
        extraBuffer[133] = mouse.x;
        extraBuffer[134] = mouse.y;
      }
    }
    let mouseVel = (mouse - prevMouse) * 60.0;
    let mouseDown = u.zoom_config.w;

    let eField = electricField(uv, mouse, chargeStrength);
    let bField = magneticField(uv, mouse, mouseVel, chargeStrength);

    var totalE = eField;
    var totalB = bField;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
      let ripple = u.ripples[i];
      let elapsed = time - ripple.z;
      if (elapsed > 0.0 && elapsed < 3.0) {
        let orbitAngle = elapsed * 2.0 + f32(i) * 1.256;
        let orbitRadius = 0.05 + 0.1 * smoothstep(0.0, 1.0, elapsed);
        let orbitPos = mouse + vec2<f32>(cos(orbitAngle), sin(orbitAngle)) * orbitRadius;
        let secondaryCharge = -chargeStrength * exp(-elapsed * 0.8);
        let secVel = vec2<f32>(-sin(orbitAngle), cos(orbitAngle)) * 2.0;
        totalE = totalE + electricField(uv, orbitPos, secondaryCharge);
        totalB = totalB + magneticField(uv, orbitPos, secVel, secondaryCharge);
      }
    }

    let fieldMag = length(totalE);
    let fieldDir = select(vec2<f32>(0.0), normalize(totalE), fieldMag > 0.0001);

    let emDisplacement = fieldDir * aberration * smoothstep(0.0, 2.0, fieldMag);
    let uv_r = clamp(sample_uv_center + shift * aberration * 5.0 + emDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let uv_b = clamp(sample_uv_center - shift * aberration * 5.0 + emDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let uv_g = clamp(sample_uv_center + emDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));

    let sampleR = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0);
    let sampleG = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0);
    let sampleB = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0);

    finalColor = vec3<f32>(sampleR.r, sampleG.g, sampleB.b);

    // Idea 2 — frame-drag hue shear: azimuthal hue rotation outside the well
    let azimuth = atan2(d_vec_aspect.y, d_vec_aspect.x);
    let frameDrag = azimuth * strength * smoothstep(radius * 1.05, radius * 2.5, dist);
    let hueRot = totalB * colorRotation * 0.5 + frameDrag;
    finalColor = hueShift(finalColor, hueRot);

    let glow = exp(-distSurface * 20.0) * strength;
    let glowColor = vec3<f32>(0.5, 0.2, 0.8) * glow;
    let coreGlow = exp(-dist * dist * 400.0) * chargeStrength;
    let emGlowColor = vec3<f32>(0.6, 0.9, 1.0);
    finalColor = finalColor + glowColor + emGlowColor * coreGlow * 0.3;

    // Idea 1 — photon ring halo at Einstein-radius critical curve
    let einsteinR = radius * (1.0 + strength * 0.35);
    let ringDist = abs(dist - einsteinR);
    let photonRing = exp(-ringDist * ringDist * 800.0) * strength * (0.6 + mouseDown * 0.4);
    finalColor = finalColor + vec3<f32>(1.0, 0.92, 0.75) * photonRing;

    let streamUV = uv + fieldDir * hash12(uv * 100.0 + time * 0.5) * 0.02;
    let streamNoise = hash12(streamUV * 200.0 + fieldMag * 10.0);
    let streamline = smoothstep(0.4, 0.6, streamNoise) * smoothstep(0.0, 0.5, fieldMag);
    let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
    finalColor = mix(finalColor, fieldColor, streamline * 0.3);

    let compressionFactor = 1.0 + distortionMag * 0.2;
    let scatteringLoss = distortionMag * 0.4;
    let chromaticScatter = aberration * distortionMag * 0.5;
    finalAlpha = clamp((sampleR.a + sampleG.a + sampleB.a) / 3.0 * compressionFactor - scatteringLoss - chromaticScatter, 0.4, 1.0);
    finalAlpha = min(finalAlpha + glow * 0.5 + photonRing * 0.35, 1.0);
  } else {
    let edge = smoothstep(radius, radius * 0.95, dist);
    finalColor = vec3<f32>(0.02, 0.0, 0.05) * (1.0 - edge);
    finalAlpha = 1.0 - edge * 0.3;
  }

  let displayRgb = acesToneMap(finalColor);
  textureStore(writeTexture, pixel, vec4<f32>(displayRgb, finalAlpha));
  textureStore(dataTextureA, pixel, vec4<f32>(displayRgb, finalAlpha));

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthMod = 1.0 - distortionMag * 0.1;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
