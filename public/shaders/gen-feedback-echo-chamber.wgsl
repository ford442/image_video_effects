// ═══════════════════════════════════════════════════════════════════════════════
//  Gen Feedback Echo Chamber - Advanced Alpha with Accumulative
//  Category: feedback/temporal
//  Alpha Mode: Accumulative Alpha + Effect Intensity
//  Features: advanced-alpha, generative-feedback, temporal-echo
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

// Mode 3: Accumulative Alpha
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

// ═══ ADVANCED ALPHA FUNCTION ═══
fn calculateAdvancedAlpha(color: vec3<f32>, brightness: f32, intensity: f32, accumulationRate: f32) -> f32 {
    // Tunable parameters from zoom_params
    let echoCount = u.zoom_params.x;      // Echo Count
    let decayRate = u.zoom_params.y;      // Decay Rate
    let spacing = u.zoom_params.z;        // Echo Spacing
    let colorShift = u.zoom_params.w;     // Color Shift
    
    // Effect intensity alpha: brighter = more opaque
    let intensityAlpha = mix(0.3, 1.0, brightness * intensity);
    
    // Accumulation-driven alpha: more echoes = stronger alpha buildup
    let accumBoost = echoCount * 0.3 + decayRate * 0.4;
    
    // Temporal persistence: spacing affects how quickly alpha decays
    let persistence = 1.0 - spacing * 0.3;
    
    // Combine: base intensity + accumulation boost, modulated by persistence
    let alpha = intensityAlpha * (1.0 + accumBoost) * persistence;
    
    return clamp(alpha, 0.1, 1.0);
}

// Noise
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    
    // Parameters
    let accumulationRate = u.zoom_params.x;
    let echoScale = u.zoom_params.y * 0.05;
    let intensity = u.zoom_params.z;
    let colorShift = u.zoom_params.w;
    
    // Current frame
    let current = textureLoad(readTexture, coord, 0);
    
    // Previous accumulated frame
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Generative pattern
    let patternUV = uv * 10.0;
    let pattern = hash(floor(patternUV) + time * 0.1 * audioReactivity);
    
    // Echo displacement
    let echoUV = uv + vec2<f32>(
        sin(time * 0.5 * audioReactivity + uv.y * 5.0) * echoScale,
        cos(time * 0.3 * audioReactivity + uv.x * 5.0) * echoScale
    );
    
    // Sample echo
    let echo = textureSampleLevel(dataTextureC, u_sampler, fract(echoUV), 0.0);
    
    // Generative color
    let genColor = vec3<f32>(
        0.5 + 0.5 * sin(time + uv.x * 5.0 + pattern),
        0.5 + 0.5 * sin(time * 0.8 * audioReactivity + uv.y * 5.0 + pattern + 2.0),
        0.5 + 0.5 * sin(time * 0.6 * audioReactivity + (uv.x + uv.y) * 3.0 + pattern + 4.0)
    );
    
    // Blend
    let blended = mix(echo.rgb, genColor * intensity, 0.3);
    let finalColor = mix(blended, current.rgb, 0.2);
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let brightness = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let newAlpha = calculateAdvancedAlpha(finalColor, brightness, intensity, accumulationRate);
    
    let accumulated = accumulativeAlpha(
        finalColor,
        newAlpha,
        prev.rgb,
        prev.a,
        accumulationRate
    );
    
    textureStore(dataTextureA, coord, accumulated);
    textureStore(writeTexture, global_id.xy, accumulated);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
