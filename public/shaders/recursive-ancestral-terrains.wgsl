// ═══════════════════════════════════════════════════════════════════
//  Recursive Ancestral Terrains
//  Category: generative
//  Features: multi-generational, fractal-terrain, mouse-lineage, audio-mutation, evolutionary,
//            temporal-blending, chromatic-ridges, bass-highlights, upgraded-rgba, aces-tone-map,
//            ridged-crests, cosine-lineage-strata, bass-mutation-waves
//  Complexity: High
//  Chunks From: layered FBM + parameter blending techniques
//  Created: 2026-05-31
//  Upgraded: 2026-06-06
//  Algorithmist pass: 2026-07-22 — IQ cosine palette ancestry strata, ridged-fbm octave,
//                      spatial bass mutation waves, rewired slider semantics
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

const TAU: f32 = 6.28318530718;

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

// Ridged fBM: abs-folded noise gives sharp mountain crests.
// Used as a single extra octave layered under the existing fbm stack.
fn ridgedFbm(p: vec2<f32>, octaves: i32, seed: f32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        let n = hash12(p * freq + seed);
        let r = 1.0 - abs(2.0 * n - 1.0);
        sum += amp * r * r;
        freq *= 2.11;
        amp *= 0.5;
    }
    return sum;
}

// IQ cosine palette — keyed on lineage depth so ancestry reads as color strata.
fn cosinePalette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(TAU * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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

    // Slider params — each drives a real constant of this shader's algorithm:
    //  p1 Lineage Blend    -> weight of cross-generational trait mixing
    //  p2 Mutation Rate    -> gain on audio-driven (and bass-wave) mutation
    //  p3 Terrain Roughness-> amplitude of the ridged-fbm crest octave
    //  p4 Historical Depth -> temporal memory weight (previous-frame blend)
    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    // Three ancestral lineages selected by mouse position
    let gen1 = smoothstep(0.0, 0.33, 1.0 - length(mouse - vec2<f32>(0.25, 0.5)));
    let gen2 = smoothstep(0.0, 0.33, 1.0 - length(mouse - vec2<f32>(0.5, 0.5)));
    let gen3 = smoothstep(0.0, 0.33, 1.0 - length(mouse - vec2<f32>(0.75, 0.5)));

    // Bass mutation waves: a slow radial wave expanding from the mouse
    // (canvas center when the mouse is untouched) modulates mutation locally,
    // so beats ripple lineage change across the terrain.
    let waveOrigin = select(vec2<f32>(0.5, 0.5), mouse, length(mouse) > 0.001);
    let aspect = vec2<f32>(res.x / res.y, 1.0);
    let distToOrigin = length((uv - waveOrigin) * aspect);
    let wavePhase = distToOrigin * 9.0 - u.config.x * 1.7;
    let bassWave = (0.5 + 0.5 * sin(wavePhase)) * exp(-distToOrigin * 2.2);

    let mutationAudio = mids * 0.9 + treble * 0.5 + bass * bassWave * 1.6;
    let mutation = 0.4 + mutationAudio * mix(0.15, 1.35, p2);

    // Ridged crest octave, param-scaled by Terrain Roughness (dialed out at p3 = 0)
    let ridgeAmp = p3 * 0.55;

    let t1 = fbm(uv * 3.0 + time * 0.2, 5, 0.0) * (0.8 + mutation * 0.4)
           + ridgedFbm(uv * 6.0 + time * 0.20, 1, 3.1) * ridgeAmp;
    let t2 = fbm(uv * 4.2 - time * 0.15, 4, 12.7) * (0.9 + mutation * 0.3)
           + ridgedFbm(uv * 7.4 - time * 0.15, 1, 19.3) * ridgeAmp;
    let t3 = fbm(uv * 5.5 + time * 0.25, 6, 47.2) * (0.7 + mutation * 0.6)
           + ridgedFbm(uv * 9.1 + time * 0.25, 1, 41.7) * ridgeAmp;

    let terrain = t1 * gen1 + t2 * gen2 + t3 * gen3;

    // Lineage Blend slider: how strongly ancestral traits mix across generations
    let blend = gen1 * gen2 + gen2 * gen3 + gen3 * gen1;
    let blendWeight = 0.05 + p1 * 0.6;
    let finalTerrain = terrain + blend * blendWeight;

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

    // Ancestry strata: cosine-palette hue keyed on lineage depth, blended ~0.3
    // so the original grading stays dominant while generations read as color bands.
    let genSum = max(gen1 + gen2 + gen3, 0.001);
    let lineageDepth = (gen1 * 0.15 + gen2 * 0.55 + gen3 * 0.95) / genSum;
    let ancestryHue = cosinePalette(lineageDepth + u.config.x * 0.015 + p1 * 0.25);
    let strataCol = mix(chromaCol, ancestryHue * (0.35 + height * 0.85), 0.3);

    let lineageColor = vec3<f32>(gen1, gen2 * 0.8, gen3);
    let finalCol = mix(strataCol, strataCol * lineageColor * 1.3, 0.25 + p1 * 0.3);

    // Temporal blending with previous frame; Historical Depth scales how visible
    // the 'memory' of previous generations is.
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let temporalBlend = clamp(0.05 + p4 * 0.45 + bass * 0.05, 0.0, 0.9);
    let blendedCol = mix(finalCol, prev, temporalBlend);

    let alpha = clamp(height * 0.85 + abs(finalTerrain - 0.5) * 0.6 + bass * 0.05, 0.2, 1.0);
    let a = clamp(alpha, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(acesToneMap(blendedCol * a * 1.1), a));
    textureStore(dataTextureA, gid.xy, vec4<f32>(blendedCol, a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(height * 0.8, 0.0, 0.0, 0.0));
}
