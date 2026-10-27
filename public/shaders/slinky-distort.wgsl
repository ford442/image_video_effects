// ═══════════════════════════════════════════════════════════════════════════════
//  Slinky Distort - Advanced Alpha
//  Alpha Mode: Effect Intensity Alpha
//  Features: advanced-alpha, spiral-distortion, spring-physics, mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-10-27
//  Ideas: hand-tight wraps at the cursor; wire-cylinder shading
//  A packing: linear display RGBA in A (echo history); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 5: Effect Intensity Alpha
fn effectIntensityAlpha(
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    intensity: f32
) -> f32 {
    let displacement = length(displacedUV - originalUV);
    let displacementAlpha = smoothstep(0.0, 0.08, displacement);
    
    let edgeDist = min(min(originalUV.x, 1.0 - originalUV.x),
                       min(originalUV.y, 1.0 - originalUV.y));
    let edgeFade = smoothstep(0.0, 0.04, edgeDist);
    
    return baseAlpha * mix(0.5, 1.0, displacementAlpha * intensity) * edgeFade;
}

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.4, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

// Combined advanced alpha
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn calculateAdvancedAlpha(
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    params: vec4<f32>
) -> f32 {
    let effectAlpha = effectIntensityAlpha(originalUV, displacedUV, baseAlpha, params.x);
    let depthAlpha = depthLayeredAlpha(displacedUV, params.z);
    return clamp(effectAlpha * depthAlpha, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters — bass stretches the spring, mids add coils
    let coils = (u.zoom_params.x * 10.0 + 3.0) * (1.0 + mids * 0.35);
    let amplitude = u.zoom_params.y * 0.1 * (1.0 + bass * 0.6);
    let depthWeight = u.zoom_params.z;               // Depth influence
    let tightness = u.zoom_params.w * 2.0 + 0.5;     // Coil tightness

    let mousePos = u.zoom_config.yz;

    // Distance from mouse
    let aspect = resolution.x / resolution.y;
    let d = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(d);
    let angle = atan2(d.y, d.x);

    // Idea 2: treble compression pulse — an accordion wave travels outward along
    // the coil, briefly bunching and stretching the wraps on treble energy.
    let compression = 1.0 + treble * 0.6 * sin(dist * 8.0 - time * 4.0);

    // ── Idea 1: hand-tight wraps ────────────────────────────────────
    // Frequency rises toward the cursor and loosens with distance.
    // Tightness still scales the whole spring. The echo uses the same
    // local frequency so it stays on the coil.
    let hand = exp(-dist * 3.2);
    let localCoils = coils * (1.0 + hand * 1.4);

    // Slinky spiral effect
    let spiralPhase = dist * localCoils * tightness * compression - time * 2.0;
    let spiralOffset = sin(spiralPhase) * amplitude;
    
    // Create spiral displacement
    let normal = vec2<f32>(cos(angle), sin(angle));
    let tangent = vec2<f32>(-sin(angle), cos(angle));
    
    // Displace along spiral path, plus a tangential twist (torsion) on the beat
    let falloff = 1.0 - smoothstep(0.0, 0.5, dist);
    let twist = cos(spiralPhase) * amplitude * bass * 0.8;
    let displacement = (normal * spiralOffset + tangent * twist) * falloff;
    
    let warpedUV = clamp(uv + displacement / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));
    
    // Sample with warped coordinates
    let sample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);

    // Idea 1: elastic overshoot echo — re-warp with a slightly earlier spiral
    // phase and read that lagged position back from the previous frame's
    // display history (dataTextureC), so the coil trails a springy afterimage
    // instead of snapping to a single static warp.
    let laggedPhase = dist * localCoils * tightness * compression - (time - 0.12) * 2.0;
    let laggedOffset = sin(laggedPhase) * amplitude;
    let laggedTwist = cos(laggedPhase) * amplitude * bass * 0.8;
    let laggedDisplacement = (normal * laggedOffset + tangent * laggedTwist) * falloff;
    let laggedUV = clamp(uv + laggedDisplacement / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let historyDims = vec2<i32>(textureDimensions(dataTextureC));
    let laggedCoord = clamp(vec2<i32>(laggedUV * vec2<f32>(historyDims)), vec2<i32>(0), historyDims - vec2<i32>(1));
    let echoHistory = textureLoad(dataTextureC, laggedCoord, 0);
    let echoWeight = select(0.0, clamp(abs(spiralOffset) * 3.0 * (0.3 + depthWeight * 0.7), 0.0, 0.4), echoHistory.a > 0.001);
    let echoedRgb = mix(sample.rgb, echoHistory.rgb, echoWeight);

    // Apply slinky coloring based on spiral phase
    let colorShift = vec3<f32>(
        0.5 + 0.5 * sin(spiralPhase),
        0.5 + 0.5 * sin(spiralPhase + 2.09),
        0.5 + 0.5 * sin(spiralPhase + 4.18)
    );
    
    var finalColor = mix(echoedRgb, echoedRgb * colorShift, abs(spiralOffset) * 5.0);

    // ── Idea 2: wire cylinder ───────────────────────────────────────
    // One side of each wrap darkens. The crest highlight below stays
    // the bright side of the wire.
    let wireShade = 0.72 + 0.28 * sin(spiralPhase);
    finalColor = finalColor * wireShade;

    // Bass puts a metallic highlight on the coil crests
    let crest = pow(max(0.0, sin(spiralPhase)), 12.0) * falloff;
    finalColor = finalColor + vec3<f32>(0.8, 0.9, 1.0) * crest * bass * 0.5;

    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = clamp(calculateAdvancedAlpha(uv, warpedUV, sample.a, u.zoom_params)
                      + crest * bass * 0.25, 0.0, 1.0);

    let linearRgb = max(finalColor, vec3<f32>(0.0));
    let displayRgb = aces_tonemap(linearRgb);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(displayRgb, alpha));
    // Echo history stays linear so the next frame does not tone-map twice.
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(linearRgb, alpha));

    // Depth pass-through with spiral modulation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r;
    let depthMod = 1.0 + abs(spiralOffset) * 0.5;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
