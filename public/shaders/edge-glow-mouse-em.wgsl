// ═══════════════════════════════════════════════════════════════════
//  Edge Glow Mouse EM
//  Category: advanced-hybrid
//  Features: edge-detection, electromagnetic-field, mouse-driven, chromatic, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-11
//  Ideas: Laplacian corona; field-line advection streak
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

fn clampPixel(pixel: vec2<i32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = vec2<f32>(gid.xy) / res;
  let pixelSize = 1.0 / res;
  let time = u.config.x;

  let edgeThreshold = u.zoom_params.x * 0.1 + 0.02;
  let glowRadius = u.zoom_params.y * 0.3 + 0.05;
  let glowIntensity = u.zoom_params.z * 3.0;
  let colorCycle = u.zoom_params.w * 3.14159;
  let chargeStrength = u.zoom_params.x * 2.0;
  let fieldVis = u.zoom_params.y;
  let distortionStrength = u.zoom_params.z * 0.15;

  let mousePos = u.zoom_config.yz;
  let mouseDist = distance(uv, mousePos);

  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let cR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0);
  let cL = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0);
  let cU = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0);
  let cD = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0);
  let colorEdge = length(cR.rgb - cL.rgb) + length(cU.rgb - cD.rgb);

  // Idea 1 — Laplacian corona: second-derivative zero-cross halo around strong edges
  let laplacian = length(cR.rgb + cL.rgb + cU.rgb + cD.rgb - 4.0 * c.rgb);
  let corona = smoothstep(edgeThreshold * 0.5, edgeThreshold * 2.5, laplacian)
    * (1.0 - smoothstep(edgeThreshold * 2.0, edgeThreshold * 5.0, colorEdge));

  let hasMouseBuf = arrayLength(&extraBuffer) > 134u;
  var prevMouse = mousePos;
  if (hasMouseBuf) {
    prevMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    if (gid.x == 0u && gid.y == 0u) {
      extraBuffer[133] = mousePos.x;
      extraBuffer[134] = mousePos.y;
    }
  }
  let mouseVel = (mousePos - prevMouse) * 60.0;

  let eField = electricField(uv, mousePos, chargeStrength);
  let bField = magneticField(uv, mousePos, mouseVel, chargeStrength);
  let fieldMag = length(eField);
  let fieldDir = select(vec2<f32>(0.0), normalize(eField), fieldMag > 0.0001);

  let streamUV = uv + fieldDir * hash12(uv * 100.0 + time * 0.5) * 0.02;
  let streamNoise = hash12(streamUV * 200.0 + fieldMag * 10.0);
  let streamline = smoothstep(0.4, 0.6, streamNoise) * fieldVis * smoothstep(0.0, 0.5, fieldMag);

  let displacedUV = clamp(uv + fieldDir * distortionStrength * smoothstep(0.0, 2.0, fieldMag), vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  let glowFalloff = 1.0 - smoothstep(0.0, glowRadius, mouseDist);
  let edgeGlowColor = vec3<f32>(
    0.5 + 0.5 * sin(time * 2.0 + colorCycle),
    0.5 + 0.5 * sin(time * 2.0 + 2.09 + colorCycle),
    0.5 + 0.5 * sin(time * 2.0 + 4.18 + colorCycle)
  ) * colorEdge * glowIntensity * glowFalloff;

  // Idea 2 — field-line advection streak: smear edge glow along ∇E from exact C
  let advectOffset = vec2<i32>(round(fieldDir * fieldMag * 3.0 / pixelSize));
  let prevGlow = textureLoad(dataTextureC, clampPixel(pixel - advectOffset, dims), 0);
  let streakGlow = prevGlow.rgb * smoothstep(0.0, 0.8, fieldMag) * colorEdge * 0.35;

  let hueRot = bField * colorCycle * 0.5;
  var color = hueShift(baseColor, hueRot);
  color = color + edgeGlowColor + streakGlow;
  color = color + vec3<f32>(0.7, 0.85, 1.0) * corona * glowIntensity * 0.4;

  let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
  var outColor = mix(color, fieldColor, streamline * 0.4);

  let aspect = res.x / res.y;
  let mouseDistAspect = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let coreGlow = exp(-mouseDistAspect * mouseDistAspect * 400.0) * chargeStrength;
  outColor = outColor + vec3<f32>(0.6, 0.9, 1.0) * coreGlow * fieldVis;

  let alpha = clamp(length(edgeGlowColor) * 0.5 + streamline * 0.3 + corona * 0.25 + prevGlow.a * 0.15, 0.0, 1.0);
  let displayRgb = acesToneMap(outColor);

  textureStore(writeTexture, pixel, vec4<f32>(displayRgb, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(displayRgb, alpha));

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
