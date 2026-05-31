// ═══════════════════════════════════════════════════════════════════
//  Pixelation Drift
//  Category: image
//  Features: audio-reactive, temporal-persistence, chromatic-pixel-separation,
//            depth-aware, organic-motion, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-31
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

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, vec3<f32>(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Audio-reactive pixel size
    let basePixelSize = max(u.zoom_params.x, 0.01) * 100.0 * (1.0 + bass * 0.3);
    let driftSpeed = u.zoom_params.y * (1.0 + mids * 0.2);
    let colorBleed = u.zoom_params.z;
    let depthInfluence = u.zoom_params.w;

    let depthFactor = mix(1.0, 1.0 - depth * 0.7, depthInfluence);
    let pixelSize = basePixelSize * depthFactor;

    // Organic drift with audio
    let driftScale = 5.0;
    let driftOffset = vec2<f32>(
        noise(uv * driftScale + vec2<f32>(time * driftSpeed * 0.2, 0.0)),
        noise(uv * driftScale + vec2<f32>(0.0, time * driftSpeed * 0.2))
    ) * 2.0 - 1.0;

    let driftedUV = uv + driftOffset * 0.02 * driftSpeed;
    let pixelatedUV = floor(driftedUV * resolution / pixelSize) * pixelSize / resolution;

    // Chromatic pixel separation: RGB sample at different pixel offsets
    let chromaShift = pixelSize / resolution * treble * 0.5;
    let rUV = pixelatedUV + vec2<f32>(chromaShift, 0.0);
    let gUV = pixelatedUV;
    let bUV = pixelatedUV - vec2<f32>(chromaShift, 0.0);

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    var color = vec3<f32>(r, g, b);
    var baseAlpha = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).a;

    // Color bleeding with audio
    if (colorBleed > 0.01) {
        let bleedOffset = vec2<f32>(
            sin(time * 0.5 + uv.y * 10.0 + bass * 3.14),
            cos(time * 0.5 + uv.x * 10.0 + mids * 3.14)
        ) * pixelSize / resolution * colorBleed * 2.0;
        let bleedColor = textureSampleLevel(readTexture, u_sampler, pixelatedUV + bleedOffset, 0.0);
        color = mix(color, bleedColor.rgb, colorBleed * 0.3);
        baseAlpha = mix(baseAlpha, bleedColor.a, colorBleed * 0.3);
    }

    // Edge glow
    let pixelCenter = (floor(driftedUV * resolution / pixelSize) + 0.5) * pixelSize / resolution;
    let distToCenter = length((driftedUV - pixelCenter) * resolution);
    let edgeGlow = smoothstep(pixelSize * 0.4, pixelSize * 0.5, distToCenter);
    color = mix(color, color * 1.2, edgeGlow * 0.1);

    // Temporal persistence for smoother transitions
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let persistence = 0.85 + bass * 0.05;
    let blended = mix(vec4<f32>(color, baseAlpha), prev, persistence);
    textureStore(dataTextureA, gid.xy, blended);

    // Semantic alpha based on pixel edge and audio
    let alpha = clamp(baseAlpha * (1.0 - edgeGlow * 0.2) + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(blended.rgb, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
