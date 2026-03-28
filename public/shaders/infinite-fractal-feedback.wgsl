// ═══════════════════════════════════════════════════════════════════════════════
//  Infinite Fractal Feedback - Advanced Alpha with Accumulative Alpha
//  Category: feedback/temporal
//  Alpha Mode: Accumulative Alpha (Feedback)
//  Features: advanced-alpha, fractal-feedback, infinite-zoom
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
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.08) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    
    return vec4<f32>(color, totalAlpha);
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
    let uv_raw = vec2<f32>(global_id.xy);
    var uv = (uv_raw - resolution * 0.5) / min(resolution.x, resolution.y);
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    var mousePos = vec2<f32>(u.zoom_config.y / resolution.x, u.zoom_config.z / resolution.y);

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
    polar.y = polar.y + time * u.zoom_config.w * audioReactivity * 0.2 + polar.x * spiralTightness;

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

    // Mouse click creates shockwave distortion
    let timeSinceClick = time - u.zoom_config.x;
    if (timeSinceClick > 0.0 && timeSinceClick < 2.0) {
        let clickDist = length(uv - (mousePos - vec2<f32>(0.5, 0.5)) * 2.0);
        let shockwave = sin(clickDist * 20.0 - timeSinceClick * 10.0) * (1.0 - timeSinceClick * 0.5);
        finalColor = finalColor * (1.0 + shockwave * 0.5);
    }

    // Kaleidoscopic symmetry
    let angle = atan2(newUV.y, newUV.x);
    let segments = 6.0 + floor(sin(time * 0.5 * audioReactivity) * 3.0);
    let kaleidoAngle = floor(angle * segments / (2.0 * 3.14159)) * (2.0 * 3.14159) / segments;
    let symUV = vec2<f32>(cos(kaleidoAngle), sin(kaleidoAngle)) * length(newUV);
    let symColor = textureSampleLevel(readTexture, u_sampler, symUV * 0.5 + 0.5, 0.0).rgb;

    finalColor = mix(finalColor, symColor, 0.6);
    
    // ═══ ACCUMULATIVE ALPHA CALCULATION ═══
    // Sample previous frame
    let prev = textureSampleLevel(dataTextureC, u_sampler, fract(sampleUV), 0.0);
    
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

    textureStore(writeTexture, vec2<u32>(global_id.xy), finalResult);
    
    // Store for feedback
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalResult);

    // Write depth
    let depth = 1.0 - clamp(length(newUV), 0.0, 1.0);
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
