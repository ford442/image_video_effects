// Temporal Rift — interactive temporal echo field
// Category: interactive-mouse
// Features: mouse-driven, click-reactive, audio-reactive, temporal, upgraded-rgba
// Upgraded: 2026-08-02 (Batch 30)
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=Aberration, w=Darkness
  ripples: array<vec4<f32>, 50>,
};

// Simple hash for jitter
fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn soft_ceiling(color: vec3<f32>) -> vec3<f32> {
    let positive = max(color, vec3<f32>(0.0));
    let peak = max(positive.x, max(positive.y, positive.z));
    return positive / (1.0 + max(peak - 1.0, 0.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        mousePos = rawMouse;
        mouseVelocity = vec2<f32>(0.0);
    }
    let dt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let omega = 10.0;
    mouseVelocity += ((rawMouse - mousePos) * (omega * omega) - mouseVelocity * (2.0 * omega)) * dt;
    mousePos += mouseVelocity * dt;
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = mousePos.x;
        extraBuffer[134] = mousePos.y;
        extraBuffer[135] = mouseVelocity.x;
        extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }
    let mouseDown = u.zoom_config.w;

    // Params
    let smearDecay = 0.9 + u.zoom_params.x * 0.09; // 0.90 to 0.99 (slow fade)
    let riftWidth = 0.05 + u.zoom_params.y * 0.2; // 0.05 to 0.25
    let chromaSep = u.zoom_params.z * 0.02; // 0.0 to 0.02
    let timeFlow = u.zoom_params.w; // Mix control

    let currColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let rift = 1.0 - smoothstep(0.0, riftWidth, dist);

    var clickRift = 0.0;
    var clickShear = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let radius = length(delta);
            let envelope = exp(-age * 1.6);
            clickRift = max(clickRift, (1.0 - smoothstep(0.0, 0.18, radius)) * envelope);
            clickShear += sin(radius * 90.0 - age * 18.0) * exp(-radius * 10.0) * envelope * 0.002;
        }
    }

    let fftIndex = (u32(clamp(uv.y, 0.0, 0.999) * 8.0) % 8u) + 1u;
    let fftVoice = clamp(plasmaBuffer[fftIndex].x, 0.0, 1.0);
    let separation = chromaSep * (1.0 + fftVoice * 0.5) + clamp(clickShear, -0.02, 0.02);
    let histRuv = clamp(uv + vec2<f32>(separation, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let histBuv = clamp(uv - vec2<f32>(separation, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let histR = textureSampleLevel(dataTextureC, u_sampler, histRuv, 0.0).r;
    let histG = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).g;
    let histB = textureSampleLevel(dataTextureC, u_sampler, histBuv, 0.0).b;
    let histColor = vec4<f32>(histR, histG, histB, currColor.a);
    let paintFactor = clamp(max(rift * (0.5 + 0.5 * mouseDown), clickRift) * (0.85 + fftVoice * 0.15), 0.0, 1.0);
    let nextHist = mix(histColor * smearDecay, currColor, paintFactor);
    let display = soft_ceiling(currColor.rgb + nextHist.rgb * timeFlow);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(display, clamp(currColor.a + nextHist.a * timeFlow, 0.0, 1.0)));
    textureStore(dataTextureA, global_id.xy, clamp(nextHist, vec4<f32>(0.0), vec4<f32>(1.0)));
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
