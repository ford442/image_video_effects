// ═══════════════════════════════════════════════════════════════════════════════
//  Infinite Fractal Feedback - Advanced Alpha with Accumulative Alpha
//  Category: feedback/temporal
//  Alpha Mode: Accumulative Alpha (Feedback)
//  Features: advanced-alpha, fractal-feedback, infinite-zoom
//  Upgraded: 2026-11-10
//  Ideas: recursive zoom echo into focal point; per-generation hue drift; mandala spoke seams
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 3: Accumulative Alpha (Feedback Systems)
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.08) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    
    return vec4<f32>(color, totalAlpha);
}

fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0)); }

fn hueRotate(c: vec3<f32>, a: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735);
    let ca = cos(a);
    return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.5, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv_raw = vec2<f32>(global_id.xy);
    var uv = (uv_raw - resolution * 0.5) / min(resolution.x, resolution.y);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = (bass + mids + treble) / 3.0;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    var mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let uv01 = uv_raw / resolution;

    // Parameters
    let accumulationRate = u.zoom_params.x * 0.5 + 0.1;
    let spiralTightness = u.zoom_params.y;
    let colorShift = u.zoom_params.z;
    let feedbackStrength = u.zoom_params.w;
    let depthWeight = 0.5;

    // Polar coordinates from mouse focal point
    let focalOffset = uv - (mousePos - vec2<f32>(0.5, 0.5)) * 2.0;
    var polar = vec2<f32>(length(focalOffset), atan2(focalOffset.y, focalOffset.x));

    // Perpetual zoom and rotation
    let zoomRate = u.zoom_params.x + sin(time * 0.1 * audioReactivity) * 0.1;
    polar.x = fract(polar.x + time * zoomRate * audioReactivity * 0.05);
    polar.y = polar.y + time * (0.3 + step(0.5, u.zoom_config.w)) * audioReactivity * 0.2 + polar.x * spiralTightness;

    // Convert back to cartesian
    let newUV = vec2<f32>(polar.x * cos(polar.y), polar.x * sin(polar.y));
    let sampleUV = newUV * 0.5 + 0.5;

    // Multi-layered spiral sampling
    var finalColor = vec3<f32>(0.0, 0.0, 0.0);
    for (var i: u32 = 0u; i < 3u; i = i + 1u) {
        let fi = f32(i);
        let layerUV = sampleUV + vec2<f32>(sin(time + fi), cos(time + fi)) * 0.1;
        let color = textureSampleLevel(readTexture, u_sampler, fract(layerUV), 0.0).rgb;
        let hueShift = colorShift + fi * 0.33;
        finalColor = finalColor + color * (1.0 + sin(time * 2.0 * audioReactivity + hueShift)) * 0.5;
    }

    // Ripple click interaction
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((uv01 - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(uv) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));
    finalColor = finalColor + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);

    // Kaleidoscopic symmetry
    let angle = atan2(newUV.y, newUV.x);
    let segments = 6.0 + floor(sin(time * 0.5 * audioReactivity) * 3.0);
    let kaleidoAngle = floor(angle * segments / (2.0 * 3.14159)) * (2.0 * 3.14159) / segments;
    let symUV = vec2<f32>(cos(kaleidoAngle), sin(kaleidoAngle)) * length(newUV);
    let symColor = textureSampleLevel(readTexture, u_sampler, symUV * 0.5 + 0.5, 0.0).rgb;

 finalColor = mix(finalColor, symColor, 0.6);

    // Idea 3: mandala spoke seams on the kaleidoscope segment boundaries
    let segW = 6.28318 / segments;
    let segPhase = fract((angle + 3.14159) / segW);
    let seamDist = min(segPhase, 1.0 - segPhase) * segW * length(newUV);
    let seam = exp(-seamDist * 260.0) * smoothstep(0.02, 0.15, length(newUV)) * (0.35 + treble * 0.8);
    finalColor += hueRotate(vec3<f32>(1.0, 0.85, 0.6), colorShift * 3.14159 + polar.x * 6.28) * seam;
    
    // ═══ ACCUMULATIVE ALPHA CALCULATION ═══
    // Sample previous frame
    // Idea 1: recursive zoom echo — exact C load pulled toward the focal point,
    // so previous frames fall down the tunnel instead of being re-folded.
    let focal01 = mousePos;
    let zoomStep = 1.0 - clamp(0.015 + u.zoom_params.x * 0.025 + bass * 0.01, 0.0, 0.08);
    let echoUV = focal01 + (uv01 - focal01) * zoomStep;
    let echoCoord = clamp(vec2<i32>(echoUV * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
    var prev = textureLoad(dataTextureC, echoCoord, 0);
    // Idea 2: per-generation hue drift — each echo generation turns by colorShift
    prev = vec4<f32>(max(hueRotate(prev.rgb, colorShift * 0.12), vec3<f32>(0.0)), prev.a);
    
    // Calculate new effect alpha
    let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let newAlpha = luma * depthLayeredAlpha(fract(sampleUV), depthWeight);
    
    // Accumulate alpha over time
    let accumulated = accumulativeAlpha(
        finalColor,
        newAlpha,
        prev.rgb,
        prev.a,
        accumulationRate
    );
    
    // Apply feedback strength
    let finalResult = mix(accumulated, vec4<f32>(finalColor, newAlpha), feedbackStrength);

    textureStore(writeTexture, vec2<u32>(global_id.xy), vec4<f32>(aces(finalResult.rgb), clamp(finalResult.a, 0.0, 1.0)));
    
    // Store for feedback
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalResult);

    // Write depth
    let depth = 1.0 - clamp(length(newUV), 0.0, 1.0);
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
