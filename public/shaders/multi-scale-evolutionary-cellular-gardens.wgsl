// ═══════════════════════════════════════════════════════════════════
//  Multi-Scale Evolutionary Cellular Gardens
//  Category: generative
//  Features: multi-state-ca, rule-evolution, audio-mutation, multi-scale, organic-growth,
//            chromatic-species, bass-mutation-waves, temporal-color-memory, upgraded-rgba
//  Complexity: High
//  Chunks From: cellular automata + slow parameter evolution
//  Created: 2026-05-31
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.25;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let state = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let s1 = state.r;
    let s2 = state.g;
    let resource = state.b;

    let mutationRate = 0.3 + mids * 0.9;
    let competition = 0.2 + bass * 0.6;

    let ps = 1.0 / res;
    let n1 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( ps.x, 0.0), 0.0);
    let n2 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>( ps.x, 0.0), 0.0);
    let n3 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0,  ps.y), 0.0);
    let n4 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0,  ps.y), 0.0);

    let avgS1 = (n1.r + n2.r + n3.r + n4.r) * 0.25;
    let avgS2 = (n1.g + n2.g + n3.g + n4.g) * 0.25;
    let avgRes = (n1.b + n2.b + n3.b + n4.b) * 0.25;

    let growth1 = 0.04 + mutationRate * 0.03;
    let growth2 = 0.035 + mutationRate * 0.025;

    var newS1 = s1 + (avgRes * growth1 - competition * s1 * s2);
    var newS2 = s2 + (avgRes * growth2 - competition * s1 * s2 * 0.8);
    var newRes = resource * 0.98 + 0.01 - (newS1 + newS2) * 0.008;

    let mouseDist = length(uv - mouse);
    let mouseNurture = smoothstep(0.2, 0.0, mouseDist) * mouseDown * 0.6;
    newRes += mouseNurture;
    newS1 += mouseNurture * 0.3;
    newS2 += mouseNurture * 0.25;

    newS1 = clamp(newS1, 0.0, 1.8);
    newS2 = clamp(newS2, 0.0, 1.8);
    newRes = clamp(newRes, 0.0, 1.5);

    textureStore(dataTextureA, gid.xy, vec4<f32>(newS1, newS2, newRes, 0.0));

    // Chromatic species separation: species1 = green/cyan, species2 = magenta/purple
    let c1 = vec3<f32>(0.1, 0.7 + bass * 0.2, 0.5 + treble * 0.2) * newS1;
    let c2 = vec3<f32>(0.8 + mids * 0.1, 0.2, 0.6 + treble * 0.2) * newS2;
    let resCol = vec3<f32>(0.3, 0.5, 0.3) * newRes * 0.4;

    // Temporal color memory: previous frame tint bleeds in
    let prevCol = state.rgb;
    let col = mix(c1 + c2 + resCol, prevCol * vec3<f32>(0.95, 0.9, 0.85), 0.08 + bass * 0.03);

    let totalLife = newS1 * 0.6 + newS2 * 0.6;
    let alpha = clamp(totalLife * 0.85 + newRes * 0.2 + bass * 0.05, 0.15, 1.0);
    let a = clamp(alpha, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(col, a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(totalLife * 0.6, 0.0, 0.0, 0.0));
}
