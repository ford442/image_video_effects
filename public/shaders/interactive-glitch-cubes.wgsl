// ═══════════════════════════════════════════════════════════════════
//  Interactive Glitch Cubes
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, click-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-27
//  Ideas: height bevel; extruded side wall
//  A packing: [linear rgb, settledHeight]; ACES on the display write only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(1.0));
  let ar = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let held = step(0.5, u.zoom_config.w);

  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var rippleIndex: u32 = 0u; rippleIndex < rippleCount; rippleIndex = rippleIndex + 1u) {
    let ripple = u.ripples[rippleIndex];
    let rippleAge = max(time - ripple.z, 0.0);
    let front = abs(distance(uv, ripple.xy) - rippleAge * (0.22 + bass * 0.12));
    clickFront += exp(-front * 120.0) * exp(-rippleAge * 1.6);
  }

  let gridSize = 5.0 + u.zoom_params.x * 50.0 * (1.0 + bass * 0.2);
  let extrusion = u.zoom_params.y * (1.0 + bass * 0.4) * (1.0 + held * 0.4);
  let gapBase = u.zoom_params.z * 0.5;
  let shadowStr = u.zoom_params.w;

  let st = uv * vec2<f32>(ar, 1.0) * gridSize;
  let i_st = floor(st);
  let f_st = fract(st);
  let tileCenterUV = (i_st + 0.5) / gridSize / vec2<f32>(ar, 1.0);
  let mouse = u.zoom_config.yz;
  let dist = distance(tileCenterUV, mouse);
  let influence = smoothstep(0.5, 0.0, dist) * mix(0.16, 1.0, held);
  let cubeSweep = pow(max(0.0, sin(i_st.x * 0.73 + i_st.y * 0.41 - time * (11.0 + mids * 7.0))), 12.0);
  let conveyor = pow(max(0.0, sin((tileCenterUV.y + tileCenterUV.x * 0.35) * 42.0 - time * (16.0 + bass * 6.0))), 16.0);
  let height = clamp(influence * extrusion * 2.0 + clickFront * 0.55 + cubeSweep * extrusion * 0.16, 0.0, 2.5);

  let baseScale = 1.0 - gapBase;
  let scale = baseScale * (1.0 + height * 0.3);
  let viewVec = tileCenterUV - vec2<f32>(0.5, 0.5);
  let shift = viewVec * height * 0.1 + vec2<f32>(conveyor * 0.008 / ar, 0.0);
  let shiftLocal = shift * vec2<f32>(ar, 1.0) * gridSize;
  let faceCenter = vec2<f32>(0.5) + shiftLocal;
  let distFace = abs(f_st - faceCenter);
  let limit = scale * 0.5;
  let grout = smoothstep(0.08, 0.0, min(limit - distFace.x, limit - distFace.y) / max(limit, 0.001));

  var color = vec3<f32>(0.05);
  var alpha = 0.3;
  var isFace = false;
  if (distFace.x < limit && distFace.y < limit) {
    isFace = true;
    let posOnFace = (f_st - faceCenter) / scale;
    let sampleUV = tileCenterUV + posOnFace / gridSize / vec2<f32>(ar, 1.0);
    let edgeDist = min(limit - distFace.x, limit - distFace.y) / limit;
    let edgeGlow = smoothstep(0.0, 0.3, edgeDist) * treble * 0.3;
    let rUV = sampleUV + vec2<f32>(edgeGlow * 0.01 / ar, 0.0);
    let bUV = sampleUV - vec2<f32>(edgeGlow * 0.01 / ar, 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    color = vec3<f32>(r, g, b) + height * 0.1;
    // ── Idea 1: height bevel ──────────────────────────────────────
    // The face is lighter toward its top edge, in proportion to how far
    // the cube is extruded. A flat tile (height ≈ 0) stays even.
    let shade = 1.0 + (0.5 - posOnFace.y) * clamp(height, 0.0, 1.5) * 0.55;
    color *= shade;
    alpha = clamp(0.8 + height * 0.2, 0.0, 1.0);
  } else {
    let shadowCenter = vec2<f32>(0.5) + viewVec * 0.05;
    let distShadow = abs(f_st - shadowCenter);
    let shadowLimit = baseScale * 0.5;
    if (distShadow.x < shadowLimit && distShadow.y < shadowLimit) {
      color = vec3<f32>(0.0);
      alpha = 0.5 + shadowStr * 0.3;
    }
  }

  let prev = textureLoad(dataTextureC, pixel, 0);
  let settledHeight = mix(height, prev.a * 0.92, 0.05 + mids * 0.02);
  var settledColor = mix(color, prev.rgb * 0.9, 0.03 + bass * 0.01);
  if (isFace) {
    let sparkle = pow(max(0.0, sin(time * (19.0 + treble * 8.0) + hash(i_st) * 6.2831853)), 20.0) * treble * 0.20;
    settledColor += sparkle;
  }
  let slick = hsv2rgb(vec3<f32>(fract(0.82 + hash(i_st) * 0.2 + mids * 0.15 + time * 0.08), 0.7, 1.0));
  settledColor = mix(settledColor, settledColor * slick * 1.2, grout * 0.35 * f32(isFace));
  settledColor += vec3<f32>(0.2, 0.55, 1.0) * conveyor * (0.03 + mids * 0.10);
  settledColor += vec3<f32>(1.0, 0.28, 0.72) * clickFront * 0.10;
  settledColor += slick * (grout * 0.16 * f32(isFace) + clickFront * 0.2);
  // ── Idea 2: extruded side wall ──────────────────────────────────
  // The ring just outside the grown face is the side of the cube: the
  // tile colour, darkened. It only appears once the face has height.
  // The cast shadow stays the shadow branch above.
  let faceMask = select(0.0, 1.0, isFace);
  let outsideFace = max(distFace.x, distFace.y);
  let wallBand = limit + 0.02 + height * 0.15;
  let wall = (1.0 - smoothstep(limit, wallBand, outsideFace)) * (1.0 - faceMask) * smoothstep(0.02, 0.12, height);
  let shadowCenterW = vec2<f32>(0.5) + viewVec * 0.05;
  let distShadowW = abs(f_st - shadowCenterW);
  let shadowLimitW = baseScale * 0.5;
  let inShadow = select(0.0, 1.0, distShadowW.x < shadowLimitW && distShadowW.y < shadowLimitW);
  let wallCol = textureSampleLevel(readTexture, u_sampler, clamp(tileCenterUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * vec3<f32>(0.22, 0.18, 0.26);
  settledColor = mix(settledColor, wallCol, wall * (1.0 - inShadow) * (0.65 + shadowStr * 0.35));
  settledColor = clamp(settledColor, vec3<f32>(0.0), vec3<f32>(1.0));

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthAlpha = mix(alpha, 1.0, depth * 0.3);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(settledColor), depthAlpha));
  textureStore(dataTextureA, pixel, vec4<f32>(settledColor, settledHeight));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + settledHeight * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
}
