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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash11(p: f32) -> f32 {
    var p2 = fract(p * .1031);
    p2 *= p2 + 33.33;
    p2 *= p2 + p2;
    return fract(p2);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Params
    let driftSpeed = u.zoom_params.x * 2.0;
    let lineHeight = mix(0.001, 0.1, u.zoom_params.y); // Height of the scanline strip
    let jitter = u.zoom_params.z * 0.1;
    let colorShift = u.zoom_params.w * 0.05;

    // Determine which horizontal strip we are in
    let stripId = floor(uv.y / lineHeight);

    // Each strip drifts independently based on time and its ID
    let stripRand = hash11(stripId);

    // Mouse Interaction:
    // Mouse Y selects a "bad" zone with more drift?
    // Or mouse proximity increases jitter.
    let distY = abs(uv.y - mouse.y);
    let mouseEffect = smoothstep(0.2, 0.0, distY); // Stronger near mouse Y

    // Calculate horizontal offset
    // Sine wave movement + random jitter
    var offset = sin(time * driftSpeed + stripRand * 6.28) * jitter;

    // Add mouse influence
    offset += (hash11(stripId + time) - 0.5) * mouseEffect * jitter * 2.0;

    // Color separation (drift R, G, B differently)
    let rOffset = offset + colorShift;
    let gOffset = offset;
    let bOffset = offset - colorShift;

    // Sample with wrap around or clamp?
    // Usually glitch effects wrap.
    let rUV = vec2<f32>(fract(uv.x + rOffset), uv.y);
    let gUV = vec2<f32>(fract(uv.x + gOffset), uv.y);
    let bUV = vec2<f32>(fract(uv.x + bOffset), uv.y);

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // Scanline darkness (optional)
    // Make boundaries between strips dark
    let stripUVy = fract(uv.y / lineHeight);
    let lineDark = smoothstep(0.0, 0.1, stripUVy) * smoothstep(1.0, 0.9, stripUVy);
    // Actually standard scanline look is better:
    // let scanline = sin(uv.y * resolution.y * 0.5) * 0.1;

    var color = vec3<f32>(r, g, b);

    // Apply line separation darkness
    color *= mix(0.8, 1.0, lineDark);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
