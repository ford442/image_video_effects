// ═══════════════════════════════════════════════════════════════════
//  Bilateral Grid Splat
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven, audio-reactive, depth-aware, temporal
//  Convolution Type: bilateral-grid-fast-approximate
//  Complexity: High
//  Created: 2026-04-18
//  By: Agent 1C — RGBA Convolution Architect
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Accumulated splatted color (can exceed 1.0 in grid cells with
//         many contributions — HDR accumulation)
//    Alpha: Edge-preservation confidence — higher where depth/intensity
//         discontinuities are strong, indicating less smoothing occurred.
//
//  Why it matters: The bilateral grid requires floating-point accumulation
//  in 3D bins. With rgba32float, each bin stores exact contributions without
//  quantization — enabling arbitrarily large kernel radii without penalty.
//
//  MOUSE INTERACTIVITY:
//    Mouse position creates a "detail zone" where the grid resolution is
//    effectively higher (smaller intensity bins), preserving sharp detail
//    near the cursor while smoothing elsewhere.
//    Ripples create transient grid distortions.
//
//  UPGRADES: ACES tone mapping, chromatic aberration on depth discontinuities,
//    plasmaBuffer bass-driven spatial sigma, dataTextureC temporal splat
//    accumulation, depth-aware range sigma, semantic alpha.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let pixel = vec2<i32>(global_id.xy);

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Depth sample
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = smoothstep(0.0, 1.0, depth);

    // Parameters
    let spatialSigma = mix(3.0, 12.0, u.zoom_params.x) * (1.0 + bass * 0.5);
    let intensitySigma = mix(0.05, 0.3, u.zoom_params.y) * (1.0 + depthFactor * 0.5);
    let gridQuant = mix(8.0, 32.0, u.zoom_params.z);
    let mouseInfluence = u.zoom_params.w;

    // Mouse detail zone
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 6.0) * mouseInfluence;
    let effectiveSpatialSigma = mix(spatialSigma, spatialSigma * 0.3, mouseFactor);
    let effectiveIntensitySigma = mix(intensitySigma, intensitySigma * 0.3, mouseFactor);

    // Ripple grid distortions
    var rippleDistort = vec2<f32>(0.0);
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 2.5) {
            let rDist = length(uv - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.25) * 8.0, 2.0));
            let angle = atan2(uv.y - rPos.y, uv.x - rPos.x);
            rippleDistort += vec2<f32>(cos(angle + rElapsed * 4.0), sin(angle + rElapsed * 4.0)) * wave * (1.0 - rElapsed / 2.5);
        }
    }

    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let centerLuma = dot(center.rgb, vec3<f32>(0.299, 0.587, 0.114));

    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    var depthDiscontinuity = 0.0;

    let radius = i32(ceil(effectiveSpatialSigma));
    let maxRadius = min(radius, 8);

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize + rippleDistort * pixelSize * 10.0;
            let sample = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0);
            let sampleLuma = dot(sample.rgb, vec3<f32>(0.299, 0.587, 0.114));

            // Spatial Gaussian
            let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
            let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * effectiveSpatialSigma * effectiveSpatialSigma + 0.001));

            // Intensity Gaussian (bilateral term)
            let intensityDist = abs(sampleLuma - centerLuma);
            let intensityWeight = exp(-intensityDist * intensityDist / (2.0 * effectiveIntensitySigma * effectiveIntensitySigma + 0.001));

            // Grid quantization
            let gridBin = floor(sampleLuma * gridQuant) / gridQuant;
            let binCenter = (gridBin + 0.5 / gridQuant);
            let binDist = abs(sampleLuma - binCenter);
            let binWeight = exp(-binDist * binDist * gridQuant * gridQuant * 2.0);

            let weight = spatialWeight * intensityWeight * binWeight;
            accumColor += sample.rgb * weight;
            accumWeight += weight;

            // Depth discontinuity accumulator for chromatic aberration
            let neighborDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset, 0.0).r;
            depthDiscontinuity += abs(neighborDepth - depth);
        }
    }

    var result = center.rgb;
    if (accumWeight > 0.001) {
        result = accumColor / accumWeight;
    }

    // Psychedelic enhancement
    let binHue = floor(centerLuma * gridQuant) / gridQuant;
    let colorShift = vec3<f32>(
        sin(binHue * 6.28318 + 0.0) * 0.5 + 0.5,
        sin(binHue * 6.28318 + 2.094) * 0.5 + 0.5,
        sin(binHue * 6.28318 + 4.189) * 0.5 + 0.5
    );
    result = mix(result, result * colorShift * 1.5, mouseFactor * 0.5);

    // Chromatic aberration on depth discontinuities
    let caStrength = depthDiscontinuity * 0.003 + treble * 0.004;
    let caDir = normalize(uv - vec2<f32>(0.5) + 0.001);
    let rUV = uv + caDir * caStrength;
    let bUV = uv - caDir * caStrength;
    let rSample = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let chromatic = vec3<f32>(rSample, result.g, bSample);
    result = mix(result, chromatic, clamp(caStrength * 20.0, 0.0, 0.5));

    // Temporal splat accumulation
    let prevFrame = textureLoad(dataTextureC, pixel, 0);
    let temporalDecay = mix(0.55, 0.85, depthFactor);
    result = mix(result, prevFrame.rgb, temporalDecay * 0.1);

    // ACES tone mapping
    result = acesToneMap(result * (1.0 + mids * 0.2));

    // Semantic alpha: edge-preservation confidence
    let edgeConfidence = clamp(depthDiscontinuity * 2.0 + (1.0 - accumWeight / f32((maxRadius * 2 + 1) * (maxRadius * 2 + 1))), 0.0, 1.0);
    let semanticAlpha = mix(edgeConfidence, 0.25, depthFactor * 0.4);

    textureStore(writeTexture, global_id.xy, vec4<f32>(result, semanticAlpha));

    // Depth pass-through
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
