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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let gridScale = mix(10.0, 50.0, u.zoom_params.x);
    let warpAmt = u.zoom_params.y * 0.5;
    let glowAmt = u.zoom_params.z;
    let timeSpeed = u.zoom_params.w;

    let time = u.config.x * timeSpeed;
    let mouse = u.zoom_config.yz;

    // Warp UVs for Grid
    let dist = distance(uv * vec2(aspect, 1.0), mouse * vec2(aspect, 1.0));
    let warp = (1.0 - smoothstep(0.0, 0.5, dist)) * warpAmt;

    // Displace UVs away from mouse
    let dir = normalize(uv - mouse);
    let warpedUV = uv - dir * warp;

    // Moving Grid
    let gridUV = warpedUV * gridScale + vec2(0.0, time);

    // Draw Lines
    let lines = abs(fract(gridUV) - 0.5);
    let gridLine = smoothstep(0.45, 0.48, max(lines.x, lines.y)); // Thick lines? No, 0.5 is center.
    // Logic: fract goes 0->1. Center 0.5. abs(val-0.5) goes 0.5->0->0.5.
    // We want lines at edges (near 0.5).
    // So if value is > 0.45, it's a line.

    // Neon Color
    let lineColor = vec3<f32>(1.0, 0.0, 1.0); // Magenta
    let gridColor = lineColor * gridLine * (1.0 + glowAmt * 2.0);

    // Sample Video on Floor (warped)
    let videoColor = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0).rgb;

    // Reflection effect: Mirror video on grid
    // Or just mix.
    var finalColor = mix(videoColor * 0.5, gridColor, gridLine);

    // Add glow around mouse
    finalColor += vec3(0.0, 1.0, 1.0) * warp * 2.0;

    textureStore(writeTexture, global_id.xy, vec4(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
