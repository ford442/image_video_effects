// ═══════════════════════════════════════════════════════════════════
//  Adaptive Mosaic — Phase A Upgrade
//  Category: geometric
//  Features: mouse-driven, depth-aware, audio-reactive, temporal
//  Complexity: Medium
//  Created: 2026-05-23
//  By: Claude (Sonnet 4.6)
// ═══════════════════════════════════════════════════════════════════
//
//  Param1: tile_size        — base mosaic tile size
//  Param2: depth_blend      — depth shrinks tiles (near=fine, far=coarse)
//  Param3: bevel_width      — SDF bevel/grout between tiles
//  Param4: audio_sensitivity — bass → tile-size pulse

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
  zoom_params: vec4<f32>,  // x=TileSize, y=DepthBlend, z=BevelWidth, w=AudioSensitivity
  ripples: array<vec4<f32>, 50>,
};

fn hash2f(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(q) * 43758.5453);
}

// Voronoi — returns distance to nearest cell, and cell ID
fn voronoi(p: vec2<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    var minDist = 8.0;
    var cellId  = 0.0;
    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            let nb     = vec2<f32>(f32(dx), f32(dy));
            let jitter = hash22(i + nb);
            let pt     = nb + jitter - f;
            let d      = length(pt);
            if (d < minDist) { minDist = d; cellId = hash2f(i + nb); }
        }
    }
    return vec2<f32>(minDist, cellId);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let uv    = vec2<f32>(gid.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let tileSize  = mix(0.01, 0.12, u.zoom_params.x);
    let depthBlend = u.zoom_params.y;
    let bevelW     = u.zoom_params.z * 0.12 + 0.01;
    let audioSens  = u.zoom_params.w;

    // Audio
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass = select(0.0, plasmaBuffer[0].x, hasAudio) * audioSens;

    // Depth — near objects (depth→1) get finer tiles
    let depth      = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthScale = mix(1.0, 0.3, depth * depthBlend);
    let effective  = tileSize * depthScale * (1.0 + bass * 0.25);
    let safeSize   = max(effective, 0.005);

    // Mouse focus zone — cursor always shows finest detail
    let mouse       = u.zoom_config.yz;
    let mDist       = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let focusFactor = smoothstep(0.0, 0.35, mDist);
    let fs          = max(mix(safeSize * 0.2, safeSize, focusFactor), 0.004);

    // Aspect-correct UV so tiles are square on screen
    let aUV      = uv * vec2<f32>(aspect, 1.0);
    let tileCoord = aUV / fs;
    let tileId    = floor(tileCoord);
    let inCell    = fract(tileCoord);

    // Sample from tile center
    let centerScaled = (tileId + 0.5) * fs;
    let sampleUV     = clamp(centerScaled / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

    // SDF bevel — smoothly rounds the interior edge of each tile
    let dX       = min(inCell.x, 1.0 - inCell.x);
    let dY       = min(inCell.y, 1.0 - inCell.y);
    let edgeSDF  = min(dX, dY);
    let bevelPx  = bevelW / fs;
    let bevel    = smoothstep(0.0, bevelPx, edgeSDF);
    let lipLight = smoothstep(bevelPx, bevelPx * 2.5, edgeSDF) * 0.15;
    color = color * bevel + lipLight;

    // Voronoi edge overlay at coarse tile sizes adds organic crackle
    let voro     = voronoi(tileCoord * 0.5);
    let voroEdge = smoothstep(0.0, 0.1, voro.x);
    color = mix(color, color * voroEdge, u.zoom_params.x * 0.2);

    // Temporal persistence
    let prev  = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;
    let decay = 0.12 + bass * 0.05;
    color = mix(color, prev, decay);

    let luma  = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.5 + 0.5 + depth * 0.15, 0.0, 1.0);

    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(color, alpha));
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 1.0));
}
