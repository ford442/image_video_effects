// ═══════════════════════════════════════════════════════════════════
//  spec-bicubic-crystal
//  Category: distortion
//  Features: bicubic, catmull-rom, crystalline, high-order-sampling
//  Complexity: High
//  Chunks From: chunk-library (hash12)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Bicubic Catmull-Rom Crystalline Distortion
//  Full bicubic Catmull-Rom interpolation for silky-smooth UV distortion.
//  Applied to a crystalline faceting distortion that creates glass-like
//  prismatic refractions without bilinear staircasing.
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

fn catmullRom(t: f32) -> vec4<f32> {
    let t2 = t * t;
    let t3 = t2 * t;
    return vec4<f32>(
        -0.5*t3 + t2 - 0.5*t,
        1.5*t3 - 2.5*t2 + 1.0,
        -1.5*t3 + 2.0*t2 + 0.5*t,
        0.5*t3 - 0.5*t2
    );
}

fn sampleBicubic(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>, texSize: vec2<f32>) -> vec4<f32> {
    let pixel = uv * texSize - 0.5;
    let f = fract(pixel);
    let base = floor(pixel);

    let wx = catmullRom(f.x);
    let wy = catmullRom(f.y);

    var result = vec4<f32>(0.0);
    for (var j = -1; j <= 2; j = j + 1) {
        for (var i = -1; i <= 2; i = i + 1) {
            let coord = (base + vec2<f32>(f32(i), f32(j)) + 0.5) / texSize;
            let s = textureSampleLevel(tex, samp, coord, 0.0);
            let weight = wx[i + 1] * wy[j + 1];
            result += s * weight;
        }
    }
    return result;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let crystalScale = mix(3.0, 20.0, u.zoom_params.x);
    let distortion = mix(0.0, 0.15, u.zoom_params.y);
    let facetSharp = mix(0.5, 4.0, u.zoom_params.z);
    let chromaSep = mix(0.0, 0.03, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Crystalline facet UV distortion
    let cellId = floor(uv * crystalScale);
    let cellLocal = fract(uv * crystalScale) - 0.5;

    // Each facet has a slightly different refraction direction
    let facetHash = hash12(cellId + vec2<f32>(37.0, 17.0));
    let facetAngle = facetHash * 6.28318;
    let facetOffset = vec2<f32>(cos(facetAngle), sin(facetAngle)) * distortion;

    // Facet boundary with anti-aliasing
    let distFromCenter = length(cellLocal);
    let facetEdge = 1.0 - smoothstep(0.35, 0.5, distFromCenter);

    // Mouse warps facet field
    var distortedUV = uv + facetOffset * facetEdge;
    if (isMouseDown) {
        let toMouse = mousePos - uv;
        let mouseDist = length(toMouse);
        let mouseInfluence = exp(-mouseDist * mouseDist * 300.0);
        distortedUV += toMouse * mouseInfluence * distortion * 2.0;
    }

    // Bicubic sampling with chromatic separation
    let texSize = res;
    let rSample = sampleBicubic(readTexture, u_sampler, distortedUV + vec2<f32>(chromaSep, 0.0), texSize).r;
    let gSample = sampleBicubic(readTexture, u_sampler, distortedUV, texSize).g;
    let bSample = sampleBicubic(readTexture, u_sampler, distortedUV - vec2<f32>(chromaSep, 0.0), texSize).b;

    var outColor = vec3<f32>(rSample, gSample, bSample);

    // Facet edge highlights
    let edgeGlow = pow(1.0 - distFromCenter * 2.0, facetSharp) * 0.3;
    outColor += vec3<f32>(edgeGlow * 0.5, edgeGlow * 0.6, edgeGlow * 0.8);

    // Subtle time-varying iridescence on edges
    let iridHue = time * 0.1 + facetHash * 3.0 + distFromCenter * 5.0;
    let iridColor = vec3<f32>(
        0.5 + 0.5 * cos(iridHue),
        0.5 + 0.5 * cos(iridHue + 2.09),
        0.5 + 0.5 * cos(iridHue + 4.18)
    );
    outColor += iridColor * edgeGlow * 0.2;

    textureStore(writeTexture, gid.xy, vec4<f32>(outColor, facetEdge));
    textureStore(dataTextureA, gid.xy, vec4<f32>(facetOffset, facetHash, facetEdge));
}
