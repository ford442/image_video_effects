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

// Glitch Ripple Drag
// Ripples emanate from the mouse, permanently dragging pixels with them.
// Creates a liquid glitch effect that accumulates over time.

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    // Parameters
    let dragStrength = u.zoom_params.x * 0.05; // How much pixels move per frame
    let waveFreq = 10.0 + u.zoom_params.y * 40.0;
    let persistence = 0.9 + (u.zoom_params.z * 0.099); // 0.9 - 0.999
    let glitchAmt = u.zoom_params.w;

    // 1. Calculate Ripple Displacement
    let dVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);

    // Wave function: expanding rings from mouse
    // We want the wave to move OUTWARDS.
    // sin(dist * freq - time * speed)
    let wave = sin(dist * waveFreq - time * 5.0);

    // The force is only applied at the wave crests
    // And falls off with distance to avoid moving the whole screen too much
    let waveMask = smoothstep(0.5, 0.8, wave) * smoothstep(1.0, 0.0, dist * 2.0);

    // Direction of drag is away from mouse
    var dir = normalize(dVec);
    if (length(dVec) < 0.001) { dir = vec2<f32>(0.0); }

    // Add glitchy quantization to direction
    if (glitchAmt > 0.0) {
        let angle = atan2(dir.y, dir.x);
        let quant = 3.14159 / (4.0 + glitchAmt * 8.0);
        let qAngle = floor(angle / quant) * quant;
        dir = vec2<f32>(cos(qAngle), sin(qAngle));
    }

    let displacement = dir * dragStrength * waveMask;

    // 2. Sample History
    // We sample history at the position "upstream" of the drag
    // Current pixel (uv) gets color from (uv - displacement)

    let sampleUV = uv - displacement;

    // Read previous frame (feedback)
    var history = textureSampleLevel(dataTextureC, u_sampler, sampleUV, 0.0);

    // Read current video frame
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // 3. Blend Logic
    // If history is empty (alpha=0), init with input.
    if (history.a < 0.1) {
        history = inputColor;
    }

    // We mix the input video back in slowly to prevent total degradation,
    // but keep it high persistence to allow the drag to work.
    // If we want "responsive video", we need the video to update.
    // But the drag effect requires feedback.

    // Result = Mix(Video, History, Persistence)
    var finalColor = mix(inputColor, history, persistence);

    // Add extra glitch artifact: Color separation
    if (glitchAmt > 0.5 && waveMask > 0.1) {
        let r = textureSampleLevel(dataTextureC, u_sampler, sampleUV + vec2<f32>(0.005, 0.0), 0.0).r;
        let b = textureSampleLevel(dataTextureC, u_sampler, sampleUV - vec2<f32>(0.005, 0.0), 0.0).b;
        finalColor = vec4<f32>(r, finalColor.g, b, 1.0);
    }

    finalColor.a = 1.0;

    // Output
    textureStore(writeTexture, global_id.xy, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
}
