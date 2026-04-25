// ═══════════════════════════════════════════════════════════════════
//  Stochastic Stipple
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven
//  Convolution Type: weighted-voronoi-stippling-convolution
//  Complexity: High
//  Created: 2026-04-18
//  By: Agent 1C — RGBA Convolution Architect
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Stipple color (sampled from local mean)
//    Alpha: Stipple density — continuous float representing how "full" each
//           stipple cell is. Downstream shaders can use this to create varying
//           dot sizes in vector-graphic style.
//
//  Uses blue-noise dithering + local averaging to create stipple/pointillist
//  art from any image. Each "dot" represents a local neighborhood.
//
//  MOUSE INTERACTIVITY:
//    Mouse creates a zone of higher stipple resolution (smaller cells,
//    more dots). Far from mouse = larger, more abstract stipple regions.
//    Ripples inject transient stipple displacement waves.
//
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

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
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
    // Approximate blue noise via layered hash
    let h1 = hash12(p * 1.0);
    let h2 = hash12(p * 2.3 + vec2<f32>(5.7, 3.1));
    let h3 = hash12(p * 4.7 + vec2<f32>(1.3, 8.9));
    return fract(h1 * 0.5 + h2 * 0.3 + h3 * 0.2);
}

fn localMean(uv: vec2<f32>, pixelSize: vec2<f32>, radius: i32) -> vec3<f32> {
    var sum = vec3<f32>(0.0);
    var count = 0.0;
    let r = min(radius, 4);
    for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            sum += textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
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
    
    // Parameters
    let cellSizeBase = mix(0.02, 0.08, u.zoom_params.x);
    let threshold = mix(0.2, 0.8, u.zoom_params.y);
    let colorSaturation = mix(0.5, 2.0, u.zoom_params.z);
    let mouseInfluence = u.zoom_params.w;
    
    // Mouse creates higher resolution stipple zone
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * mouseInfluence;
    let cellSize = mix(cellSizeBase, cellSizeBase * 0.3, mouseFactor);
    
    // Ripple stipple displacement
    var rippleOffset = vec2<f32>(0.0);
    let rippleCount = u32(u.config.y);
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
    let density = smoothstep(ditheredThreshold - 0.1, ditheredThreshold + 0.1, meanLuma);
    
    // Vary dot size within cell based on density
    let cellCenter = hash22(cellCoord) * 0.6 + 0.2;
    let distToCenter = length(cellUV - cellCenter);
    let dotRadius = density * 0.45;
    let inDot = 1.0 - smoothstep(dotRadius * 0.7, dotRadius, distToCenter);
    
    // Colorize
    let saturatedColor = meanColor * colorSaturation;
    let stippleColor = saturatedColor * inDot + meanColor * 0.1 * (1.0 - inDot);
    
    // Add artistic edge variation
    let edgeNoise = hash12(cellCoord * 3.7 + vec2<f32>(time * 0.05));
    let edgeFactor = smoothstep(0.3, 0.7, edgeNoise);
    let finalColor = mix(stippleColor, meanColor * 1.2, edgeFactor * 0.2);
    
    // Store: RGB = stipple color, Alpha = stipple density
    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, density));
    
    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
