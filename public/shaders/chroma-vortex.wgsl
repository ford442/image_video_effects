// ═══════════════════════════════════════════════════════════════════
//  Chroma Vortex
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, audio-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  upgraded-rgba
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Twist, y=Spread, z=Radius, w=CenterBias
  ripples: array<vec4<f32>, 50>,
};

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    var mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let twist = u.zoom_params.x * 3.14159 * 2.0 * (1.0 + bass * 0.2 + mids * 0.1);
    let spread = u.zoom_params.y * 0.1 * (1.0 + treble * 0.1);
    let radius = max(u.zoom_params.z, 0.01);
    let centerBias = u.zoom_params.w;

    // Base color for alpha preservation
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let diff = uv - mousePos;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));

    var factor = smoothstep(radius, 0.0, dist);
    let power = centerBias * 4.8 + 0.2;
    factor = pow(factor, power);

    let angleBase = factor * twist;
    let angleR = angleBase - spread * factor * 10.0;
    let angleG = angleBase;
    let angleB = angleBase + spread * factor * 10.0;

    let diffSq = vec2<f32>(diff.x * aspect, diff.y);

    let rotR_sq = rotate(diffSq, angleR);
    let rotG_sq = rotate(diffSq, angleG);
    let rotB_sq = rotate(diffSq, angleB);

    let rotR = vec2<f32>(rotR_sq.x / aspect, rotR_sq.y);
    let rotG = vec2<f32>(rotG_sq.x / aspect, rotG_sq.y);
    let rotB = vec2<f32>(rotB_sq.x / aspect, rotB_sq.y);

    let uvR = clamp(mousePos + rotR, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(mousePos + rotG, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(mousePos + rotB, vec2<f32>(0.0), vec2<f32>(1.0));

    let colR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    let chromaSplit = length(uvR - uvB);

    // Alpha: preserve input transparency while blending vortex intensity
    let finalAlpha = mix(baseColor.a, 1.0, factor * 0.7);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(colR, colG, colB, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0, 0, 1));
    textureStore(dataTextureA, coord, vec4<f32>(colR, colG, colB, finalAlpha));
}
