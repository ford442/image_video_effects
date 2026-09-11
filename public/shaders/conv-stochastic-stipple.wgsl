// ═══════════════════════════════════════════════════════════════════
//  Stochastic Stipple
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven, audio-reactive, depth-aware
//  Convolution Type: weighted-voronoi-stippling-convolution
//  Complexity: High
//  Upgraded: 2026-09-08
//  Ideas: paper ground under dots; gradient-stretched ellipses
//  A packing: ACES display RGBA
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn blueNoise(p: vec2<f32>) -> f32 {
    let h1 = hash12(p * 1.0);
    let h2 = hash12(p * 2.3 + vec2<f32>(5.7, 3.1));
    let h3 = hash12(p * 4.7 + vec2<f32>(1.3, 8.9));
    return fract(h1 * 0.5 + h2 * 0.3 + h3 * 0.2);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn localMean(uv: vec2<f32>, pixelSize: vec2<f32>, radius: i32) -> vec3<f32> {
    var sum = vec3<f32>(0.0);
    var count = 0.0;
    let r = min(radius, 4);
    for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            sum += textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
            count += 1.0;
        }
    }
    return sum / count;
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

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = 0.5 + depth * 0.5;

    let cellSizeBase = mix(0.02, 0.08, u.zoom_params.x);
    let threshold = mix(0.2, 0.8, u.zoom_params.y);
    let colorSaturation = mix(0.5, 2.0, u.zoom_params.z);
    let mouseInfluence = u.zoom_params.w;

    // Bass-driven dot density
    let cellSizeAudio = cellSizeBase * (1.0 - bass * 0.2);

    // Mouse creates higher resolution stipple zone
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * mouseInfluence;
    let cellSize = mix(cellSizeAudio, cellSizeAudio * 0.3, mouseFactor);

    // Ripple stipple displacement
    var rippleOffset = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.2) * 12.0, 2.0));
            let angle = atan2(uv.y - rPos.y, uv.x - rPos.x) + rElapsed * 4.0;
            rippleOffset += vec2<f32>(cos(angle), sin(angle)) * wave * (1.0 - rElapsed / 3.0) * cellSize * 2.0;
        }
    }

    let displacedUV = uv + rippleOffset;

    // Cell-based stippling
    let cellCoord = floor(displacedUV / cellSize);
    let cellUV = (displacedUV - cellCoord * cellSize) / cellSize;

    // Blue-noise dithered threshold
    let noise = blueNoise(cellCoord + vec2<f32>(time * 0.01));
    let ditheredThreshold = threshold + (noise - 0.5) * 0.3;

    // Local mean for cell color
    let meanColor = localMean(displacedUV, pixelSize, i32(cellSize * max(res.x, res.y) * 0.5));
    let meanLuma = dot(meanColor, vec3<f32>(0.299, 0.587, 0.114));

    // Stipple density based on luminance
    var density = smoothstep(ditheredThreshold - 0.1, ditheredThreshold + 0.1, meanLuma);
    // Bass-driven density boost
    density = clamp(density * (1.0 + bass * 0.3), 0.0, 1.0);

    // Depth-based stipple size
    let dotRadius = density * 0.45 * mix(1.2, 0.7, depth);
    let cellCenter = hash22(cellCoord) * 0.6 + 0.2;
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let gx = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(pixelSize.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let gy = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, pixelSize.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let gdir = vec2<f32>(gx - meanLuma, gy - meanLuma);
    let glen = max(length(gdir), 0.0001);
    let gN = gdir / glen;
    let delta = cellUV - cellCenter;
    let along = dot(delta, gN);
    let across = dot(delta, vec2<f32>(-gN.y, gN.x));
    let ellipse = length(vec2<f32>(along * 0.72, across * 1.28));
    let inDot = 1.0 - smoothstep(dotRadius * 0.7, dotRadius, ellipse);

    // Colorize
    let saturatedColor = meanColor * colorSaturation;
    let paper = vec3<f32>(0.93, 0.90, 0.84);
    var stippleColor = mix(paper * 0.98, saturatedColor, inDot);

    // Chromatic aberration on stipple dots
    let caStrength = 0.003 * (1.0 + bass) * cellSize;
    let caR = localMean(displacedUV + vec2<f32>(caStrength, 0.0), pixelSize, i32(cellSize * max(res.x, res.y) * 0.5)).r;
    let caB = localMean(displacedUV - vec2<f32>(caStrength, 0.0), pixelSize, i32(cellSize * max(res.x, res.y) * 0.5)).b;
    stippleColor.r = mix(stippleColor.r, mix(paper.r, caR * colorSaturation, inDot), 0.5 * (1.0 + treble));
    stippleColor.b = mix(stippleColor.b, mix(paper.b, caB * colorSaturation, inDot), 0.5 * (1.0 + treble));

    // Artistic edge variation
    let edgeNoise = hash12(cellCoord * 3.7 + vec2<f32>(time * 0.05));
    let edgeFactor = smoothstep(0.3, 0.7, edgeNoise);
    var finalColor = mix(stippleColor, meanColor * 1.2, edgeFactor * 0.2);

    // Temporal feedback: stipple morphing
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    finalColor = mix(finalColor, prev.rgb, 0.06 * (1.0 + mids));

    // ACES tone mapping
    finalColor = acesToneMap(finalColor * 1.1);

    // Depth boost
    finalColor *= depthFactor;

    // Semantic alpha: stipple density × dot coverage × depth
    let alpha = clamp(density * inDot * depthFactor + src.a * 0.15, 0.0, 1.0);
    let packed = vec4<f32>(finalColor, alpha);
    let pixel = vec2<i32>(global_id.xy);

    textureStore(writeTexture, pixel, packed);
    textureStore(dataTextureA, pixel, packed);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
