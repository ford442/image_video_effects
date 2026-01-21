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
  zoom_params: vec4<f32>,  // x=ThreadDensity, y=VibrationAmp, z=RGBSplit, w=Decay
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;
    let mouseDown = u.zoom_config.w;

    // Params
    let density = mix(50.0, 300.0, u.zoom_params.x);
    let amp = u.zoom_params.y * 0.2; // Vibration strength
    let split = u.zoom_params.z * 0.05; // Chroma split amount
    let decay = u.zoom_params.w; // Unused in this simple version, could be used for trail

    // Thread ID (Row)
    // We treat the image as a set of horizontal threads
    let threadID = floor(uv.y * density);
    let threadUVY = (threadID + 0.5) / density; // Center of the thread

    // Calculate influence of mouse on this specific thread
    let distY = abs(threadUVY - mouse.y);
    let mouseRadius = 0.2;

    // Influence drops off as we get further from mouse Y
    let influence = smoothstep(mouseRadius, 0.0, distY);

    // Vibration calculation
    // Base vibration on horizontal distance to mouse and time
    // Threads "near" the mouse vibrate
    // Adding time makes them oscillate
    let distX = uv.x - mouse.x;

    // "Pluck" shape: Gaussian bell curve + sine wave
    let vibration = sin(distX * 20.0 - time * 10.0) * exp(-abs(distX) * 5.0);

    // If mouse is down, pull harder?
    let activeAmp = amp * (1.0 + mouseDown * 2.0);

    let offset = vibration * influence * activeAmp;

    // RGB Split offsets
    // R moves one way, B the other, G stays or moves less
    let offsetR = offset * (1.0 + split * 10.0);
    let offsetG = offset;
    let offsetB = offset * (1.0 - split * 10.0);

    // Sample with offsets
    // We sample from the *original* texture UVs displaced by our thread offset
    // Clamp Y to the thread's Y to mimic "scanlines" or "LCD" effect?
    // Let's just displace X, keep Y (maybe quantize Y slightly?)

    // To make it look like distinct threads, we can mask between them
    let threadPattern = abs(fract(uv.y * density) - 0.5) * 2.0; // 0 at center, 1 at edge
    let mask = smoothstep(0.9, 0.6, threadPattern); // Darken edges of threads

    let uvR = vec2<f32>(uv.x - offsetR, uv.y);
    let uvG = vec2<f32>(uv.x - offsetG, uv.y);
    let uvB = vec2<f32>(uv.x - offsetB, uv.y);

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    let finalColor = vec3<f32>(r, g, b) * mask;

    // Add a highlight where the mouse is
    let highlight = exp(-length(uv - mouse) * 10.0) * 0.2;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor + highlight, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
