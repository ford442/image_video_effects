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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=Width, w=Height
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // Params
  ripples: array<vec4<f32>, 50>,
};

// Cyber Grid Pulse
// A glowing grid that pulses with the music (simulated by time/interaction) and distorts near the mouse.

fn get_luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.zoom_config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Parameters
    let gridSize = 20.0 + u.zoom_params.x * 50.0; // Grid density
    let pulseSpeed = 2.0 + u.zoom_params.y * 5.0;
    let distortionStrength = 0.1 + u.zoom_params.z * 0.4;
    let glowIntensity = 0.5 + u.zoom_params.w * 1.5;

    // Distort UV based on mouse
    let aspect = resolution.x / resolution.y;
    let dVec = uv - mouse;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    // Magnetic pull distortion
    var distortedUV = uv;
    if (mouse.x >= 0.0) {
        let pull = smoothstep(0.4, 0.0, dist) * distortionStrength;
        distortedUV = uv - normalize(dVec) * pull * (0.5 + 0.5 * sin(time * 5.0)); // Pulsing pull
    }

    // Sample original image with slight chromatic aberration based on grid
    let baseColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).rgb;
    let luma = get_luminance(baseColor);

    // Grid Calculation
    let gridUV = distortedUV * gridSize;

    // Add wave movement to grid
    let wave = sin(gridUV.y * 0.5 + time * pulseSpeed) * 0.1;
    let gridLineX = abs(fract(gridUV.x + wave) - 0.5);
    let gridLineY = abs(fract(gridUV.y) - 0.5);

    let gridVal = smoothstep(0.48, 0.5, max(gridLineX, gridLineY)); // Sharp lines
    // Thicker lines near bright parts of image?
    let thickness = 0.02 + luma * 0.1;
    let gridMask = 1.0 - smoothstep(thickness, thickness + 0.02, min(gridLineX, gridLineY));

    // Pulse color
    let pulse = 0.5 + 0.5 * sin(time * pulseSpeed - dist * 10.0);
    let gridColor = vec3<f32>(0.0, 1.0, 0.8) * pulse * glowIntensity; // Cyan grid

    // Combine
    // If grid, show grid color additively, otherwise show base image
    var finalColor = baseColor;

    // Scanline effect
    let scanline = sin(uv.y * resolution.y * 0.5 + time * 10.0) * 0.1;

    finalColor = mix(finalColor, gridColor + baseColor * 0.5, gridMask);
    finalColor += gridColor * gridMask * pulse; // Glow
    finalColor += vec3<f32>(scanline);

    // Mouse interaction highlight
    if (mouse.x >= 0.0) {
        let highlight = smoothstep(0.2, 0.0, dist);
        finalColor += vec3<f32>(0.2, 0.4, 1.0) * highlight * mouseDown; // Blue flash on click
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
