// ═══════════════════════════════════════════════════════════════════
//  Cyber Grid Pulse
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
// ═══════════════════════════════════════════════════════════════════

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
// A glowing grid that pulses with the music and distorts near the mouse.

fn get_luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.zoom_config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters — bass drives pulse
    let gridSize = 20.0 + u.zoom_params.x * 50.0;
    let pulseSpeed = (2.0 + u.zoom_params.y * 5.0) * (1.0 + bass * 0.5);
    let distortionStrength = 0.1 + u.zoom_params.z * 0.4;
    let glowIntensity = (0.5 + u.zoom_params.w * 1.5) * (1.0 + mids * 0.3);

    // Distort UV based on mouse
    let aspect = resolution.x / max(resolution.y, 0.001);
    let dVec = uv - mouse;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    // Magnetic pull distortion — branchless
    let hasMouse = select(0.0, 1.0, mouse.x >= 0.0);
    let pull = smoothstep(0.4, 0.0, dist) * distortionStrength * hasMouse;
    let safeDVec = dVec + vec2<f32>(0.0001);
    let distortedUV = uv - normalize(safeDVec) * pull * (0.5 + 0.5 * sin(time * 5.0));

    let baseColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);
    let luma = get_luminance(baseColor.rgb);

    // Grid Calculation
    let gridUV = distortedUV * gridSize;
    let wave = sin(gridUV.y * 0.5 + time * pulseSpeed) * 0.1;
    let gridLineX = abs(fract(gridUV.x + wave) - 0.5);
    let gridLineY = abs(fract(gridUV.y) - 0.5);

    let thickness = 0.02 + luma * 0.1;
    let gridMask = 1.0 - smoothstep(thickness, thickness + 0.02, min(gridLineX, gridLineY));

    // Pulse color — treble adds shimmer
    let pulse = (0.5 + 0.5 * sin(time * pulseSpeed - dist * 10.0)) * (1.0 + treble * 0.2);
    let gridColor = vec3<f32>(0.0, 1.0, 0.8) * pulse * glowIntensity;

    var finalColor = baseColor.rgb;
    let scanline = sin(uv.y * resolution.y * 0.5 + time * 10.0) * 0.1;

    finalColor = mix(finalColor, gridColor + baseColor.rgb * 0.5, gridMask);
    finalColor += gridColor * gridMask * pulse;
    finalColor += vec3<f32>(scanline);

    // Mouse highlight — branchless
    let highlight = smoothstep(0.2, 0.0, dist) * mouseDown * hasMouse;
    finalColor += vec3<f32>(0.2, 0.4, 1.0) * highlight;

    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: grid edge presence + audio pulse + base image alpha
    let alpha = clamp(gridMask * 0.6 + luma * 0.2 + bass * 0.15 + baseColor.a * 0.1, 0.0, 1.0);
    let fc = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
