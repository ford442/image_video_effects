// ═══════════════════════════════════════════════════════════════════
//  Glass Shatter Morph
//  Category: advanced-hybrid
//  Features: mouse-driven, voronoi-shards, morphological, chromatic-aberration
//  Complexity: Very High
//  Chunks From: glass-shatter, conv-morphological-erosion-dilation
//  Created: 2026-04-18
//  By: Agent CB-24 — Glass & Reflection Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Shattered glass with morphological edge processing on each shard.
//  Voronoi shards are physically displaced by mouse interaction,
//  while morphological erosion/dilation sculpts shard edges.
//  The gradient channel reveals crack propagation patterns.
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

struct VoronoiResult {
    dist: f32,
    id: vec2<f32>,
    center: vec2<f32>
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn voronoi(uv: vec2<f32>, scale: f32) -> VoronoiResult {
    var g = floor(uv * scale);
    let f = fract(uv * scale);

    var res = VoronoiResult(8.0, vec2<f32>(0.0), vec2<f32>(0.0));

    for(var y: i32 = -1; y <= 1; y = y + 1) {
        for(var x: i32 = -1; x <= 1; x = x + 1) {
            let lattice = vec2<f32>(f32(x), f32(y));
            var offset = hash22(g + lattice);
            var p = lattice + offset - f;
            let d = dot(p, p);

            if(d < res.dist) {
                res.dist = d;
                res.id = g + lattice;
                res.center = (g + lattice + offset) / scale;
            }
        }
    }

    res.dist = sqrt(res.dist);
    return res;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    var mousePos = u.zoom_config.yz;

    // Parameters
    let shardScale = u.zoom_params.x * 20.0 + 3.0;
    let displaceStr = u.zoom_params.y * 0.5;
    let morphBlend = u.zoom_params.z; // 0=erosion, 1=dilation
    let edgeWidth = u.zoom_params.w * 0.1;

    // Voronoi for shards
    let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
    let v = voronoi(aspectUV, shardScale);

    // Calculate vector from mouse to shard center
    let cellCenter = v.center;
    let mouseVec = cellCenter - vec2<f32>(mousePos.x * aspect, mousePos.y);
    var dist = length(mouseVec);

    // Repulsion force
    var offset = vec2<f32>(0.0);
    if (dist < 0.5 && dist > 0.001) {
        let force = (1.0 - smoothstep(0.0, 0.5, dist)) * displaceStr;
        offset = normalize(mouseVec) * force;
    }

    let randOffset = (hash22(v.id) - 0.5) * 0.02 * displaceStr;
    let finalUV = uv - offset - randOffset;

    // ═══ Morphological edge processing on shard boundaries ═══
    let pixelSize = 1.0 / resolution;
    let kernelRadius = i32(mix(1.0, 4.0, edgeWidth));
    let maxRadius = min(kernelRadius, 5);

    var minVal = vec3<f32>(999.0);
    var maxVal = vec3<f32>(-999.0);
    var minLuma = 999.0;
    var maxLuma = -999.0;

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let sampleOffset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let sample = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + sampleOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
            let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));

            minVal = min(minVal, sample);
            maxVal = max(maxVal, sample);
            minLuma = min(minLuma, luma);
            maxLuma = max(maxLuma, luma);
        }
    }

    let erosion = minVal;
    let dilation = maxVal;
    let morphGradient = (dilation - erosion);

    // Shard normal for fresnel
    let shardTilt = normalize(offset + randOffset + vec2<f32>(0.001));
    let normal = normalize(vec3<f32>(shardTilt * 2.0, 1.0));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let cos_theta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.04;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);

    // Glass properties
    let thickness = 0.05 + (1.0 - v.dist) * 0.1;
    let glassColor = vec3<f32>(0.92, 0.98, 0.95);
    let absorption = exp(-(1.0 - glassColor) * thickness * 2.0);
    let transmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;

    // Sample with chromatic aberration
    let aberration = edgeWidth * 0.5;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + vec2<f32>(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(finalUV - vec2<f32>(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    var color = vec4<f32>(r, g, b, transmission);

    // Apply glass tint
    color = vec4<f32>(color.rgb * glassColor, transmission);

    // Blend morphological result on shard edges
    let edgeProximity = smoothstep(0.0, 0.15, v.dist) * (1.0 - smoothstep(0.15, 0.35, v.dist));
    let morphRGB = mix(erosion, dilation, morphBlend);
    color = vec4<f32>(mix(color.rgb, morphRGB + morphGradient * 0.3, edgeProximity * 0.4), color.a);

    // Highlight edges with specular
    let lightDir = normalize(vec2<f32>(0.5, -0.5));
    let tilt = normalize(offset + randOffset + vec2<f32>(0.001));
    let light = dot(tilt, lightDir);
    color = color + max(light, 0.0) * 0.2;

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Depth pass-through
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
