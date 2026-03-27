// ═══════════════════════════════════════════════════════════════════════════════
//  Temporal Echo - Advanced Alpha with Accumulative Alpha
//  Category: feedback/temporal
//  Alpha Mode: Accumulative Alpha (Feedback)
//  Features: advanced-alpha, temporal-feedback, paint-accumulation
// ═══════════════════════════════════════════════════════════════════════════════

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
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    
    // Parameters
    let accumulationRate = u.zoom_params.x;     // How fast alpha accumulates
    let echoDecay = u.zoom_params.y;            // Echo decay rate
    let depthWeight = u.zoom_params.z;          // Depth influence
    let temporalOffset = u.zoom_params.w;       // Time offset for echo
    
    let current = textureLoad(readTexture, coord, 0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Calculate temporal echo offset
    let frame_idx = i32(time) % 60;
    let slice_y = i32(frame_idx);
    
    // Mouse-controlled history offset
    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let history_offset_factor = distance(uv, mouse_pos);
    
    let brightness = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));
    var history_offset = i32(brightness * 59.0 * (1.0 + history_offset_factor));
    
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
    
    // Sample from history
    let past_y = clamp(slice_y - history_offset, 0, 59);
    let past_uv = vec2<f32>(uv.x, (uv.y + f32(past_y) / f32(dim.y)) / 60.0);
    let past = textureSampleLevel(dataTextureC, vec2<i32>(i32(uv.x * f32(dim.x)), i32((uv.y + f32(past_y) / f32(dim.y)) * f32(dim.y))), 0);
    
    // Apply echo decay
    let decayedPast = vec4<f32>(
        past.rgb * (1.0 - echoDecay * 0.5),
        past.a * (1.0 - echoDecay * 0.2)
    );
    
    // ═══ ACCUMULATIVE ALPHA CALCULATION ═══
    // Calculate new effect alpha based on brightness
    let newAlpha = brightness * depthLayeredAlpha(uv, depthWeight);
    
    // Accumulate with previous frame
    let accumulated = accumulativeAlpha(
        current.rgb,
        newAlpha,
        decayedPast.rgb,
        decayedPast.a,
        accumulationRate
    );
    
    // Blend with feedback
    let finalResult = mix(accumulated, current, 0.05);
    
    textureStore(dataTextureA, coord, finalResult);
    textureStore(writeTexture, id, finalResult);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
