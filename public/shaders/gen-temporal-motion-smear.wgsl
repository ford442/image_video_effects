// ═══════════════════════════════════════════════════════════════════
//  Temporal Motion Smear - Motion-aware temporal smearing
//  Category: generative
//  Features: generative, audio-reactive, temporal, depth-aware, upgraded-rgba
//  Complexity: High
//  Created: 2026-03-22
//  By: Agent 4A
//  Upgraded: 2026-06-06, 2026-11-21
//  Ideas: shutter tent; upstream trail
//  A packing: ACES display RGBA (C is that trail)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn luma3(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
}

// Motion from this frame versus exact C, and the gradient of that history.
fn detectMotion(coord: vec2<i32>, dims: vec2<i32>) -> vec2<f32> {
    let current = textureLoad(readTexture, coord, 0).rgb;
    let previous = textureLoad(dataTextureC, coord, 0).rgb;
    let diff = abs(luma3(current) - luma3(previous));
    let right = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), dims), 0).rgb;
    let left = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), dims), 0).rgb;
    let up = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), dims), 0).rgb;
    let down = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), dims), 0).rgb;
    let dx = luma3(right - left) * 0.5;
    let dy = luma3(up - down) * 0.5;
    return vec2<f32>(dx, dy) * diff * 10.0;
}

// ── Idea 1: shutter tent ──────────────────────────────────────────
// Same eight taps along the motion direction. The head (i = 0) is full
// weight and the tail thins, which is an open shutter rather than a box.
fn shutterBlur(uv: vec2<f32>, dir: vec2<f32>, radius: f32) -> vec3<f32> {
    var result = vec3<f32>(0.0);
    var wsum = 0.0;
    for (var i: i32 = 0; i < 8; i = i + 1) {
        let t = f32(i) / 7.0;
        let w = 1.0 - t * 0.85;
        let offset = dir * radius * t;
        let tap = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        result += tap * w;
        wsum += w;
    }
    return result / max(wsum, 0.001);
}

// Hue shift for trail coloring
fn hueShift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(shift);
    return vec3<f32>(color * cosAngle + cross(k, color) * sin(shift) + k * dot(k, color) * (1.0 - cosAngle));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let bass = plasmaBuffer[0].x;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let dims = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
    
    // Parameters - safe randomization
    let persistence = mix(0.7, 0.99, u.zoom_params.x);
    let sensitivity = mix(0.5, 5.0, u.zoom_params.y);
    let directionality = u.zoom_params.z; // 0=omni, 1=direction-aware
    let intensityBoost = mix(0.5, 2.0, u.zoom_params.w);
    
    // Get current frame
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Detect motion, then read the trail one step upstream of it.
    let motion = detectMotion(coord, dims) * sensitivity;
    let motionStrength = length(motion);
    // ── Idea 2: upstream trail ────────────────────────────────────────
    // Directionality 0 keeps the ghost on this pixel (omni mode). Otherwise
    // the decayed light is the history that was just upstream.
    let stepUv = clamp(motion, vec2<f32>(-0.05), vec2<f32>(0.05)) * directionality;
    let advectCoord = clamp(vec2<i32>(clamp(uv - stepUv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), dims);
    let prevTrail = textureLoad(dataTextureC, advectCoord, 0);

    let decay = min(mix(persistence * 0.9, persistence, smoothstep(0.1, 0.5, motionStrength)) * (1.0 + bass * 0.02), 0.985);

    let blurDir = normalize(motion + vec2<f32>(0.001));
    let blurRadius = motionStrength * 0.05 * directionality;
    let blurred = shutterBlur(uv, blurDir, blurRadius);
    let velocityColor = mix(
        vec3<f32>(0.3, 0.5, 0.9),
        vec3<f32>(0.9, 0.6, 0.2),
        smoothstep(0.0, 1.0, motionStrength)
    );
    let tinted = mix(blurred, blurred * velocityColor * 1.5, 0.4);
    let moving = step(0.01, motionStrength);
    var smearedColor = mix(current.rgb, tinted, moving);
    var alpha = mix(current.a, mix(current.a, 1.0, min(motionStrength * 0.5, 0.5)), moving);
    
    // Accumulate trails with decay
    let trailContribution = prevTrail.rgb * decay;
    
    // Combine: current smeared + decayed trail
    // Use max for light-trail effect, or mix for ghosting
    var finalColor = max(smearedColor * intensityBoost, trailContribution * 0.95);
    
    // Add subtle color shift based on trail age (branchless)
    let trailAge = length(prevTrail.rgb);
    let ageShift = hueShift(finalColor, trailAge * 0.1);
    finalColor = mix(finalColor, ageShift, f32(trailAge > 0.1));
    
    // Fade to black if very little motion (branchless)
    let shouldFade = f32(motionStrength < 0.001 && length(trailContribution) < 0.01);
    finalColor = mix(finalColor, finalColor * 0.99, shouldFade);
    
    // Pass through depth early for chromatic + alpha
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Vignette for alpha
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    alpha = alpha * vignette;
    
    // Chromatic aberration + ACES
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    finalColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);
    finalColor = acesToneMap(max(finalColor, vec3<f32>(0.0)) * 1.1);

    // Store accumulated trail
    let trailOutput = vec4<f32>(finalColor, alpha);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), trailOutput);
    
    // Write output
    textureStore(writeTexture, vec2<i32>(global_id.xy), trailOutput);
    
    // Pass through depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
