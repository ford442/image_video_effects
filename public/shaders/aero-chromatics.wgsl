// ═══════════════════════════════════════════════════════════════════
//  Aero Chromatics
//  Category: simulation
//  Features: mouse-driven, depth-aware, audio-reactive
//  Complexity: Medium
//  Chunks From: aero-chromatics
//  Created: 2026-05-31
//  By: Copilot CLI (tactical swarm)
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Aero Chromatics
// P1: Wind Speed / Force
// P2: Decay Rate (Tail length)
// P3: Chromatic Split (Aberration amount)
// P4: Source Mix (How much new video is injected vs history)

// Sprung wind source state lives in extraBuffer[133..137]:
//   [133..134] = spring position (eased mouse)
//   [135..136] = spring velocity
//   [137] = initialized flag
// extraBuffer[0..4] is reserved and [5..132] belongs to the engine FFT,
// so persistent shader state stays in [133..255] only.

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;

    // Sprung wind source: a critically-damped spring chases the raw mouse
    // (the raw mouse stays the spring target), so the repulsion source
    // drifts like a slow fan instead of snapping to the cursor.
    // Every invocation computes the same local step; thread (0,0) persists it.
    let springK = 60.0;
    let springDamp = 2.0 * sqrt(springK); // critical damping
    let springDt = 0.016;
    var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        sPos = mouse; // wake up on the mouse, not the corner
        sVel = vec2<f32>(0.0);
    }
    let sAccel = (mouse - sPos) * springK - sVel * springDamp;
    sVel = sVel + sAccel * springDt;
    sPos = sPos + sVel * springDt;
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = sPos.x;
        extraBuffer[134] = sPos.y;
        extraBuffer[135] = sVel.x;
        extraBuffer[136] = sVel.y;
        extraBuffer[137] = 1.0;
    }
    let windSource = sPos;

    // Audio: bass energy from the spectrum buffer (previously never sampled)
    let bass = plasmaBuffer[1].x;

    // Params
    var windStrength = mix(0.5, 5.0, u.zoom_params.x);
    let decay = mix(0.8, 0.995, u.zoom_params.y);
    let chromaSplit = u.zoom_params.z * 0.02; // Small offset
    let sourceMix = mix(0.01, 0.2, u.zoom_params.w);

    // Bass gusts: the wind rides the low end, so drops push the smoke
    windStrength = windStrength * (1.0 + bass * 0.6);

    // Calculate drag based on current image luma
    // Lighter pixels = lighter weight = move faster (or vice versa?)
    // Let's say Light = Smoke = Fast. Dark = Heavy = Slow.
    let currentFrame = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(currentFrame.rgb, vec3<f32>(0.299, 0.587, 0.114));
    // Wind Vector
    // Base wind flows diagonally or follows mouse?
    // Let's make wind blow AWAY from mouse.
    let dVec = uv - windSource;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    // Mouse influence falls off
    let mouseInfluence = smoothstep(0.5, 0.0, dist);

    // Combine base drift with mouse wind
    // Base drift (upwards slightly like smoke)
    let baseWind = vec2<f32>(0.0, -0.001);
    let dVecAspect = dVec * vec2<f32>(aspect, 1.0);
    let mouseDirAspect = dVecAspect / max(dist, 0.0001);
    let mouseDir = mouseDirAspect / vec2<f32>(aspect, 1.0);
    let mouseWind = mouseDir * 0.01 * mouseInfluence * windStrength;

    // Final velocity for this pixel
    // If luma is high, it moves more.
    var velocity = (baseWind + mouseWind) * (luma * 2.0);

    // Click gust bursts: each live ripple adds a decaying radial gust from
    // its click point, so clicks blow puffs of smoke (~1.5s lifetime).
    // config.y = ripple COUNT.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleAge = u.config.x - ripple.z;
        if (rippleAge >= 0.0 && rippleAge < 1.5) {
            let rVec = uv - ripple.xy;
            let rVecAspect = vec2<f32>(rVec.x * aspect, rVec.y);
            let distR = length(rVecAspect);
            let dirR = (rVecAspect / max(distR, 0.0001)) / vec2<f32>(aspect, 1.0);
            let gustFalloff = smoothstep(0.35, 0.0, distR);
            velocity = velocity + dirR * 0.02 * exp(-rippleAge * 2.0) * gustFalloff;
        }
    }

    // Per-band flutter: 8 horizontal bands each wobble their velocity
    // perpendicular component, so the trail flickers across the spectrum.
    let band = min(u32(uv.y * 8.0), 7u);
    let flutter = plasmaBuffer[(band % 8u) + 1u].x * 0.003;
    let flowLen = max(length(velocity), 0.00001);
    let perpDir = vec2<f32>(-velocity.y, velocity.x) / flowLen;
    velocity = velocity + perpDir * flutter;

    // To simulate advection, we sample FROM (uv - velocity)
    // Because the smoke at (uv) came from (uv - velocity).

    // Chromatic Advection: Sample R, G, B from slightly different locations
    let offsetR = velocity * (1.0 + chromaSplit);
    let offsetG = velocity;
    let offsetB = velocity * (1.0 - chromaSplit);

    let prevR = textureSampleLevel(dataTextureC, u_sampler, uv - offsetR, 0.0).r;
    let prevG = textureSampleLevel(dataTextureC, u_sampler, uv - offsetG, 0.0).g;
    let prevB = textureSampleLevel(dataTextureC, u_sampler, uv - offsetB, 0.0).b;
    let historyColor = vec3<f32>(prevR, prevG, prevB);

    // Mix new source
    // If it's bright, we inject more source (smoke generation).
    // If dark, we inject less (transparent).
    let injectAmount = sourceMix * luma;

    var finalColor = mix(historyColor * decay, currentFrame.rgb, injectAmount);

    // Clamp
    finalColor = max(vec3<f32>(0.0), finalColor);

    // Sample depth for alpha calculation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Calculate luminance-based alpha
    let lumaFinal = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.7, 1.0, lumaFinal);
    let finalAlpha = mix(alpha * 0.8, alpha, depth);

    // Store to history (A) and Display (Write)
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));

    // Pass depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4(depth, 0.0, 0.0, 0.0));
}
