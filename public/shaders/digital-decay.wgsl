// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,      // x=time, y=frame, z=resX, w=resY
  zoom_params: vec4<f32>, // x=decay_intensity, y=blockSize, z=corruptionSpeed, w=depthFocus
  zoom_config: vec4<f32>, // unused
  ripples: array<vec4<f32>, 50>,
};

// Simple hash functions
fn hash11(p: f32) -> f32 {
    var v = fract(p * 0.1031);
    v = fract(v + dot(vec2<f32>(v, v), vec2<f32>(v, v) + 33.33));
    return fract(v * v * 43758.5453);
}
fn hash21(p: vec2<f32>) -> f32 {
    var v = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    v = fract(v + dot(v, v.yzx + 33.33));
    return fract((v.x + v.y) * v.z);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    let n = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3))));
    return fract(n * 43758.5453);
}

@compute @workgroup_size(8,8,1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dimsI = textureDimensions(readTexture);
    let resolution = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) { return; }
    let uv = vec2<f32>(f32(gid.x) / resolution.x, f32(gid.y) / resolution.y);
    let time = u.config.x;

    // Read source and depth
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Params
    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let rawBlock = clamp(u.zoom_params.y, 0.0, 1.0);
    let corruptionSpeed = clamp(u.zoom_params.z, 0.0, 1.0) * 5.0;
    let depthFocus = clamp(u.zoom_params.w, 0.0, 1.0);

    // Calculate block size in pixels
    let blockSizePx = floor(mix(5.0, 150.0, rawBlock));
    let blockUV = vec2<i32>(i32(floor(uv.x * resolution.x / blockSizePx)), i32(floor(uv.y * resolution.y / blockSizePx)));

    let id = f32((blockUV.x * 73856093) ^ (blockUV.y * 19349663));
    let blockHashTime = floor(time * corruptionSpeed * hash11(id + 1.0));
    let blockHash = hash21(vec2<f32>(f32(blockUV.x), f32(blockUV.y)) + blockHashTime);

    var glitchUV = uv;

    let signalStrength = 0.55 + 0.45 * sin(time * corruptionSpeed * 0.2);
    let corruptionAmount = (1.0 - signalStrength) * intensity * 2.0;

    if (blockHash < (corruptionAmount * 0.5)) {
        let disp = (hash22(vec2<f32>(f32(blockUV.x), f32(blockUV.y)) * 99.0 + blockHashTime) - 0.5) * 0.4;
        glitchUV += disp;
    }

    let pixelHash = hash21(uv * 500.0 + time * corruptionSpeed);
    if (blockHash < (corruptionAmount * 0.2)) {
        glitchUV += (vec2<f32>(pixelHash, hash21(uv*600.0)) - 0.5) * vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y) * 20.0;
    }

    // Chromatic aberration
    let depthInfluence = 1.0 - abs(depth - depthFocus);
    let a_depth = pow(depthInfluence, 2.0);
    var aberrationOffset = (hash22(uv + time * 0.1) - 0.5) * 0.01 * corruptionAmount * a_depth;
    if (blockHash < (corruptionAmount * 0.4)) { aberrationOffset *= 4.0; }
    let r = textureSampleLevel(readTexture, u_sampler, glitchUV + aberrationOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, glitchUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, glitchUV - aberrationOffset, 0.0).b;
    var outCol = vec3<f32>(r, g, b);

    // scanline and noise
    let scanLine = sin(uv.y * resolution.y * 1.5 + time) * 0.04 * corruptionAmount;
    outCol -= scanLine * a_depth;
    let noise = (hash11(dot(uv, vec2<f32>(12.9898, 78.233)) + time) - 0.5) * 0.15 * corruptionAmount;
    outCol += noise * a_depth;

    outCol = clamp(outCol, vec3<f32>(0.0), vec3<f32>(1.0));
    if (intensity < 0.01) { outCol = src.rgb; }

    textureStore(writeTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(outCol, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
