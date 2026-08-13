// ═══════════════════════════════════════════════════════════════════
//  Cyber Focus
//  Mouse-tracked focus aperture; everything outside it gets blocky glitch
//  offset, chromatic aberration, and box blur scaled by distance.
//  Features: mouse-driven, audio-reactive, upgraded-rgba
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    var mousePos = u.zoom_config.yz;
    let heldFocus = step(0.5, u.zoom_config.w);
    let aspectRatio = resolution.x / resolution.y;
    let time = u.config.x;

    // Mouse is 0-1. UV is 0-1.
    // Distance needs aspect ratio correction if we want circular radius.
    // However, if we don't correct, it matches the screen shape (oval).
    // Let's correct for circular radius.
    let distVec = (uv - mousePos) * vec2<f32>(aspectRatio, 1.0);
    let dist = length(distVec);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Bass pulses the focus aperture, mids drive glitch/aberration
    let radius = (u.zoom_params.x * 0.5 + 0.1) * (1.0 + bass * 0.35); // 0.1 to 0.6
    let blurStrength = u.zoom_params.y * 10.0;
    let glitchIntensity = u.zoom_params.z * (1.0 + mids * 0.5);
    let aberration = u.zoom_params.w * 0.05 * (1.0 + mids * 0.4);

    var clickClarity = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspectRatio, 1.0);
            clickClarity += smoothstep(0.025, 0.0, abs(length(delta) - age * 0.48)) * exp(-age * 1.5);
        }
    }

    // Smooth focus aperture plus fast scanner packets and click clarity fronts.
    let activeRadius = radius * (1.0 + heldFocus * 0.35);
    let baseFocusMask = smoothstep(activeRadius, activeRadius + 0.1, dist);
    let scanPacket = pow(max(0.0, sin(uv.y * 75.0 - time * 15.0)), 14.0) * baseFocusMask;
    let focusMask = clamp(baseFocusMask * (1.0 - clickClarity * 0.9) - scanPacket * 0.18, 0.0, 1.0);

    var finalColor = vec4<f32>(0.0);

    if (focusMask < 0.01) {
        // Inside focus - crisp
        finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    } else {
        // Outside focus - process

        // 1. Glitch Offset (Blocky)
        var offset = vec2<f32>(0.0);
        if (glitchIntensity > 0.0) {
            let blockSize = 20.0;
            let blockId = floor(uv * blockSize);
            let blockSeed = hash21(blockId);
            let noise = 0.5 + 0.5 * sin(time * (4.0 + mids * 3.0) + blockSeed * 6.28318);
            if (noise < glitchIntensity * 0.2) {
                let direction = vec2<f32>(hash21(blockId), hash21(blockId + 1.0)) - 0.5;
                offset = direction * (0.06 + scanPacket * 0.06 + treble * 0.02);
            }
        }

        // 2. Chromatic Aberration + Blur
        // We will sample a few points and average them
        var r_acc = 0.0;
        var g_acc = 0.0;
        var b_acc = 0.0;
        var weight_acc = 0.0;

        let blurSize = blurStrength * focusMask / resolution;

        // Simple 3x3 box blur with offset
        for (var i = -1.0; i <= 1.0; i += 1.0) {
            for (var j = -1.0; j <= 1.0; j += 1.0) {
                let jitter = vec2<f32>(i, j);
                let sampleUV = clamp(uv + offset + jitter * blurSize, vec2<f32>(0.0), vec2<f32>(1.0));

                // Chromatic Aberration: R and B are offset
                let r = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(aberration * focusMask, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
                let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
                let b = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(aberration * focusMask, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

                r_acc += r;
                g_acc += g;
                b_acc += b;
                weight_acc += 1.0;
            }
        }

        // Blend based on mask (soft edge for the focus area)
        let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

        // Defocused regions thin out — alpha falls off with the focus mask
        let defocusAlpha = original.a * (1.0 - focusMask * 0.35);
        finalColor = vec4<f32>(r_acc / weight_acc, g_acc / weight_acc, b_acc / weight_acc, defocusAlpha);

        finalColor = mix(original, finalColor, focusMask);
    }

    finalColor = vec4<f32>(
        clamp(finalColor.rgb + vec3<f32>(0.05, 0.35, 0.55) * scanPacket * (0.2 + treble * 0.3), vec3<f32>(0.0), vec3<f32>(4.0)),
        finalColor.a
    );

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
