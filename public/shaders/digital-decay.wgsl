// ═══════════════════════════════════════════════════════════════════
//  Digital Decay — Phase A Upgrade
//  Category: retro-glitch
//  Features: audio-reactive, depth-aware, temporal
//  Complexity: Medium
//  Chunks From: original digital-decay.wgsl
//  Created: 2026-05-23
//  By: Claude (Sonnet 4.6)
// ═══════════════════════════════════════════════════════════════════
//
//  Param1: corruption_rate  — probability of block/pixel corruption
//  Param2: block_size       — corruption block size (small→large)
//  Param3: ghost_decay      — ghost frame persistence (dataTextureA)
//  Param4: depth_influence  — near objects degrade faster

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=CorruptionRate, y=BlockSize, z=GhostDecay, w=DepthInfluence
  ripples: array<vec4<f32>, 50>,
};

fn hash11(p: f32) -> f32 {
    var v = fract(p * 0.1031);
    v = fract(v + dot(vec2<f32>(v,v), vec2<f32>(v,v)+33.33));
    return fract(v*v*43758.5453);
}
fn hash21(p: vec2<f32>) -> f32 {
    var v = fract(vec3<f32>(p.x,p.y,p.x)*0.1031);
    v = fract(v+dot(v,v.yzx+33.33));
    return fract((v.x+v.y)*v.z);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    let n = sin(vec2<f32>(dot(p,vec2<f32>(127.1,311.7)), dot(p,vec2<f32>(269.5,183.3))));
    return fract(n*43758.5453);
}

// Simulate 1-bit flip in 8-bit channel
fn bitFlip(v: f32, seed: f32) -> f32 {
    let quantized = floor(v * 255.0);
    let bitPos    = floor(hash11(seed) * 8.0);
    let flipMask  = exp2(bitPos);
    let flipped   = fract((quantized + flipMask) / 256.0) * (256.0 / 255.0);
    return clamp(flipped, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let uv   = vec2<f32>(f32(gid.x)/resolution.x, f32(gid.y)/resolution.y);
    let time = u.config.x;

    // Params
    let corruptionRate = u.zoom_params.x;
    let rawBlock       = u.zoom_params.y;
    let ghostDecay     = 0.7 + u.zoom_params.z * 0.28;
    let depthInfluence = u.zoom_params.w;

    // Audio — bass spikes trigger corruption bursts
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass = select(0.0, plasmaBuffer[0].x, hasAudio);
    let effectiveCorruption = clamp(corruptionRate + bass * 0.35, 0.0, 1.0);

    // Depth — near objects corrupt more
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthCorrupt = effectiveCorruption * (1.0 + depth * depthInfluence);

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Block grid — variable size (4 / 8 / 16 px based on rawBlock)
    let blockPx   = floor(mix(4.0, 64.0, rawBlock));
    let blockUV   = vec2<i32>(i32(floor(uv.x*resolution.x/blockPx)), i32(floor(uv.y*resolution.y/blockPx)));
    let blockId   = f32(blockUV.x*73856093 ^ blockUV.y*19349663);
    let blockTime = floor(time * (2.0 + bass * 3.0) * hash11(blockId+1.0));
    let blockHash = hash21(vec2<f32>(f32(blockUV.x), f32(blockUV.y)) + blockTime);

    var glitchUV = uv;

    // Block-level displacement
    if (blockHash < depthCorrupt * 0.55) {
        let disp = (hash22(vec2<f32>(f32(blockUV.x), f32(blockUV.y))*99.0 + blockTime) - 0.5) * 0.35;
        glitchUV += disp;
    }

    // Sub-pixel jitter on corrupted blocks
    let pixHash = hash21(uv*500.0 + time*3.0);
    if (blockHash < depthCorrupt * 0.25) {
        glitchUV += (vec2<f32>(pixHash, hash21(uv*600.0)) - 0.5) / resolution * 18.0;
    }
    glitchUV = clamp(glitchUV, vec2<f32>(0.0), vec2<f32>(1.0));

    // Chromatic aberration — magnitude scales with corruption
    let aberrStr = depthCorrupt * 0.012 * select(1.0, 3.0, blockHash < depthCorrupt * 0.4);
    let aberr = (hash22(uv + time*0.07) - 0.5) * aberrStr;
    let r = textureSampleLevel(readTexture, u_sampler, glitchUV + aberr,       0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, glitchUV,               0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, glitchUV - aberr,       0.0).b;
    var outCol = vec3<f32>(r, g, b);

    // Bit-flip corruption on individual channels
    if (blockHash < depthCorrupt * 0.15) {
        outCol.r = bitFlip(outCol.r, blockId + time * 7.3);
        outCol.g = bitFlip(outCol.g, blockId + time * 5.1);
        outCol.b = bitFlip(outCol.b, blockId + time * 3.7);
    }

    // Scanline noise
    let scanline = sin(uv.y*resolution.y*1.5 + time*2.0) * 0.05 * depthCorrupt;
    outCol -= scanline;
    let noise = (hash11(dot(uv, vec2<f32>(12.9898,78.233)) + time) - 0.5) * 0.12 * depthCorrupt;
    outCol += noise;

    // Ghost frame persistence — blend current corruption with previous frame
    let ghost = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;
    let ghostBlend = clamp(depthCorrupt * 0.6, 0.0, 0.8);
    outCol = mix(outCol, ghost * ghostDecay, ghostBlend);

    outCol = clamp(outCol, vec3<f32>(0.0), vec3<f32>(1.0));
    if (corruptionRate < 0.01) { outCol = src.rgb; }

    // Persist to dataTextureA for next frame
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(outCol, 1.0));
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(outCol, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 1.0));
}
