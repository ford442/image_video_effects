// ═══════════════════════════════════════════════════════════════════
//  Stereoscopic 3D
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(prev: f32, raw: f32) -> f32 {
    let k = select(0.15, 0.8, raw > prev);
    return mix(prev, raw, k);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Read persistent state from previous frame (dataTextureC)
    let prev = textureLoad(dataTextureC, coords, 0);

    // Smoothed audio envelope eliminates raw bass strobe
    let rawBass = bass;
    let envBass = bass_env(prev.r, rawBass);

    // Spring-damper mouse follow with per-pixel exponential smoothing
    let rawMouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let snap = select(0.06, 0.3, mouseDown > 0.5);
    let smoothMouse = mix(prev.gb, rawMouse, vec2<f32>(snap));

    // Params
    let maxSep = u.zoom_params.x * 0.05;
    let focusOffset = u.zoom_params.y;
    let glitchStr = u.zoom_params.z;
    let lensRot = (u.zoom_params.w - 0.5) * 0.4;

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Mouse affects convergence bias (X) and focal plane (Y)
    let mouseBias = (smoothMouse.x - 0.5) * 2.0;
    let focalWarp = (smoothMouse.y - 0.5) * 0.3;
    let sceneDepth = (uv.y - focusOffset + focalWarp) + mouseBias;

    // Beat-reactive separation with click boost
    let clickBoost = select(1.0, 1.3, mouseDown > 0.5);
    let audioPulse = 1.0 + envBass * 0.4 * clickBoost;
    var sepOffset = vec2<f32>(sceneDepth * maxSep * audioPulse, 0.0);

    // Glitch with envelope-driven amplitude
    let jitter = sin(uv.y * 200.0 + time * 30.0) * cos(time * 15.0);
    let block = floor(uv.y * 20.0);
    let blockNoise = fract(sin(block * 12.9898 + time) * 43758.5453);
    let glitchFactor = (jitter * 0.5 + blockNoise * 0.5) * (1.0 + envBass * 3.0);
    sepOffset = vec2<f32>(sepOffset.x + glitchFactor * glitchStr * 0.02, sepOffset.y);

    // Rotation: param + mouse-driven nudge
    let rot = lensRot + smoothMouse.x * 0.15 + (smoothMouse.y - 0.5) * 0.1;
    let c = cos(rot);
    let s = sin(rot);
    sepOffset = vec2<f32>(sepOffset.x * c - sepOffset.y * s, sepOffset.x * s + sepOffset.y * c);

    // Temporal feedback trails: ghost offset from previous intensity
    let prevIntensity = prev.a;
    let ghost = prevIntensity * 0.003;
    let redUV = clamp(uv - sepOffset - vec2<f32>(ghost, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let cyanUV = clamp(uv + sepOffset + vec2<f32>(ghost, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let redColor = textureSampleLevel(readTexture, u_sampler, redUV, 0.0).r;
    let cyanColor = textureSampleLevel(readTexture, u_sampler, cyanUV, 0.0).gb;
    var finalColor = vec3<f32>(redColor, cyanColor.x, cyanColor.y);

    // Treble sparkle on highlights + mids color warmth
    finalColor = finalColor + vec3<f32>(treble * 0.08 + mids * 0.03, treble * 0.04 + mids * 0.02, treble * 0.12);

    // Smooth intensity for temporal trail decay
    let currentIntensity = clamp(abs(sceneDepth) * 2.0 + length(sepOffset) * 20.0 + glitchStr * 0.5, 0.0, 1.0);
    let trailIntensity = mix(prevIntensity, currentIntensity, 0.12);
    let luminance = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));

    // Audio-reactive color boost
    finalColor = finalColor * (1.0 + envBass * 0.25 + mids * 0.1);

    // Alpha encodes trail age / interaction intensity
    let alpha = clamp(mix(0.6, 1.0, trailIntensity * 0.5 + luminance * 0.3 + envBass * 0.2), 0.0, 1.0);

    let outColor = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, coords, outColor);
    textureStore(dataTextureA, global_id.xy, outColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
