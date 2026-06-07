// ═══════════════════════════════════════════════════════════════════
//  Crystal Mosaic
//  Category: geometric
//  Features: mouse-driven, audio-reactive, depth-parallax, chromatic-edges, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-31
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn triCell(uv: vec2<f32>, density: f32) -> vec3<f32> {
    let s = uv * density;
    let x = s.x;
    let y = s.y;
    let i = floor(x);
    let j = floor(y * 0.8660254);
    let u = fract(x);
    let v = fract(y * 0.8660254);
    let id = select(vec2<f32>(i, j), vec2<f32>(i + 0.5, j), fract(j * 0.5) > 0.25);
    return vec3<f32>(id, 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthShift = mix(-0.02, 0.02, depth);

    let density = mix(5.0, 40.0, u.zoom_params.x);
    let rotationAmt = u.zoom_params.y;
    let chromaticEdge = u.zoom_params.z * 0.01;
    let mouseInfluence = u.zoom_params.w;

    let s = uv * density;
    let i = floor(s.x);
    let j = floor(s.y * 0.8660254);
    let rowParity = i32(j) & 1;
    let u = fract(s.x);
    let v = fract(s.y * 0.8660254);

    // Triangle inside rhombus
    let triID = vec2<f32>(i + f32(rowParity) * 0.5, j);
    let triCenter = (triID + vec2<f32>(0.5, 0.57735)) / density;

    let dToMouse = length(triCenter - mousePos);
    let influence = smoothstep(0.4, 0.0, dToMouse) * mouseInfluence;

    // Rotate triangle based on mouse + audio
    let rot = (rotationAmt + influence + bass * 0.1) * 0.5;
    let localUV = uv - triCenter;
    let c = cos(rot);
    let s_rot = sin(rot);
    let rotatedUV = vec2<f32>(
        localUV.x * c - localUV.y * s_rot,
        localUV.x * s_rot + localUV.y * c
    ) + triCenter + vec2<f32>(depthShift, depthShift);

    // Chromatic edges: sample R/B at offset near triangle boundary
    let edge = smoothstep(0.15, 0.0, abs(v - 0.5) + abs(u - 0.5) * 0.5);
    let rUV = clamp(rotatedUV + vec2<f32>(chromaticEdge * edge * (1.0 + bass), 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(rotatedUV - vec2<f32>(chromaticEdge * edge * (1.0 + treble), 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, rotatedUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // Tile border highlight
    let border = smoothstep(0.05, 0.0, min(min(u, 1.0 - u), min(v, 1.0 - v))) * mids;

    let color = vec3<f32>(r, g, b) + vec3<f32>(0.3, 0.2, 0.4) * border;
    let alpha = clamp(0.85 + border * 0.15 + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
