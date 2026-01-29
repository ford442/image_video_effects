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
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=Aberration, w=Darkness
  ripples: array<vec4<f32>, 50>,
};

fn getLuma(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;

    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    // Params
    let amplitude = u.zoom_params.x; // 0.0 to 1.0
    let thickness = max(0.001, u.zoom_params.y * 0.02); // scale thickness
    let waveOpacity = u.zoom_params.z;
    let scanLineAlpha = u.zoom_params.w;

    let mousePos = u.zoom_config.yz;
    let scanY = mousePos.y; // The Y coordinate we are scanning

    // Sample original image
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // 1. Draw Scan Line (Horizontal line at mousePos.y)
    let distScan = abs(uv.y - scanY);
    let scanLine = smoothstep(thickness, 0.0, distScan) * scanLineAlpha;
    let scanColor = vec3<f32>(1.0, 0.2, 0.2); // Red line for the scanner

    // 2. Draw Waveform
    // We want to visualize the luminance of the pixels at (x, scanY)
    // We sample the texture at the current x, but at the scanY height
    let scanSample = textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x, scanY), 0.0).rgb;
    let scanLuma = getLuma(scanSample);

    // Map luminance to Y position (centered at 0.5)
    let waveY = 0.5 + (scanLuma - 0.5) * amplitude;

    let distWave = abs(uv.y - waveY);
    let waveVal = smoothstep(thickness, 0.0, distWave);

    let waveColor = vec3<f32>(0.2, 1.0, 0.5); // Green phosphor color

    // Composite
    var finalColor = color;

    // Add Scan Line
    finalColor = mix(finalColor, scanColor, scanLine);

    // Add Waveform
    // Additive blending for "glowing" look
    finalColor = finalColor + waveColor * waveVal * waveOpacity;

    // Add faint grid?
    // let gridY = abs(uv.y - 0.5) < 0.002 ? 0.2 : 0.0;
    // finalColor += vec3<f32>(gridY);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
}
