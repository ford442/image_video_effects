// ═══════════════════════════════════════════════════════════════════
//  Silk Flow Advection
//  Category: image
//  Features: silk, flow, advection, painterly, curl-noise, audio-breath, mouse-finger, click-reactive, semantic-alpha
//  Complexity: High
//  Chunks From: _hash_library.wgsl (hash21, valueNoise)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — image colors gently advected along living silky curl-noise flows. Mouse finger disturbs the silk like fabric)
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
  zoom_params: vec4<f32>,  // x=Flow, y=Silk, z=Breath, w=Disturb
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let a = hash21(i); let b = hash21(i + vec2<f32>(1,0));
    let c = hash21(i + vec2<f32>(0,1)); let d = hash21(i + vec2<f32>(1,1));
    let u = f*f*(3.0-2.0*f);
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
    let e = 0.08;
    let n1 = valueNoise(p + vec2<f32>(0, e) + t);
    let n2 = valueNoise(p + vec2<f32>(e, 0) + t);
    let n3 = valueNoise(p - vec2<f32>(0, e) + t);
    let n4 = valueNoise(p - vec2<f32>(e, 0) + t);
    return vec2<f32>(n1 - n3, n4 - n2) * 0.6;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let flowAmt = u.zoom_params.x * (0.7 + bass * 0.35);
    let silk = u.zoom_params.y * 0.9 + 0.2;
    let breath = u.zoom_params.z * (0.6 + treble * 0.5);
    let disturb = u.zoom_params.w;

    let mousePress = u.zoom_config.w;
    let aspect = res.x / max(res.y, 1.0);
    let aspectVec = vec2<f32>(aspect, 1.0);

    // A critically-damped fabric finger follows the raw normalized cursor.
    let rawMouse = u.zoom_config.yz;
    var mouse = vec2<f32>(extraBuffer[133u], extraBuffer[134u]);
    var mouseVelocity = vec2<f32>(extraBuffer[135u], extraBuffer[136u]);
    let mouseInitialized = extraBuffer[137u] >= 0.5;
    if (!mouseInitialized) {
        mouse = rawMouse;
        mouseVelocity = vec2<f32>(0.0);
    }
    let springDt = select(0.0, clamp(time - extraBuffer[138u], 0.0005, 0.05), mouseInitialized);
    let springOmega = 8.0;
    let mouseAccel = springOmega * springOmega * (rawMouse - mouse)
        - 2.0 * springOmega * mouseVelocity;
    mouseVelocity += mouseAccel * springDt;
    mouse = clamp(mouse + mouseVelocity * springDt, vec2<f32>(-0.2), vec2<f32>(1.2));
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133u] = mouse.x;
        extraBuffer[134u] = mouse.y;
        extraBuffer[135u] = mouseVelocity.x;
        extraBuffer[136u] = mouseVelocity.y;
        extraBuffer[137u] = 1.0;
        extraBuffer[138u] = time;
    }

    // Previous advection state
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let previousVelocity = clamp(prev.xy, vec2<f32>(-0.08), vec2<f32>(0.08));

    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Living silk curl flow field
    let curl = curlNoise(uv * (3.5 + silk * 2.5), time * 0.04 + mids * 0.03);
    let breathWave = sin(uv.x * 4.0 + time * 1.2) * cos(uv.y * 3.0 - time * 0.7) * breath * 0.018;

    var liveVelocity = curl * flowAmt * 0.022 + vec2<f32>(breathWave, -breath * 0.011);

    // Mouse finger disturbance stays circular on wide canvases and safely
    // maps its aspect-space direction back into UV velocity.
    let mouseDeltaAspect = (uv - mouse) * aspectVec;
    let md = length(mouseDeltaAspect);
    if (md < 0.32) {
        let push = (1.0 - smoothstep(0.0, 0.3, md)) * disturb * (0.8 + mousePress * 1.6);
        let mouseDir = (mouseDeltaAspect / max(md, 0.001)) / aspectVec;
        liveVelocity += mouseDir * push * -0.035;
    }

    // Clicks pluck the silk with alternating tangent waves.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let clickVec = (uv - ripple.xy) * aspectVec;
            let clickDistance = length(clickVec);
            let tangentAspect = vec2<f32>(-clickVec.y, clickVec.x) / max(clickDistance, 0.001);
            let tangentUV = tangentAspect / aspectVec;
            let pluck = sin(clickDistance * 32.0 - age * 10.0)
                * exp(-age * 1.8) * smoothstep(0.34, 0.0, clickDistance);
            let directionSign = select(-1.0, 1.0, (ri % 2u) == 0u);
            liveVelocity += tangentUV * pluck * directionSign * disturb * 0.025;
        }
    }

    // The velocity state written to A is now actually consumed from C. This
    // temporal smoothing is raw state math, not display-color feedback.
    let velocityResponse = clamp(0.38 + flowAmt * 0.18 + mousePress * 0.12, 0.25, 0.75);
    let vel = clamp(mix(previousVelocity, liveVelocity, velocityResponse), vec2<f32>(-0.08), vec2<f32>(0.08));

    // Advect sample position
    let advUV = clamp(uv - vel * 1.8, vec2<f32>(0.0), vec2<f32>(1.0));
    let carried = textureSampleLevel(readTexture, u_sampler, advUV, 0.0);

    // Silk filtering (soft, luxurious)
    let silkBlend = mix(input.rgb, carried.rgb, 0.55 + silk * 0.35);

    // Subtle weave texture
    let weaveBand = min(u32(clamp(uv.y, 0.0, 0.9999) * 8.0), 7u);
    let weaveVoice = plasmaBuffer[(weaveBand % 8u) + 1u].x;
    let weave = (valueNoise(uv * 48.0 + time * 0.1) - 0.5)
        * 0.035 * silk * (1.0 + weaveVoice * 0.35);
    var col = silkBlend + weave;

    // Gentle color breathing from audio
    let breathColor = vec3<f32>(0.98, 0.96, 0.92) + vec3<f32>(0.04, 0.02, -0.03) * sin(time * 0.6 + mids * 1.2) * breath * 0.3;
    col *= breathColor;
    col = max(col, vec3<f32>(0.0));

    // Semantic alpha — higher where flow is active (beautiful motion trails when stacked)
    let flowEnergy = length(vel) * 28.0 + breath * 0.4;
    let semantic_alpha = clamp(0.62 + flowEnergy * 0.55, 0.5, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, semantic_alpha));

    // Store velocity field for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(vel.x, vel.y, flowEnergy, semantic_alpha));

    let d = clamp(0.25 + flowEnergy * 0.35, 0.0, 0.92);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
