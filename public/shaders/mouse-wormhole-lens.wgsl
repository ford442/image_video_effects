// ═══════════════════════════════════════════════════════════════════
//  mouse-wormhole-lens
//  Category: interactive-mouse
//  Features: mouse-driven, portal, spatial-distortion
//  Complexity: High
//  Chunks From: chunk-library.md (hueShift)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  Mouse position creates a wormhole portal. Inside the radius, the
//  image is inverted, color-shifted, and spirally distorted. The
//  portal edge has an event-horizon glow with lensing. Dragging
//  stretches the wormhole into an oval.
//  Alpha channel stores portal edge intensity.
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

// ═══ CHUNK: hueShift (from stellar-plasma.wgsl) ═══
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let portalRadius = mix(0.1, 0.4, u.zoom_params.x);
  let spiralStrength = mix(0.0, 3.0, u.zoom_params.y);
  let colorShiftAmt = mix(0.0, 1.57, u.zoom_params.z);
  let lensStrength = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = mousePos - prevMouse;
  let mouseDown = u.zoom_config.w;

  // Store mouse position
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  // Wormhole stretch from drag velocity
  let stretchDir = select(vec2<f32>(1.0, 0.0), normalize(mouseVel), length(mouseVel) > 0.001);
  let stretchAmount = length(mouseVel) * 2.0;

  // Transform to portal-local space with stretch
  var local = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let stretchDot = dot(local, stretchDir);
  let stretchPerp = local - stretchDir * stretchDot;
  local = stretchDir * stretchDot * (1.0 + stretchAmount) + stretchPerp;

  let localDist = length(local);
  let localAngle = atan2(local.y, local.x);

  // Portal boundary
  let inPortal = smoothstep(portalRadius, portalRadius * 0.85, localDist);
  let edge = smoothstep(portalRadius * 1.1, portalRadius * 0.9, localDist) -
             smoothstep(portalRadius * 0.9, portalRadius * 0.7, localDist);

  // Default: sample outside normally
  var sampleUV = uv;

  if (inPortal > 0.01) {
    // Inside wormhole: invert, spiral, and compress
    let normalizedDist = localDist / portalRadius;
    let spiralAngle = localAngle + (1.0 - normalizedDist) * spiralStrength * 3.14159 + time * 0.5;
    let compressedDist = normalizedDist * normalizedDist * portalRadius;

    var wormholeLocal = vec2<f32>(cos(spiralAngle), sin(spiralAngle)) * compressedDist;
    // Undo stretch
    let whStretchDot = dot(wormholeLocal, stretchDir);
    let whStretchPerp = wormholeLocal - stretchDir * whStretchDot;
    wormholeLocal = stretchDir * whStretchDot / (1.0 + stretchAmount) + whStretchPerp;

    sampleUV = mousePos + wormholeLocal / vec2<f32>(aspect, 1.0);

    // Also invert UV for extra weirdness
    sampleUV = 1.0 - sampleUV;
  }

  // Gravitational lensing near edge
  let lensDir = select(vec2<f32>(0.0), normalize(local), localDist > 0.001);
  let lensOffset = lensDir * edge * lensStrength * 0.05 / max(localDist, 0.01);
  sampleUV = sampleUV + lensOffset / vec2<f32>(aspect, 1.0);

  var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

  // Color shift inside portal
  if (inPortal > 0.01) {
    let hueRot = localAngle * 0.5 + time * 0.3;
    color = hueShift(color, hueRot * colorShiftAmt);
    // Deep space tint
    color = mix(color, vec3<f32>(0.1, 0.0, 0.2), (1.0 - inPortal) * 0.3);
  }

  // Event horizon glow
  let glowColor = vec3<f32>(0.4, 0.7, 1.0);
  color = color + glowColor * edge * 2.0 * (1.0 + mouseDown);

  // Ripple wormholes: secondary portals
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rPos = ripple.xy;
      let rLocal = (uv - rPos) * vec2<f32>(aspect, 1.0);
      let rDist = length(rLocal);
      let rRadius = portalRadius * 0.5 * smoothstep(0.0, 0.3, elapsed) * smoothstep(2.0, 1.0, elapsed);
      let rInPortal = smoothstep(rRadius, rRadius * 0.8, rDist);
      let rEdge = smoothstep(rRadius * 1.2, rRadius * 0.9, rDist) - smoothstep(rRadius * 0.9, rRadius * 0.7, rDist);

      if (rInPortal > 0.01) {
        let rAngle = atan2(rLocal.y, rLocal.x) + elapsed * 3.0;
        let rCompressed = (rDist / rRadius) * (rDist / rRadius) * rRadius;
        let rWormhole = rPos + vec2<f32>(cos(rAngle), sin(rAngle)) * rCompressed / vec2<f32>(aspect, 1.0);
        let rColor = textureSampleLevel(readTexture, u_sampler, 1.0 - rWormhole, 0.0).rgb;
        color = mix(color, hueShift(rColor, elapsed + f32(i)), rInPortal * 0.5);
      }
      color = color + glowColor * rEdge * 0.5;
    }
  }

  // Alpha = portal edge intensity
  let alpha = clamp(abs(edge) * 2.0 + inPortal * 0.3, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
