// ===============================================================
// Chromatic Folds 2 – Color as Physical Dimension
// The image becomes a higher-dimensional manifold where RGB
// channels exist as spatial coordinates that can be folded,
// twisted, and bent through topological transformations.
// Implements Möbius, Klein, and Hyperbolic fold types.
// ===============================================================
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
   config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
   zoom_params: vec4<f32>,       // x=globalIntensity, y=hyperFactor, z=twistRate, w=chromaticScale
   zoom_config: vec4<f32>,       // x=depthInfluence, y=foldSharpness, z=rotationSpeed, w=dimensionalFold
   ripples:     array<vec4<f32>, 50>, // Used as folds: x, y, foldType, phase
};

// ---------------------------------------------------------------
// Möbius strip fold - twists color space with half-turn inversion
// ---------------------------------------------------------------
fn mobiusFold(pos: vec3<f32>, uv: vec2<f32>, center: vec2<f32>, strength: f32) -> vec3<f32> {
   let localUV = uv - center;
   let angle = atan2(localUV.y, localUV.x);
   
   // Möbius twist: inverts and swaps channels based on angular position
   let twist = sin(angle * 0.5 + 3.14159) * strength * 0.5;
   var outPos = pos;
   
   // Non-orientable transformation: R->G, G->1-R, B->R
   outPos.x = mix(pos.x, pos.y, twist);
   outPos.y = mix(pos.y, 1.0 - pos.x, twist);
   outPos.z = mix(pos.z, pos.x, twist * 0.7);
   
   return outPos;
}

// ---------------------------------------------------------------
// Klein bottle fold - creates non-orientable surface where channels intersect
// ---------------------------------------------------------------
fn kleinFold(pos: vec3<f32>, uv: vec2<f32>, center: vec2<f32>, strength: f32) -> vec3<f32> {
   let localUV = (uv - center) * 2.0;
   let radius = length(localUV);
   
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
   
   return outPos;
}

// ---------------------------------------------------------------
// Hyperbolic fold - creates recursive color tunnels
// ---------------------------------------------------------------
fn hyperbolicFold(pos: vec3<f32>, uv: vec2<f32>, center: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
   let localUV = uv - center;
   let radius = length(localUV);
   
   // Hyperbolic distance creates infinite recursion effect
   let hyperDist = log(radius * 10.0 + 1.0);
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
   let angle = time * speed;
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

// ---------------------------------------------------------------
// Main Compute Shader
// ---------------------------------------------------------------
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
   let dimsI = textureDimensions(videoTex);
   let dims = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
   if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) {
       return;
   }

   let uv = vec2<f32>(gid.xy) / dims;
   let time = u.config.x;
   
   // Sample source color and depth
   let srcColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
   let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
   
   // RGB becomes XYZ in chromatic manifold
   var colorPos = srcColor;
   
   // ──────────────────────────────────────────────────────────────────────────
   //  Parameters
   // ──────────────────────────────────────────────────────────────────────────
   let globalIntensity = u.zoom_params.x;
   let hyperFactor = u.zoom_params.y;
   let twistRate = u.zoom_params.z;
   let chromaticScale = u.zoom_params.w * 2.0;
   let depthInfluence = u.zoom_config.x;
   let foldSharpness = u.zoom_config.y;
   let rotationSpeed = u.zoom_config.z * 2.0;
   let dimensionalFold = u.zoom_config.w;
   
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
       let foldCenter = vec2<f32>(
           0.5 + sin(time * 0.3 + fi * 1.2) * 0.35,
           0.5 + cos(time * 0.4 + fi * 0.9) * 0.35
       );
       let foldType = i % 3u; // Cycle through Möbius, Klein, Hyperbolic
       let foldPhase = fi * 0.5;
       
       // Calculate distance to fold center
       let distToFold = distance(uv, foldCenter);
       let foldRadius = 0.3 + foldSharpness * 0.2;
       
       // Fold influence falls off with distance
       let foldInfluence = (1.0 - smoothstep(0.0, foldRadius, distToFold)) * 
                          (sin(time * 0.5 + foldPhase) * 0.5 + 0.5);
       
       // Depth-aware fold strength
       let localFoldStrength = foldInfluence * depthFoldBoost * globalIntensity;
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
   let clampedAbUV = clamp(aberrationUV, vec2<f32>(0.0), vec2<f32>(1.0));
   
   // Sample with chromatic aberration for final output
   var outColor = textureSampleLevel(videoTex, videoSampler, clampedAbUV, 0.0).rgb;
   
   // Mix with folded color space for psychedelic topology effect
   outColor = mix(outColor, finalColorPos, totalFoldStrength * 0.6);
   
   // ──────────────────────────────────────────────────────────────────────────
   //  Boost saturation in folded regions to emphasize color-as-dimension
   // ──────────────────────────────────────────────────────────────────────────
   let foldBoost = 1.0 + totalFoldStrength * 0.5;
   outColor = pow(max(outColor, vec3<f32>(0.001)), vec3<f32>(1.0 / foldBoost));
   
   // ──────────────────────────────────────────────────────────────────────────
   //  Feedback blend for persistence
   // ──────────────────────────────────────────────────────────────────────────
   let prev = textureSampleLevel(feedbackTex, videoSampler, uv, 0.0).rgb;
   let feedbackMix = 0.85;
   let finalColor = mix(outColor, prev, feedbackMix);
   
   // ──────────────────────────────────────────────────────────────────────────
   //  Output
   // ──────────────────────────────────────────────────────────────────────────
   textureStore(outTex, gid.xy, vec4<f32>(finalColor, 1.0));
   textureStore(feedbackOut, gid.xy, vec4<f32>(finalColor, 1.0));
   
   // Update depth texture with fold-distorted depth
   let foldDepthOffset = totalFoldStrength * 0.1;
   let newDepth = clamp(depth + foldDepthOffset, 0.0, 1.0);
   textureStore(outDepth, gid.xy, vec4<f32>(newDepth, 0.0, 0.0, 0.0));
}
