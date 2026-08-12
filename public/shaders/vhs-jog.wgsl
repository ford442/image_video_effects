// ═══════════════════════════════════════════════════════════════════
//  VHS Jog Wheel
//  Category: image
//  Features: mouse-driven, glitch
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
  zoom_params: vec4<f32>,  // x=Noise, y=DistortionFreq, z=ColorBleed, w=Scanlines
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)),
                   hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)),
                   hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv_raw = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Base color for alpha preservation
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv_raw, 0.0);

    // Params — bass amplifies tracking instability, mids the warp freq, treble the bleed
    let noise_amt = clamp(u.zoom_params.x + bass * 0.15, 0.0, 1.0);
    let dist_freq = (u.zoom_params.y * 50.0 + 1.0) * (1.0 + mids * 0.5);
    let bleed_amt = u.zoom_params.z * 0.02 * (1.0 + bass * 0.4 + treble * 0.4);
    let scanline_intensity = u.zoom_params.w;

    // Mouse Inputs
    let mouse_x = u.zoom_config.y; // 0.0 to 1.0
    let mouse_y = u.zoom_config.z; // 0.0 to 1.0
    let mouse_down = u.zoom_config.w;

    // Jog Wheel: Mouse X controls horizontal tear/distortion intensity
    let distortion_strength = pow(abs(mouse_x - 0.5) * 2.0, 2.0) * 0.5; // Stronger at edges
    let direction = sign(mouse_x - 0.5);

    // Tracking: Mouse Y controls vertical offset
    let vertical_tracking = (mouse_y - 0.5) * 0.2;

    // Apply Vertical Tracking (looping)
    var uv = uv_raw;
    let headRollPhase = fract(uv.y - time * (0.55 + distortion_strength * 2.5) * direction + 0.5);
    let headSwitchRoll = exp(-pow((headRollPhase - 0.5) / 0.055, 2.0)) * distortion_strength;
    uv.y = fract(uv.y + vertical_tracking + time * 0.05 * distortion_strength * direction + headSwitchRoll * 0.035 * direction);

    var tapeSlip = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.2) {
            let slipY = fract(ripple.y + age * (0.22 + mids * 0.10));
            let bandDist = abs(fract(uv_raw.y - slipY + 0.5) - 0.5);
            tapeSlip += (1.0 - smoothstep(0.0, 0.035, bandDist)) * (1.0 - age / 2.2);
        }
    }
    tapeSlip += mouse_down * (1.0 - smoothstep(0.0, 0.025, abs(uv_raw.y - mouse_y))) * 0.45;

    // Horizontal Distortion (Jitter)
    // Create 'bands' of distortion based on Y and Time
    let dist_wave = noise(vec2<f32>(uv.y * dist_freq, time * 20.0));
    // Threshold the wave to make it look like digital tearing
    let tear = smoothstep(0.4, 0.6, dist_wave) * distortion_strength;

    let horizontalStreak = sin(uv.y * resolution.y * 0.15 - time * (35.0 + dist_freq)) * (headSwitchRoll + tapeSlip);
    uv.x += (dist_wave - 0.5) * tear * 0.2 + horizontalStreak * (0.015 + distortion_strength * 0.08) * direction;

    // Color Bleed (Chromatic Aberration)
    // R, G, B sampled at different X offsets
    let r_offset = bleed_amt * (1.0 + distortion_strength * 5.0);
    let b_offset = -bleed_amt * (1.0 + distortion_strength * 5.0);

    let r = textureSampleLevel(readTexture, u_sampler, fract(uv + vec2<f32>(r_offset, 0.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, fract(uv), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, fract(uv + vec2<f32>(b_offset, 0.0)), 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Static Noise
    let static_noise = noise(vec2<f32>(uv.x * resolution.x * 0.25, uv.y * 80.0 + time * 12.0));
    color += (static_noise - 0.5) * noise_amt;

    // Exact, clamped display-history loads make horizontal tape streaks stable.
    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
    let streakOffset = i32(round(direction * (3.0 + distortion_strength * 14.0 + tapeSlip * 8.0)));
    let history = textureLoad(dataTextureC, clamp(coord - vec2<i32>(streakOffset, 0), vec2<i32>(0), maxCoord), 0);
    color = max(color, clamp(history.rgb, vec3<f32>(0.0), vec3<f32>(3.0)) * (0.42 + headSwitchRoll * 0.25 + tapeSlip * 0.18));

    // Scanlines
    let scanline = sin(uv.y * resolution.y * 0.5 * PI);
    color *= 1.0 - (scanline * scanline_intensity * 0.5);

    // Vignette / Tube curve (optional, keep it subtle)
    let d = distance(uv_raw, vec2<f32>(0.5));
    color *= 1.0 - d * 0.3;
    color = max(color, vec3<f32>(0.0));
    color = clamp(color / (vec3<f32>(1.0) + color * 0.35), vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha: preserve input transparency while blending tear intensity
    let finalAlpha = clamp(mix(baseColor.a, 1.0, clamp(tear * 0.7 + tapeSlip * 0.3, 0.0, 1.0)), 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(color, finalAlpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv_raw, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0, 0, 0.0));
}
