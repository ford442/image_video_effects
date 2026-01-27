struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

fn rand(n: vec2<f32>) -> f32 {
    return fract(sin(dot(n, vec2<f32>(12.9898, 4.1414))) * 43758.5453);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(coord) / vec2<f32>(dims);

    let instability = u.zoom_params.x; // Global instability level
    let chroma_split = u.zoom_params.y; // RGB Split
    let scan_drift = u.zoom_params.z; // V-Hold
    let static_noise = u.zoom_params.w; // Static

    let time = u.config.y;
    let mouse = u.zoom_config.yz;
    let aspect = u.config.z / u.config.w;

    // Mouse Interaction: Stabilize the hologram near the mouse
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Stabilize Factor (1.0 near mouse, 0.0 far away)
    let stability = smoothstep(0.5, 0.0, dist);

    // Net Glitch Level (High far away, Low near mouse)
    let glitch_level = instability * (1.0 - stability);

    // 1. Vertical Sync Drift (V-Hold)
    // Shift Y based on time and glitch level
    let y_shift = sin(time * 0.5) * scan_drift * glitch_level;
    // Jitter (random jumps)
    let y_jitter = step(0.9, rand(vec2<f32>(time, 0.0))) * (rand(vec2<f32>(time, 1.0)) - 0.5) * glitch_level;

    let drifted_uv = vec2<f32>(uv.x, fract(uv.y + y_shift + y_jitter));

    // 2. Scanline Slicing (Horizontal strips offset)
    let scan_slice = floor(drifted_uv.y * 50.0);
    let slice_offset = (rand(vec2<f32>(scan_slice, time)) - 0.5) * 0.1 * glitch_level;

    let sliced_uv = vec2<f32>(drifted_uv.x + slice_offset, drifted_uv.y);

    // 3. Chromatic Aberration (RGB Split)
    // Separate R, G, B channels by offset
    let split_amt = chroma_split * glitch_level * 0.05;

    let r = textureSampleLevel(readTexture, u_sampler, sliced_uv + vec2<f32>(split_amt, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sliced_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sliced_uv - vec2<f32>(split_amt, 0.0), 0.0).b;

    var color = vec3<f32>(r, g, b);

    // 4. Scanlines (Dark lines)
    let scanline = 0.5 + 0.5 * sin(drifted_uv.y * 800.0);
    color *= mix(1.0, scanline, 0.5); // Apply scanlines mildly

    // 5. Static Noise
    let noise = rand(uv * time);
    color += noise * static_noise * glitch_level;

    // 6. Holographic Blue Tint
    // Mix towards blue based on glitch level (hologram look)
    let holo_tint = vec3<f32>(0.2, 0.6, 1.0);
    color = mix(color, dot(color, vec3<f32>(0.33)) * holo_tint, glitch_level * 0.5);

    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
}
