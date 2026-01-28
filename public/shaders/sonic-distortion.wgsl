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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Params
    let freq = u.zoom_params.x * 100.0; // Frequency (10-100ish)
    let speed = u.zoom_params.y * 10.0; // Speed
    let amp = u.zoom_params.z * 0.05;   // Amplitude
    let radius = u.zoom_params.w;       // Radius

    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);

    let dist = distance(uvCorrected, mouseCorrected);
    let dir = normalize(uv - mouse);

    var offset = vec2<f32>(0.0);

    // Apply distortion if within radius (with falloff)
    let safeRadius = max(0.001, radius);
    let mask = 1.0 - smoothstep(safeRadius * 0.8, safeRadius, dist);

    if (mask > 0.0) {
        // Sonic wave function
        let wave = sin(dist * freq - time * speed);
        // Add some noise/jitter to make it "sonic"
        let jitter = sin(uv.y * 500.0 + time * 20.0) * 0.1;

        offset = dir * (wave + jitter) * amp * mask;
    }

    // Chromatic Aberration based on offset
    let r = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + offset * 1.05, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + offset * 1.1, 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));
}
