// ═══════════════════════════════════════════════════════════════════
//  Chromatic Folds V2
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-09, 2026-11-01
//  Ideas: Klein orientation seam; Möbius fiber twist; Poincaré-disk fold distance; Cauchy-split fold aberration; held cursor drags a fold centre
//  A packing: pre-ACES display RGB in A (C is color history)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// ---------------------------------------------------------------
// Möbius strip fold - twists color space with half-turn inversion
// ---------------------------------------------------------------
fn mobiusFold(pos: vec3<f32>, uv: vec2<f32>, center: vec2<f32>, strength: f32) -> vec3<f32> {
   let localUV = uv - center;
   var angle = atan2(localUV.y, localUV.x);
   
   // Möbius twist: inverts and swaps channels based on angular position
   let twist = sin(angle * 0.5 + 3.14159) * strength * 0.5;
   var outPos = pos;
   
   // Non-orientable transformation: R->G, G->1-R, B->R
   outPos.x = mix(pos.x, pos.y, twist);
   outPos.y = mix(pos.y, 1.0 - pos.x, twist);
   outPos.z = mix(pos.z, pos.x, twist * 0.7);

   // Fiber twist around the existing channel swap (half-turn with angle).
   let fiber = angle * 0.5 * strength;
   let cs = cos(fiber);
   let sn = sin(fiber);
   let gy = outPos.y * cs - outPos.z * sn;
   let bz = outPos.y * sn + outPos.z * cs;
   outPos.y = gy;
   outPos.z = bz;
   
   return outPos;
}

// ---------------------------------------------------------------
// Klein bottle fold - creates non-orientable surface where channels intersect
// ---------------------------------------------------------------
fn kleinFold(pos: vec3<f32>, uv: vec2<f32>, center: vec2<f32>, strength: f32) -> vec3<f32> {
   var localUV = (uv - center) * 2.0;
   var radius = length(localUV);
   
   // Klein bottle parametric distortion
   let fold = smoothstep(0.0, 1.0, radius) * strength;
   var outPos = pos;
   
   // Channels pass through each other in 4D space projection
   if (radius > 0.01) {
       let crossing = sin(atan2(localUV.y, localUV.x) * 3.0) * fold;
       outPos.x = mix(pos.x, pos.y, crossing);
       outPos.y = mix(pos.y, pos.z, crossing);
       outPos.z = mix(pos.z, pos.x, crossing);
   }
   
   // Self-intersection region creates color singularities
   let singularity = 1.0 - smoothstep(0.0, 0.2, abs(radius - 0.5));
   outPos = outPos + vec3<f32>(singularity * fold * 0.3);

   // Orientation seam: the Klein join flips color where the angle crosses zero.
   let orient = sin(atan2(localUV.y, localUV.x));
   let seam = smoothstep(0.14, 0.0, abs(orient)) * fold;
   outPos = mix(outPos, vec3<f32>(1.0) - outPos, seam * 0.85);
   
   return outPos;
}

// ---------------------------------------------------------------
// Hyperbolic fold - creates recursive color tunnels
// ---------------------------------------------------------------
fn hyperbolicFold(pos: vec3<f32>, uv: vec2<f32>, center: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
   var localUV = uv - center;
   var radius = length(localUV);
   
   // Idea 1: Poincaré-disk distance. The fold used log(10r+1); the hyperbolic distance
   // of a point at Euclidean radius r in the unit disk is 2·atanh(r) = ln((1+r)/(1-r)),
   // so rings pile up toward the rim like an Escher tunnel. r is capped below 1.
   let rDisk = min(radius * 1.8, 0.97);
   let hyperDist = log((1.0 + rDisk) / (1.0 - rDisk)) * 2.2;
   let foldWave = sin(hyperDist * 8.0 - time * 2.0) * strength;
   
   // Recursive color space compression
   var outPos = pos;
   let compression = 1.0 + foldWave * 0.5;
   
   // Fold color space back onto itself
   outPos = fract(pos * compression);
   outPos = mix(pos, outPos, smoothstep(0.0, 0.5, radius) * strength);
   
   return outPos;
}

// ---------------------------------------------------------------
// 4D Quaternion rotation projected to 3D color space
// ---------------------------------------------------------------
fn quaternionRotate(pos: vec3<f32>, time: f32, speed: f32) -> vec3<f32> {
   // Simplified 4D rotation: rotate in XW and YW planes
   var angle = time * speed;
   let cosA = cos(angle);
   let sinA = sin(angle);
   
   // XW rotation affects R channel
   let newX = pos.x * cosA - sinA * 0.5;
   let newW1 = pos.x * sinA + cosA * 0.5;
   
   // YW rotation affects G channel
   let newY = pos.y * cosA - sinA * newW1;
   
   return vec3<f32>(newX, newY, pos.z);
}

// ---------------------------------------------------------------
// Chromatic aberration from fold edges
// ---------------------------------------------------------------
fn chromaticAberration(uv: vec2<f32>, foldStrength: f32, chromaticScale: f32) -> vec2<f32> {
   let aberration = foldStrength * chromaticScale * 0.02;
   return uv + vec2<f32>(
       sin(uv.y * 10.0) * aberration,
       cos(uv.x * 10.0) * aberration
   );
}

// Idea 2: Cauchy-split — the aberration used to move R, G and B together, which is not
// chromatic. n(λ) = 1 + B/λ² at 650/550/450 nm, relative to green, scales the SAME
// displacement per channel (red < 1 < blue), so folds fringe like glass.
fn cauchyScale() -> vec3<f32> {
   let lam = vec3<f32>(0.650, 0.550, 0.450);
   let n = vec3<f32>(1.0) + 0.10 / (lam * lam);
   return n / n.y;
}

// ---------------------------------------------------------------
// Main Compute Shader
// ---------------------------------------------------------------
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
   let a = 2.51;
   let b = 0.03;
   let c = 2.43;
   let d = 0.59;
   let e = 0.14;
   return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

   var uv = vec2<f32>(gid.xy) / dims;
   let time = u.config.x;
   let bass = plasmaBuffer[0].x;
   let mids = plasmaBuffer[0].y;
   let treble = plasmaBuffer[0].z;
   
   // Sample source color and depth
   let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
   let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
   
   // RGB becomes XYZ in chromatic manifold
   var colorPos = srcColor;
   
   // ──────────────────────────────────────────────────────────────────────────
   //  Parameters
   // ──────────────────────────────────────────────────────────────────────────
   // JSON order global_intensity / hyper_factor / twist_rate / chromatic_scale → zoom_params.xyzw.
   // HEAD read these from zoom_config (time / mouse / down), so intensity grew with uptime; the
   // four former zoom_params reads have no slider and sit at their old midpoints.
   let globalIntensity = u.zoom_params.x;
   let hyperFactor = u.zoom_params.y;
   let twistRate = u.zoom_params.z;
   let chromaticScale = u.zoom_params.w * 2.0;
   let depthInfluence = 0.5;
   let foldSharpness = 0.5;
   let rotationSpeed = 1.0;
   let dimensionalFold = 0.5;
   let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
   let mouseHeld = select(0.0, 1.0, u.zoom_config.w > 0.5);
   
   // Depth-modulated fold intensity (foreground folds more)
   let depthFoldBoost = 1.0 + (1.0 - depth) * depthInfluence * 2.0;
   
   // ──────────────────────────────────────────────────────────────────────────
   //  Generate dynamic fold centers based on time
   // ──────────────────────────────────────────────────────────────────────────
   var totalFoldStrength = 0.0;
   var accumulatedPos = colorPos;
   
   // Create 5 animated fold centers
   for (var i: u32 = 0u; i < 5u; i = i + 1u) {
       let fi = f32(i);
       var foldCenter = vec2<f32>(
           0.5 + sin(time * 0.3 + fi * 1.2) * 0.35,
           0.5 + cos(time * 0.4 + fi * 0.9) * 0.35
       );
       // Idea 3: while the pointer is held, fold centre 0 is dragged onto it. Hold-only:
       // an idle pointer parks at (0.5, 0.5) and would bake a fold into the default look.
       foldCenter = mix(foldCenter, mouse, mouseHeld * select(0.0, 0.85, i == 0u));
       let foldType = i % 3u; // Cycle through Möbius, Klein, Hyperbolic
       let foldPhase = fi * 0.5;
       
       // Calculate distance to fold center
       let distToFold = distance(uv, foldCenter);
       let foldRadius = 0.3 + foldSharpness * 0.2;
       
       // Fold influence falls off with distance
       let foldInfluence = (1.0 - smoothstep(0.0, foldRadius, distToFold)) * 
                          (sin(time * 0.5 + foldPhase) * 0.5 + 0.5);
       
       // Depth-aware fold strength
       let localFoldStrength = foldInfluence * depthFoldBoost * globalIntensity * (1.0 + bass * 0.2);
       totalFoldStrength = totalFoldStrength + localFoldStrength;
       
       // Apply fold based on type
       if (foldType == 0u) { // Möbius fold
           accumulatedPos = mobiusFold(accumulatedPos, uv, foldCenter, localFoldStrength);
       } else if (foldType == 1u) { // Klein bottle fold
           accumulatedPos = kleinFold(accumulatedPos, uv, foldCenter, localFoldStrength);
       } else { // Hyperbolic fold
           accumulatedPos = hyperbolicFold(accumulatedPos, uv, foldCenter, localFoldStrength, time + foldPhase);
       }
   }
   
   // ──────────────────────────────────────────────────────────────────────────
   //  Apply global hyper-dimensional rotation
   // ──────────────────────────────────────────────────────────────────────────
   if (hyperFactor > 0.0) {
       accumulatedPos = quaternionRotate(accumulatedPos, time * twistRate, rotationSpeed * hyperFactor);
   }
   
   // ──────────────────────────────────────────────────────────────────────────
   //  Dimensional fold: treat color as 4D with time as W dimension
   // ──────────────────────────────────────────────────────────────────────────
   if (dimensionalFold > 0.0) {
       let wCoord = sin(time * 0.3 + srcColor.r * 5.0) * dimensionalFold * 0.2;
       accumulatedPos = accumulatedPos + vec3<f32>(wCoord, wCoord * 0.5, -wCoord * 0.3);
   }
   
   // Clamp color space position back to valid range
   let finalColorPos = clamp(accumulatedPos, vec3<f32>(0.0), vec3<f32>(1.0));
   
   // ──────────────────────────────────────────────────────────────────────────
   //  Chromatic aberration from fold edges
   // ──────────────────────────────────────────────────────────────────────────
   let aberrationUV = chromaticAberration(uv, totalFoldStrength, chromaticScale);
   let abShift = aberrationUV - uv;
   let cs = cauchyScale();
   let uvR = clamp(uv + abShift * cs.x, vec2<f32>(0.0), vec2<f32>(1.0));
   let uvG = clamp(uv + abShift * cs.y, vec2<f32>(0.0), vec2<f32>(1.0));
   let uvB = clamp(uv + abShift * cs.z, vec2<f32>(0.0), vec2<f32>(1.0));
   
   // Sample with chromatic aberration for final output (Idea 2: per-channel Cauchy scale)
   var outColor = vec3<f32>(
       textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
       textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g,
       textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
   );
   
   // Mix with folded color space for psychedelic topology effect
   outColor = mix(outColor, finalColorPos, totalFoldStrength * 0.6);
   
   // ──────────────────────────────────────────────────────────────────────────
   //  Boost saturation in folded regions to emphasize color-as-dimension
   // ──────────────────────────────────────────────────────────────────────────
   let foldBoost = 1.0 + totalFoldStrength * 0.5;
   outColor = pow(max(outColor, vec3<f32>(0.001)), vec3<f32>(1.0 / foldBoost));
   
   var clickFront = 0.0;
   let rippleCount = min(u32(u.config.y), 50u);
   let aspect = dims.x / dims.y;
   for (var i = 0u; i < rippleCount; i = i + 1u) {
       let event = u.ripples[i];
       let age = max(time - event.z, 0.0);
       clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 58.0);
   }
   
   let clockRings = sin(length(uv - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0)) * totalFoldStrength;
   let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));
   outColor = outColor + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
   
   // ──────────────────────────────────────────────────────────────────────────
   //  Feedback blend for persistence
   // ──────────────────────────────────────────────────────────────────────────
   let prev = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0).rgb;
   let feedbackMix = 0.85;
   let finalColor = mix(outColor, prev, feedbackMix);
   
   // ──────────────────────────────────────────────────────────────────────────
   //  Output
   // ──────────────────────────────────────────────────────────────────────────
   let foldAlpha = clamp(0.28 + totalFoldStrength * 0.45, 0.0, 1.0);
   textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(aces_tonemap(finalColor), foldAlpha));
   textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(finalColor, foldAlpha));
   
   // Update depth texture with fold-distorted depth
   let foldDepthOffset = totalFoldStrength * 0.1;
   let newDepth = clamp(depth + foldDepthOffset, 0.0, 1.0);
   textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(newDepth, 0.0, 0.0, 0.0));
}
