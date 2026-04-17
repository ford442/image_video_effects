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

// Double Exposure Zoom
// Param 1: Rotation (Input 0..1 maps to -PI..PI)
// Param 2: Zoom Level (Input 0..1 maps to 0.25x .. 4.0x)
// Param 3: Edge Fade (0..1)
// Param 4: Audio Reactivity (0..1)

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    var mouse = u.zoom_config.yz;

    let rot = (u.zoom_params.x - 0.5) * 6.28318;
    let zoomRaw = u.zoom_params.y;
    let edgeFade = u.zoom_params.z;
    let audioReact = u.zoom_params.w;
    let bass = plasmaBuffer[0].x;

    let zoom = pow(2.0, (zoomRaw - 0.5) * 4.0 + bass * audioReact);

    let col1 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    var uv2 = uv - mouse;
    uv2.x *= aspect;
    let c = cos(rot);
    let s = sin(rot);
    let rx = uv2.x * c - uv2.y * s;
    let ry = uv2.x * s + uv2.y * c;
    uv2 = vec2<f32>(rx, ry);
    uv2.x /= aspect;
    uv2 /= zoom;
    uv2 += mouse;

    let col2 = textureSampleLevel(readTexture, u_sampler, uv2, 0.0);

    // Edge fade for transformed layer
    let edgeDist = min(min(uv2.x, 1.0 - uv2.x), min(uv2.y, 1.0 - uv2.y));
    let edgeMask = smoothstep(0.0, 0.05 + edgeFade * 0.45, edgeDist);
    let col2Faded = vec4<f32>(col2.rgb, col2.a * edgeMask);

    // RGBA-aware screen blend
    let blendedRGB = 1.0 - (1.0 - col1.rgb) * (1.0 - col2Faded.rgb);
    let alpha = 1.0 - (1.0 - col1.a) * (1.0 - col2Faded.a);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(blendedRGB, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
