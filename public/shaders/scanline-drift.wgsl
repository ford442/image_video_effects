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
  zoom_params: vec4<f32>,  // x=DriftSpeed, y=LineHeight, z=Jitter, w=ColorShift
  ripples: array<vec4<f32>, 50>,
};

fn hash11(p: f32) -> f32 {
    var p2 = fract(p * .1031);
    p2 *= p2 + 33.33;
    p2 *= p2 + p2;
    return fract(p2);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var mouse = u.zoom_config.yz;

    // Params
    let driftSpeed = u.zoom_params.x * 2.0 * (1.0 + bass * 0.2);
    let lineHeight = mix(0.001, 0.1, u.zoom_params.y);
    let jitter = u.zoom_params.z * 0.1 * (1.0 + mids * 0.3);
    let colorShift = u.zoom_params.w * 0.05;

    // Determine which horizontal strip we are in
    let stripId = floor(uv.y / lineHeight);
    let stripRand = hash11(stripId);

    // Mouse proximity increases jitter
    let distY = abs(uv.y - mouse.y);
    let mouseEffect = smoothstep(0.2, 0.0, distY);

    // Calculate horizontal offset
    var offset = sin(time * driftSpeed + stripRand * 6.28) * jitter;
    offset += (hash11(stripId + time) - 0.5) * mouseEffect * jitter * 2.0;

    // Color separation
    let rOffset = offset + colorShift;
    let gOffset = offset;
    let bOffset = offset - colorShift;

    let rUV = vec2<f32>(fract(uv.x + rOffset), uv.y);
    let gUV = vec2<f32>(fract(uv.x + gOffset), uv.y);
    let bUV = vec2<f32>(fract(uv.x + bOffset), uv.y);

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // Scanline darkness at strip boundaries
    let stripUVy = fract(uv.y / lineHeight);
    let lineDark = smoothstep(0.0, 0.1, stripUVy) * smoothstep(1.0, 0.9, stripUVy);

    var color = vec3<f32>(r, g, b);
    color *= mix(0.8, 1.0, lineDark);

    // Semantic alpha
    let driftMag = abs(rOffset - bOffset);
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(driftMag * 10.0 + mouseEffect * 0.3 + luma * 0.2, 0.0, 1.0);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
