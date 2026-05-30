// ═══════════════════════════════════════════════════════════════════
//  Coral Reef Colony
//  Category: generative
//  Features: coral, organic, generative, audio-reactive, semantic-alpha, simulation-like
//  Complexity: Medium-High
//  Created: 2026-05-30
//  Updated: 2026-06-01
//  By: Kimi Agent (integrated + upgraded)
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
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1,0)), u.x),
               mix(hash21(i + vec2<f32>(0,1)), hash21(i + vec2<f32>(1,1)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let growth = u.zoom_params.x * (0.7 + bass * 0.6);
    let polypSize = u.zoom_params.y;
    let colorVariety = u.zoom_params.z;
    let mouseAttraction = u.zoom_params.w;

    let mouse = u.zoom_config.yz;

    // Organic growth field
    let n1 = valueNoise(uv * 7.0 + time * 0.04);
    let n2 = valueNoise(uv * 14.0 - time * 0.03 + vec2<f32>(n1));
    let growthField = smoothstep(0.3, 0.75, n1 * 0.6 + n2 * 0.4) * growth;

    // Polyp structure
    let distToCenter = length(fract(uv * 22.0) - 0.5);
    let polyp = smoothstep(polypSize * 0.6, polypSize * 0.12, distToCenter);

    let mousePull = (1.0 - smoothstep(0.0, 0.6, length(uv - mouse))) * mouseAttraction * 0.8;
    let structure = polyp * (growthField + mousePull);

    // Coral coloring
    let hue = fract(uv.x * 0.4 + uv.y * 0.3 + time * 0.02 + colorVariety * 0.5 + mids * 0.15);
    let coral = vec3<f32>(
        0.6 + 0.4 * sin(hue * 6.28),
        0.3 + 0.5 * sin(hue * 6.28 + 2.0),
        0.4 + 0.6 * sin(hue * 6.28 + 4.0)
    );

    var color = coral * structure * (0.8 + treble * 0.5);

    // Subtle background water tint
    color = mix(color, vec3<f32>(0.05, 0.12, 0.18), 0.35 * (1.0 - structure));

    // Semantic alpha
    let semantic_alpha = clamp(0.48 + structure * 0.7, 0.35, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, semantic_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(structure * 0.65, 0.0, 0.0, 0.0));
}