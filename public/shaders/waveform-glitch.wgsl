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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    let baseAmp = u.zoom_params.x * 0.1;       // Base Glitch Amplitude
    let speed = u.zoom_params.y * 10.0;        // Wave Speed
    let rgbSplit = u.zoom_params.z * 0.05;     // Chromatic Aberration
    let contentReact = u.zoom_params.w;        // Blue Channel Reaction

    // Mouse Inputs
    let mouseX = u.zoom_config.y; // 0..1
    let mouseY = u.zoom_config.z; // 0..1

    // Interactive Controls from Mouse
    // X controls Frequency
    let freq = mix(2.0, 50.0, mouseX);

    // Y controls Extra Amplitude
    let mouseAmp = mix(0.0, 0.2, mouseY);

    let totalAmp = baseAmp + mouseAmp;

    // Sample video for content reaction
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    // Use Blue channel as a mask for glitch intensity?
    // If contentReact is 1.0, dark blue areas won't glitch.
    let reaction = mix(1.0, srcColor.b, contentReact);

    // Calculate Sine Wave Displacement
    // Horizontal waves
    let wave = sin(uv.y * freq + time * speed);
    let displacement = wave * totalAmp * reaction;

    // Apply Chromatic Aberration (RGB Split)
    // R is offset +, G is normal, B is offset -
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(displacement + rgbSplit, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(displacement, 0.0), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(displacement - rgbSplit, 0.0), 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));
}
