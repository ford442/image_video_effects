// ═══════════════════════════════════════════════════════════════════
//  Infinite Video Feedback
//  Category: interactive-mouse
//  Features: mouse-driven, temporal-persistence, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-23
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=AccumulationRate, y=RecursionDepth, z=DepthWeight, w=ColorShift
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 3: Accumulative Alpha
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.05) + newAlpha * accumulationRate;
    let totalAlpha = clamp(accumulatedAlpha, 0.0, 1.0);
    let validAlpha = step(0.001, totalAlpha);
    let blendFactor = clamp(newAlpha * accumulationRate / max(totalAlpha, 0.001), 0.0, 1.0) * validAlpha;
    let color = mix(prevColor, newColor, blendFactor);
    return vec4<f32>(color, totalAlpha);
}

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(depth: f32, depthWeight: f32) -> f32 {
    let depthAlpha = mix(0.5, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let accumulationRate = u.zoom_params.x;
    let feedbackRetention = sqrt(clamp(u.zoom_params.x, 0.0, 1.0)); // default 0.9 ≈ legacy 0.95
    let recursionDepth = u.zoom_params.y * 0.02 * (1.0 + bass * 0.3 + mids * 0.3);
    let rotation = (u.zoom_params.z - 0.5) * 0.16;
    let depthWeight = 0.5; // preserve the old default while z earns its Rotation label
    let colorShift = u.zoom_params.w + treble * 0.2;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // The advertised mouse-centered recursion now exists: a critically
    // damped center follows normalized mouse coordinates every frame.
    let rawMouse = u.zoom_config.yz;
    var feedbackCenter = vec2<f32>(extraBuffer[133u], extraBuffer[134u]);
    var feedbackVelocity = vec2<f32>(extraBuffer[135u], extraBuffer[136u]);
    let feedbackInitialized = extraBuffer[137u] >= 0.5;
    if (!feedbackInitialized) {
        feedbackCenter = rawMouse;
        feedbackVelocity = vec2<f32>(0.0);
    }
    let springDt = select(0.0, clamp(time - extraBuffer[138u], 0.0005, 0.05), feedbackInitialized);
    let springOmega = 8.0;
    let feedbackAccel = springOmega * springOmega * (rawMouse - feedbackCenter)
        - 2.0 * springOmega * feedbackVelocity;
    feedbackVelocity += feedbackAccel * springDt;
    feedbackCenter = clamp(feedbackCenter + feedbackVelocity * springDt, vec2<f32>(-0.2), vec2<f32>(1.2));
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133u] = feedbackCenter.x;
        extraBuffer[134u] = feedbackCenter.y;
        extraBuffer[135u] = feedbackVelocity.x;
        extraBuffer[136u] = feedbackVelocity.y;
        extraBuffer[137u] = 1.0;
        extraBuffer[138u] = time;
    }

    let aspect = resolution.x / max(resolution.y, 1.0);
    let centeredAspect = (uv - feedbackCenter) * vec2<f32>(aspect, 1.0);
    let sectorAngle = atan2(centeredAspect.y, centeredAspect.x);
    let sector = u32(clamp(floor((sectorAngle + PI) * 8.0 / TAU), 0.0, 7.0));
    let sectorVoice = plasmaBuffer[(sector % 8u) + 1u].x;

    // Clicks kick localized portal rotation/zoom without mutating the raw
    // feedback packing. Alternating click indices counter-rotate.
    var clickSpin = 0.0;
    var clickZoom = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let clickDistance = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            let localMask = smoothstep(0.45, 0.0, clickDistance) * exp(-age * 1.6);
            let directionSign = select(-1.0, 1.0, (ri % 2u) == 0u);
            clickSpin += directionSign * localMask * 0.12;
            clickZoom += localMask * 0.012;
        }
    }

    let current = textureLoad(readTexture, coord, 0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Infinite recursion effect
    var accumulatedColor = vec3<f32>(0.0);
    var totalWeight = 0.0;
    
    for (var i: i32 = 0; i < 5; i++) {
        let fi = f32(i);
        let scale = max(1.0 - fi * (recursionDepth + clickZoom), 0.2);
        let layerAngle = (rotation + clickSpin) * (fi + 1.0)
            * select(1.0, 1.35, u.zoom_config.w > 0.5);
        let cs = cos(layerAngle);
        let sn = sin(layerAngle);
        let relative = (uv - feedbackCenter) * vec2<f32>(aspect, 1.0);
        let rotatedAspect = vec2<f32>(relative.x * cs - relative.y * sn, relative.x * sn + relative.y * cs);
        let recursiveUV = (rotatedAspect / vec2<f32>(aspect, 1.0)) / scale + feedbackCenter;
        
        if (recursiveUV.x >= 0.0 && recursiveUV.x <= 1.0 && recursiveUV.y >= 0.0 && recursiveUV.y <= 1.0) {
            let recursiveSample = textureSampleLevel(dataTextureC, u_sampler, recursiveUV, 0.0);
            let weight = pow(0.7, fi) * (1.0 + sectorVoice * 0.2);
            let hueShift = vec3<f32>(
                recursiveSample.r * (1.0 + colorShift * sin(fi)),
                recursiveSample.g,
                recursiveSample.b * (1.0 + colorShift * cos(fi))
            );
            accumulatedColor += hueShift * weight;
            totalWeight += weight;
        }
    }
    
    let finalColor = accumulatedColor / max(totalWeight, 0.001);
    let newAlpha = clamp(depthLayeredAlpha(depth, depthWeight) * length(finalColor), 0.0, 1.0);
    
    let accumulated = accumulativeAlpha(
        finalColor,
        newAlpha,
        prev.rgb,
        prev.a,
        accumulationRate
    );
    
    let rgbResult = mix(current.rgb, accumulated.rgb, feedbackRetention);
    let finalAlpha = mix(current.a, 1.0, accumulationRate * 0.7);
    let result = vec4<f32>(clamp(rgbResult, vec3<f32>(0.0), vec3<f32>(2.0)), finalAlpha);
    
    textureStore(dataTextureA, coord, result);
    textureStore(writeTexture, global_id.xy, result);
    
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0, 0, 0.0));
}
