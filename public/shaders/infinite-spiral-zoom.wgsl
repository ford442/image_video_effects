// ═══════════════════════════════════════════════════════════════════════════════
//  Möbius–Droste Infinite Spiral
//  Category: interactive-mouse
//  Features: mouse-driven, click-reactive, audio-reactive, temporal, chromatic, depth-aware
//  Complexity: Very High
//  Upgraded: 2026-08-02 (Batch 30)
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0)  var u_sampler: sampler;
@group(0) @binding(1)  var readTexture: texture_2d<f32>;
@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3)  var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples:     array<vec4<f32>, 50>,
};

fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let d = max(dot(b, b), 0.000001);
    return vec2<f32>((a.x*b.x + a.y*b.y)/d, (a.y*b.x - a.x*b.y)/d);
}

fn soft_ceiling(color: vec3<f32>) -> vec3<f32> {
    let positive = max(color, vec3<f32>(0.0));
    let peak = max(positive.x, max(positive.y, positive.z));
    return positive / (1.0 + max(peak - 1.0, 0.0));
}

fn mobius(z: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>) -> vec2<f32> {
    return cdiv(cmul(a, z) + b, cmul(c, z) + d);
}

fn logPolarUV(z: vec2<f32>, zoomSpeed: f32, twist: f32, time: f32, branches: f32) -> vec2<f32> {
    let r = length(z);
    if (r < 0.0001) { return vec2<f32>(0.5); }
    var u_c = log(r) - time * zoomSpeed;
    var v_c = atan2(z.y, z.x) / 6.28318;
    v_c += u_c * twist * 0.15;
    return fract(vec2<f32>(u_c, v_c * branches));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let aspect = resolution.x / resolution.y;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth  = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let stateReady = extraBuffer[137] > 0.5;
    var mouse = select(rawMouse, vec2<f32>(extraBuffer[133], extraBuffer[134]), stateReady);
    var mouseVelocity = select(vec2<f32>(0.0), vec2<f32>(extraBuffer[135], extraBuffer[136]), stateReady);
    let dt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), stateReady);
    let omega = 9.0;
    mouseVelocity += ((rawMouse - mouse) * (omega * omega) - mouseVelocity * (2.0 * omega)) * dt;
    mouse += mouseVelocity * dt;

    let thetaTarget = time * 0.4 + bass * 0.8;
    let previousTheta = select(thetaTarget, extraBuffer[139], stateReady);
    let thetaState = mix(previousTheta, thetaTarget, clamp(dt * (2.5 + mids), 0.0, 1.0));
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = mouse.x;
        extraBuffer[134] = mouse.y;
        extraBuffer[135] = mouseVelocity.x;
        extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
        extraBuffer[139] = thetaState;
    }

    let zoomSpeed  = (u.zoom_params.x - 0.5) * 4.0 * (1.0 + bass * 0.2);
    let mobStrength= mix(0.0, 0.8, u.zoom_params.y) * (1.0 + mids * 0.15);
    let branches   = floor(u.zoom_params.z * 5.0) + 1.0;
    let chromatic  = u.zoom_params.w * 0.08 + treble * 0.03;

    var p = (uv - mouse) * vec2<f32>(aspect, 1.0);

    var clickTwist = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let radius = length(delta);
            clickTwist += sin(radius * 45.0 - age * 12.0) * exp(-radius * 6.0 - age * 1.5) * 0.45;
        }
    }

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let theta = thetaState + clamp(clickTwist, -0.8, 0.8);

    let bVec  = mobStrength * vec2<f32>(cos(theta), sin(theta));
    let cVec  = mobStrength * vec2<f32>(cos(-theta), sin(-theta));
    p = mobius(p, vec2<f32>(1.0, 0.0), bVec, cVec, vec2<f32>(1.0, 0.0));

    let twist  = (mids - 0.5) * 1.5 + 0.3;
    let uvBase = logPolarUV(p, zoomSpeed, twist, time, branches);
    let fftBin = (u32(fract(uvBase.y) * 8.0) % 8u) + 1u;
    let fftVoice = clamp(plasmaBuffer[fftBin].x, 0.0, 1.0);

    // Depth-scaled chromatic aberration
    let depthChroma = chromatic * (1.0 + depth * 0.5);
    let dtheta = depthChroma;
    let bR = (mobStrength + depthChroma * 0.1) * vec2<f32>(cos(theta + dtheta), sin(theta + dtheta));
    let cR = (mobStrength + depthChroma * 0.1) * vec2<f32>(cos(-theta - dtheta), sin(-theta - dtheta));
    var pR = (uv - mouse) * vec2<f32>(aspect, 1.0);
    pR = mobius(pR, vec2<f32>(1.0, 0.0), bR, cR, vec2<f32>(1.0, 0.0));
    let uvR = logPolarUV(pR, zoomSpeed, twist, time, branches);

    let bB = (mobStrength - depthChroma * 0.1) * vec2<f32>(cos(theta - dtheta), sin(theta - dtheta));
    let cB = (mobStrength - depthChroma * 0.1) * vec2<f32>(cos(-theta + dtheta), sin(-theta + dtheta));
    var pB = (uv - mouse) * vec2<f32>(aspect, 1.0);
    pB = mobius(pB, vec2<f32>(1.0, 0.0), bB, cB, vec2<f32>(1.0, 0.0));
    let uvB = logPolarUV(pB, zoomSpeed, twist, time, branches);

    let sR  = textureSampleLevel(readTexture, u_sampler, uvR,   0.0);
    let sG  = textureSampleLevel(readTexture, u_sampler, uvBase, 0.0);
    let sB2 = textureSampleLevel(readTexture, u_sampler, uvB,   0.0);
    var color = vec3<f32>(sR.r, sG.g, sB2.b);

    // Temporal trail persistence
    let prevCol = prev.rgb;
    color = mix(color, prevCol * 0.9, 0.04 + bass * 0.015);

    // Tile-seam edge glow
    let fx = fract(uvBase.x * 8.0);
    let fy = fract(uvBase.y * 8.0);
    let edgeGlow = smoothstep(0.48, 0.5, fx) * smoothstep(0.48, 0.5, fy) * 0.3 * (treble + fftVoice * 0.5);
    let finalColor = soft_ceiling(color + vec3<f32>(0.6, 0.3, 1.0) * edgeGlow);

    let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.8 + edgeGlow + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
