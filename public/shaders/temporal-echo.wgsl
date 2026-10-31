// ═══════════════════════════════════════════════════════════════════════════════
//  Temporal Echo - Advanced Alpha with Accumulative Alpha
//  Category: feedback/temporal
//  Alpha Mode: Accumulative Alpha (Feedback)
//  Features: advanced-alpha, temporal-feedback, paint-accumulation, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-30
//  Ideas: user-controlled echo depth; bass-transient echo pinning; history-axis smear; shadow-first stick
//  A packing: accumulated linear RGBA (C is that accumulation); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    let c = max(x, vec3<f32>(0.0));
    return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 3: Accumulative Alpha (Feedback Systems)
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    // Old alpha fades slightly, new alpha adds on top
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.1) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    
    // Color blends based on alpha contribution
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    
    return vec4<f32>(color, totalAlpha);
}

// Mode 1: Depth-Layered Alpha for temporal fading
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.5, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let id = vec2<u32>(global_id.xy);
    let dim = textureDimensions(readTexture);
    let uv = vec2<f32>(f32(id.x), f32(id.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    // Fix: zoom_config.x duplicates config.x (time), it is not audio — see
    // docs/BINDING_CONTRACT.md. Real audio lives in plasmaBuffer[0].xyz.
    let bass = plasmaBuffer[0].x;
    let audioReactivity = 1.0 + bass * 0.3;

    // Idea 2: bass-transient echo pinning — a single-writer read/update of the
    // previous frame's bass in extraBuffer[133] (this shader's own buffer;
    // read-old-then-write-new-at-corner, same convention as the spring shaders)
    // lets us detect a rising bass edge and pin a fresh echo frame on the beat,
    // layered alongside the existing click-ripple pin.
    let hasBassState = arrayLength(&extraBuffer) > 133u;
    var prevBass = bass;
    if (hasBassState) { prevBass = extraBuffer[133]; }
    if (global_id.x == 0u && global_id.y == 0u && hasBassState) {
        extraBuffer[133] = bass;
    }
    let bassTransient = clamp((bass - prevBass) * 4.0, 0.0, 1.0);

    // Parameters
    let accumulationRate = u.zoom_params.x;     // How fast alpha accumulates
    let echoDecay = u.zoom_params.y;            // Echo decay rate
    let depthWeight = u.zoom_params.z;          // Depth influence
    let temporalOffset = u.zoom_params.w;       // Time offset for echo

    let current = textureLoad(readTexture, coord, 0);

    // Calculate temporal echo offset
    let frame_idx = i32(time) % 60;
    let slice_y = i32(frame_idx);

    // Mouse-controlled history offset
    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let history_offset_factor = distance(uv, mouse_pos);

    let brightness = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));
    // Idea 1: user-controlled echo depth — temporalOffset was read but never
    // used; it now adds an explicit frame-lag bias independent of brightness.
    var history_offset = i32(brightness * 59.0 * (1.0 + history_offset_factor) * audioReactivity)
        + i32(temporalOffset * 30.0);

    // Ripples pin frames into history
    for (var i = 0; i < 50; i++) {
        let ripple = u.ripples[i];
        if (ripple.z > 0.0) {
            let ripple_age = time - ripple.z;
            if (ripple_age > 0.0 && ripple_age < 5.0) {
                let dist_to_ripple = distance(uv, ripple.xy);
                if (dist_to_ripple < 0.1) {
                    history_offset = i32(ripple_age * 10.0);
                }
            }
        }
    }
    history_offset = i32(mix(f32(history_offset), 0.0, bassTransient));

    // Sample from history (coordinates clamped — an unclamped lookup here
    // could read outside dataTextureC's bounds)
    let past_y = clamp(slice_y - history_offset, 0, 59);
    let pastCoord = vec2<i32>(
        clamp(i32(uv.x * f32(dim.x)), 0, i32(dim.x) - 1),
        clamp(i32((uv.y + f32(past_y) / f32(dim.y)) * f32(dim.y)), 0, i32(dim.y) - 1)
    );
    let past = textureLoad(dataTextureC, pastCoord, 0);
    // ── Idea 1: history-axis smear ──────────────────────────────────
    // The echo already lives on a vertical slice of C. One extra row
    // along that slice turns the point sample into a short streak.
    // temporalOffset keeps its lag-bias role and also sets the mix.
    let past2Coord = vec2<i32>(pastCoord.x, clamp(pastCoord.y + 1, 0, i32(dim.y) - 1));
    let past2 = textureLoad(dataTextureC, past2Coord, 0);
    let smearedPast = mix(past, past2, temporalOffset * 0.65);

    // Apply echo decay
    let decayedPast = vec4<f32>(
        smearedPast.rgb * (1.0 - echoDecay * 0.5),
        smearedPast.a * (1.0 - echoDecay * 0.2)
    );
    
    // ═══ ACCUMULATIVE ALPHA CALCULATION ═══
    // Calculate new effect alpha based on brightness
    let newAlpha = brightness * depthLayeredAlpha(uv, depthWeight);
    // ── Idea 2: shadow-first stick ──────────────────────────────────
    // Dim pixels stop accumulating before bright ones. echoDecay still
    // fades the stored echo; it only tightens this knee.
    let stick = smoothstep(0.05, 0.22, brightness);
    let stuckAlpha = newAlpha * mix(1.0, mix(0.35, 1.0, stick), echoDecay);
    
    // Accumulate with previous frame
    let accumulated = accumulativeAlpha(
        current.rgb,
        stuckAlpha,
        decayedPast.rgb,
        decayedPast.a,
        accumulationRate
    );
    
    // Blend with feedback
    let finalResult = mix(accumulated, current, 0.05);
    
    textureStore(dataTextureA, coord, finalResult);
    textureStore(writeTexture, id, vec4<f32>(aces(finalResult.rgb), finalResult.a));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
