// ═══════════════════════════════════════════════════════════════════
//  Spectral Smear
//  Category: image
//  Features: mouse-driven, history, upgraded-rgba, audio-reactive, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  upgraded-rgba
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

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=TrailDecay, y=BrushSize, z=ShiftSpeed, w=Intensity
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params (mids speeds hue shift, treble lifts smear intensity)
    let trailDecay = u.zoom_params.x;
    let brushSize = u.zoom_params.y * (1.0 + bass * 0.2);
    let shiftSpeed = u.zoom_params.z * (1.0 + mids * 0.8);
    let intensity = u.zoom_params.w * (1.0 + treble * 0.5);

    // Check mouse distance
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    let inBrush = smoothstep(brushSize, brushSize * 0.8, dist);

    // Get current video frame
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Get history (previous output)
    let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Create the "paint" color
    let hue = fract(time * shiftSpeed);
    let shiftColor = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
        0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
    );

    let paint = mix(current.rgb, shiftColor, 0.5);

    let historyDecayed = history.rgb * (0.9 + 0.09 * trailDecay);

    var newHistory = historyDecayed;
    if (inBrush > 0.01) {
        newHistory = mix(newHistory, shiftColor * 2.0, inBrush * intensity);
    }

    newHistory = clamp(newHistory, vec3<f32>(0.0), vec3<f32>(2.0));

    // Final composite: Video + History
    let finalColor = current.rgb + newHistory * 0.5;

    // Alpha: preserve input transparency while blending smear intensity
    let finalAlpha = mix(current.a, 1.0, inBrush * intensity * 0.7);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0, 0, 1));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, finalAlpha));
}
