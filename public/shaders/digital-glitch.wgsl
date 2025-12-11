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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=blockIntensity (0..1), y=channelShift (0..1), z=scanline (0..1), w=unused
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    var n = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(n) * 43758.5453123);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Block displacement
    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let blockSize = mix(4.0, 64.0, intensity);
    let invBlock = 1.0 / blockSize;

    let px = vec2<f32>(floor(uv.x * blockSize), floor(uv.y * blockSize));
    let seed = hash21(px + vec2<f32>(time * 0.1, 0.0));

    let maxShift = mix(0.0, 0.05, intensity);
    let xShift = (seed - 0.5) * maxShift;
    let yShift = (hash21(px + vec2<f32>(1.0, 7.0) + vec2<f32>(time * 0.07, 0.0)) - 0.5) * maxShift;

    var displacedUV = uv + vec2<f32>(xShift, yShift);

    // Apply scanline tearing for some rows
    let scan = u.zoom_params.z;
    if (scan > 0.01) {
        let row = floor(uv.y * blockSize);
        let scanSeed = hash21(vec2<f32>(row, floor(time * 10.0)));
        let tear = step(0.95, scanSeed); // rare tear
        displacedUV.x += mix(0.0, 0.2 * (seed - 0.5), tear * scan);
    }

    // Chromatic aberration/channel shift
    let chroma = u.zoom_params.y * 0.02;
    let r = textureSampleLevel(readTexture, u_sampler, displacedUV + vec2<f32>(chroma, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, displacedUV - vec2<f32>(chroma, 0.0), 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Add occasional block color shifts
    if (seed > 0.9 && intensity > 0.4) {
        color = mix(color, vec3<f32>(hash21(px + 2.0), hash21(px + 7.0), hash21(px + 11.0)), 0.7);
    }

    // Slight vignetting to hide artifacts
    let dist = length(uv - 0.5);
    color *= 1.0 - smoothstep(0.7, 1.0, dist) * 0.6;

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    // Depth grab
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
