// ═══════════════════════════════════════════════════════════════════
//  Recursive Ancestral Terrains
//  Category: generative
//  Features: multi-generational, fractal-terrain, mouse-lineage, audio-mutation, evolutionary,
//            temporal-blending, chromatic-ridges, bass-highlights, upgraded-rgba
//  Complexity: High
//  Chunks From: layered FBM + parameter blending techniques
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
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}


fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn fbm(p: vec2<f32>, octaves: i32, seed: f32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum += amp * hash12(p * freq + seed);
        freq *= 2.03;
        amp *= 0.5;
    }
    return sum;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.3;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;

    let gen1 = smoothstep(0.0, 0.33, 1.0 - length(mouse - vec2<f32>(0.25, 0.5)));
    let gen2 = smoothstep(0.0, 0.33, 1.0 - length(mouse - vec2<f32>(0.5, 0.5)));
    let gen3 = smoothstep(0.0, 0.33, 1.0 - length(mouse - vec2<f32>(0.75, 0.5)));

    let mutation = 0.4 + mids * 0.9 + treble * 0.5;

    let t1 = fbm(uv * 3.0 + time * 0.2, 5, 0.0) * (0.8 + mutation * 0.4);
    let t2 = fbm(uv * 4.2 - time * 0.15, 4, 12.7) * (0.9 + mutation * 0.3);
    let t3 = fbm(uv * 5.5 + time * 0.25, 6, 47.2) * (0.7 + mutation * 0.6);

    let terrain = t1 * gen1 + t2 * gen2 + t3 * gen3;
    let blend = gen1 * gen2 + gen2 * gen3 + gen3 * gen1;
    let finalTerrain = terrain + blend * 0.3;

    let height = finalTerrain * 0.5 + 0.5;
    let col = mix(
        vec3<f32>(0.1, 0.2, 0.15),
        vec3<f32>(0.9, 0.85, 0.6),
        height
    );

    // Chromatic ridge highlights: bass adds warm R, treble adds cool B
    let ridge = smoothstep(0.55, 0.75, height);
    let ridgeR = ridge * bass * 0.4;
    let ridgeB = ridge * treble * 0.3;
    let chromaCol = col + vec3<f32>(ridgeR, ridge * mids * 0.2, ridgeB);

    let lineageColor = vec3<f32>(gen1, gen2 * 0.8, gen3);
    let finalCol = mix(chromaCol, chromaCol * lineageColor * 1.3, 0.4);

    // Temporal blending with previous frame for smooth generational transitions
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let temporalBlend = 0.15 + bass * 0.05;
    let blendedCol = mix(finalCol, prev, temporalBlend);

    let alpha = clamp(height * 0.85 + abs(finalTerrain - 0.5) * 0.6 + bass * 0.05, 0.2, 1.0);
    let a = clamp(alpha, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, applyGenerativePrimaryControls(vec4<f32>(blendedCol * a, a)));
    textureStore(dataTextureA, gid.xy, vec4<f32>(blendedCol, a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(height * 0.8, 0.0, 0.0, 0.0));
}
