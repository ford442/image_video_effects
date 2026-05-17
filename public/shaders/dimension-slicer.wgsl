// ═══════════════════════════════════════════════════════════════════
//  Dimension Slicer
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
  config: vec4<f32>,       // x=Time
  zoom_config: vec4<f32>,  // y=MouseX, z=MouseY
  zoom_params: vec4<f32>,  // x=SliceWidth, y=Distortion, z=Angle, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = u.config.zw;
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / dims;
    let aspect = dims.x / max(dims.y, 0.001);

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;

    // Parameters — bass widens slice, mids boost aberration
    let sliceWidth  = mix(0.05, 0.4, u.zoom_params.x) * (1.0 + bass * 0.15);
    let distortion  = mix(0.0, 2.0, u.zoom_params.y);
    let angle       = u.zoom_params.z * 3.14159 * 2.0;
    let aberration  = u.zoom_params.w * 0.05 * (1.0 + mids * 0.3);

    let mouse = u.zoom_config.yz;

    var p = uv - mouse;
    p.x *= aspect;

    let pRot = rotate(p, angle);
    let dist = abs(pRot.x);

    let inSlice = 1.0 - smoothstep(sliceWidth - 0.01, sliceWidth, dist);

    // Warp UVs inside slice
    let zoom = 1.0 - distortion * 0.5 * cos(dist / max(sliceWidth, 0.001) * 3.14159);
    let offset = (uv - mouse) * (1.0 / max(zoom, 0.001) - 1.0);
    let warpedUV = clamp(uv + offset * inSlice, vec2<f32>(0.0), vec2<f32>(1.0));

    // Chromatic aberration — applied inside slice, zero outside
    let aberAmt = vec2<f32>(aberration, 0.0) * inSlice;
    let rUV = clamp(warpedUV + aberAmt, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(warpedUV - aberAmt, vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let baseAlpha = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0).a;

    // Slice edge glow
    let edge = smoothstep(sliceWidth - 0.02, sliceWidth, dist) * (1.0 - smoothstep(sliceWidth, sliceWidth + 0.01, dist));
    let sliceColor = vec3<f32>(r, g, b) + vec3<f32>(0.5, 0.8, 1.0) * edge * 2.0;

    // Outside slice: original image with soft darkening
    let outsideColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let shadow = smoothstep(sliceWidth, sliceWidth + 0.1, dist);
    let outsideDark = outsideColor * (0.5 + 0.5 * shadow);

    // Blend inside/outside — branchless
    var finalColor = mix(outsideDark, sliceColor, inSlice);
    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: slice presence + edge glow + audio
    let alpha = clamp(inSlice * 0.6 + edge * 0.8 + bass * 0.1 + baseAlpha * 0.1, 0.0, 1.0);
    let fc = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
