// ═══════════════════════════════════════════════════════════════════
//  Wormhole Lens
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09
//  Ideas: inverse-square lensing; exact-C throat ghost
//  A packing: ACES display RGBA (mouse stash extraBuffer[133..134])
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

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 0.001);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let portalRadius = mix(0.1, 0.4, u.zoom_params.x) * (1.0 + bass * 0.15);
  let spiralStrength = mix(0.0, 3.0, u.zoom_params.y);
  let colorShiftAmt = mix(0.0, 1.57, u.zoom_params.z) * (1.0 + mids * 0.2);
  let lensStrength = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let hasStash = arrayLength(&extraBuffer) > 134u;
  var prevMouse = mousePos;
  if (hasStash) {
    prevMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  let mouseVel = mousePos - prevMouse;
  let mouseDown = u.zoom_config.w;

  if (global_id.x == 0u && global_id.y == 0u && hasStash) {
    extraBuffer[133] = mousePos.x;
    extraBuffer[134] = mousePos.y;
  }

  let stretchDir = select(vec2<f32>(1.0, 0.0), normalize(mouseVel), length(mouseVel) > 0.001);
  let stretchAmount = length(mouseVel) * 2.0;

  var local = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let stretchDot = dot(local, stretchDir);
  let stretchPerp = local - stretchDir * stretchDot;
  local = stretchDir * stretchDot * (1.0 + stretchAmount) + stretchPerp;

  let localDist = length(local);
  let localAngle = atan2(local.y, local.x);

  let inPortal = smoothstep(portalRadius, portalRadius * 0.85, localDist);
  let edge = smoothstep(portalRadius * 1.1, portalRadius * 0.9, localDist) -
             smoothstep(portalRadius * 0.9, portalRadius * 0.7, localDist);

  var sampleUV = uv;

  if (inPortal > 0.01) {
    let normalizedDist = localDist / max(portalRadius, 0.001);
    let spiralAngle = localAngle + (1.0 - normalizedDist) * spiralStrength * 3.14159 + time * 0.5;
    let compressedDist = normalizedDist * normalizedDist * portalRadius;

    var wormholeLocal = vec2<f32>(cos(spiralAngle), sin(spiralAngle)) * compressedDist;
    let whStretchDot = dot(wormholeLocal, stretchDir);
    let whStretchPerp = wormholeLocal - stretchDir * whStretchDot;
    wormholeLocal = stretchDir * whStretchDot / (1.0 + stretchAmount) + whStretchPerp;

    sampleUV = mousePos + wormholeLocal / vec2<f32>(aspect, 1.0);
    sampleUV = 1.0 - sampleUV;
  }

  // Idea 1 — inverse-square lensing on the existing edge offset
  let lensDir = select(vec2<f32>(0.0), local / max(localDist, 0.001), localDist > 0.001);
  let r2 = max(localDist * localDist, 0.0004);
  let lensOffset = lensDir * edge * lensStrength * 0.012 / r2;
  sampleUV = clamp(sampleUV + lensOffset / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));

  var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  let srcA = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;

  if (inPortal > 0.01) {
    let hueRot = localAngle * 0.5 + time * 0.3;
    color = hueShift(color, hueRot * colorShiftAmt);
    color = mix(color, vec3<f32>(0.1, 0.0, 0.2), (1.0 - inPortal) * 0.3);

    // Idea 2 — exact-C throat ghost
    let prev = textureLoad(dataTextureC, coord, 0);
    color = mix(color, prev.rgb, inPortal * (0.18 + treble * 0.12));
  }

  let glowColor = vec3<f32>(0.4, 0.7, 1.0);
  color = color + glowColor * edge * 2.0 * (1.0 + mouseDown) * (1.0 + bass * 0.35);

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    let live = step(0.0, elapsed) * (1.0 - step(2.0, elapsed));
    let rPos = ripple.xy;
    let rLocal = (uv - rPos) * vec2<f32>(aspect, 1.0);
    let rDist = length(rLocal);
    let rRadius = portalRadius * 0.5 * smoothstep(0.0, 0.3, elapsed) * smoothstep(2.0, 1.0, elapsed);
    let rInPortal = smoothstep(rRadius, rRadius * 0.8, rDist) * live;
    let rEdge = (smoothstep(rRadius * 1.2, rRadius * 0.9, rDist) - smoothstep(rRadius * 0.9, rRadius * 0.7, rDist)) * live;

    if (rInPortal > 0.01) {
      let rAngle = atan2(rLocal.y, rLocal.x) + elapsed * 3.0;
      let rCompressed = (rDist / max(rRadius, 0.001)) * (rDist / max(rRadius, 0.001)) * rRadius;
      let rWormhole = clamp(rPos + vec2<f32>(cos(rAngle), sin(rAngle)) * rCompressed / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));
      let rColor = textureSampleLevel(readTexture, u_sampler, 1.0 - rWormhole, 0.0).rgb;
      color = mix(color, hueShift(rColor, elapsed + f32(i)), rInPortal * 0.5);
    }
    color = color + glowColor * rEdge * 0.5;
  }

  let mapped = acesToneMap(color);
  let alpha = clamp(abs(edge) * 2.0 + inPortal * 0.3 + srcA * 0.2, 0.05, 1.0);
  let outCol = vec4<f32>(mapped, alpha);

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(d, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, outCol);
}
