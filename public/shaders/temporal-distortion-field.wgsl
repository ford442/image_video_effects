// ═══════════════════════════════════════════════════════════════════
//  Temporal Distortion Field
//  Category: image
//  Features: mouse-freeze, temporal-ghosting, fbm-warp, depth-field-modulation,
//            chromatic-time-lag, temporal-freeze-memory, depth-field-radius
//  Complexity: High
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn fbmWarp(p_in: vec2<f32>, time: f32) -> vec2<f32> {
    var p = p_in;
    var v = vec2<f32>(0.0);
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < 4; i = i + 1) {
        v += amp * vec2<f32>(
            sin(p.x * freq + time),
            cos(p.y * freq + time)
        );
        p = p * 1.8 + v * 0.3;
        amp *= 0.5;
        freq *= 2.0;
    }
    return v;
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
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let freeze = mouseDown;
    let freezeAmount = u.zoom_params.x;
    let warpStrength = u.zoom_params.y;
    let ghostCount = u.zoom_params.z;
    let depthWeight = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Depth-aware field radius: closer objects are frozen closer to mouse
    let dM = length(uv - mouse);
    let fieldRadius = freezeAmount * (1.0 - depth * 0.3);
    let inField = smoothstep(fieldRadius * 1.2, fieldRadius * 0.8, dM);

    var warpUV = uv;
    let w = fbmWarp(uv * 3.0, time) * warpStrength * (1.0 + bass * 0.2);
    warpUV = warpUV + w * (1.0 - inField * freeze);

    // Chromatic time-lag splitting
    var rUV = warpUV;
    var gUV = warpUV;
    var bUV = warpUV;
    for (var i: i32 = 0; i < i32(ghostCount * 5.0 + 1.0); i = i + 1) {
        let lag = 0.02 * f32(i) * (1.0 + mids * 0.3);
        // R = past, G = present, B = future
        rUV = rUV - vec2<f32>(lag, 0.0);
        bUV = bUV + vec2<f32>(lag, 0.0);
    }

    rUV = clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0));
    gUV = clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0));
    bUV = clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0));

    var color = vec3<f32>(0.0);
    color.r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    color.g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    color.b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    let freezeColor = textureSampleLevel(readTexture, u_sampler, clamp(warpUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    color = mix(color, freezeColor, inField * freeze);

    // Temporal freeze memory: ghost trails persist longer
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let memory = mix(color, prev * 0.9, (1.0 - freeze) * 0.06 + freeze * 0.12 + bass * 0.02);

    let alpha = mix(0.7, 1.0, inField * freeze * 0.5 + length(w) * 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(memory, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(memory, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
