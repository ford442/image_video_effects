// ═══════════════════════════════════════════════════════════════════
//  Fiber Optic Weave
//  Category: interactive-mouse
//  Features: woven-fibers, mouse-pluck, audio-reactive, signal-pulse, upgraded-rgba
//  Complexity: Medium
//  Phase B / Interactivist
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Density, y=Glow, z=Force, w=Fray
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 1.0);

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params — bass amplifies fiber pulse
    let density = u.zoom_params.x * 100.0 + 10.0;
    let glow = u.zoom_params.y * (1.0 + bass * 0.4);
    let force = u.zoom_params.z;
    let fray = u.zoom_params.w;

    let rawMouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // A soft spring gives the weave some mass. State is restricted to the
    // persistent-safe range [133..138].
    let hasSpringState = arrayLength(&extraBuffer) > 138u;
    var mouse = rawMouse;
    if (hasSpringState && extraBuffer[138] > 0.5) {
        mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
        var springPos = mouse;
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] <= 0.5) {
            springPos = rawMouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
            let omega = 7.0;
            let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
    }

    // Fiber strips
    let stripIndex = floor(uv.y * density);
    let stripUV = fract(uv.y * density);
    let isOdd = (stripIndex % 2.0) >= 1.0;

    // Mouse pluck — close to fiber centerline = pluck wave (golden-ratio harmonic per fiber)
    let stripCenter = (stripIndex + 0.5) / density;
    let dy = abs(uv.y - stripCenter);
    let dxToMouse = abs(uv.x - mouse.x);
    let yToMouseStrip = abs(stripIndex - floor(mouse.y * density));
    let pluckGate = step(yToMouseStrip, 1.5);  // pluck nearby strips
    let pluck = exp(-dxToMouse * 5.0) * pluckGate * (mouseDown * 0.6 + 0.2);

    // Clicks launch one-shot pulses along the selected fibers.
    var clickPluck = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        let safeAge = max(age, 0.0);
        let live = step(0.0, age) * (1.0 - step(1.8, age));
        let clickedStrip = floor(rp.y * density);
        let stripGate = 1.0 - step(1.5, abs(stripIndex - clickedStrip));
        let travel = abs(uv.x - rp.x) * aspect;
        let pulseBand = 1.0 - smoothstep(0.012, 0.05, abs(travel - safeAge * 0.42));
        clickPluck = max(clickPluck, pulseBand * stripGate * exp(-safeAge * 1.4) * live);
    }

    // Weaving displacement (alternating, with bass-driven sin wave)
    let weavePhase = uv.y * 20.0 + time * 2.0 * (1.0 + bass * 0.3) + stripIndex * PHI;
    let weaveAmt = sin(weavePhase) * 0.005 * fray;
    var offsetX = select(-weaveAmt, weaveAmt, isOdd);
    offsetX += pluck * sin((uv.x - mouse.x) * 50.0 + time * 8.0) * 0.02;
    offsetX += clickPluck * sin((uv.x - mouse.x) * 70.0 - time * 10.0) * 0.025 * force;

    // Mouse repulsion (force param)
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dM = length(distVec);
    let repulsionStr = exp(-dM * dM * 12.0) * force * 0.2;
    let dir = distVec / max(dM, 1e-4);
    offsetX += dir.x * repulsionStr;

    let finalUV = clamp(vec2<f32>(uv.x + offsetX, uv.y), vec2<f32>(0.0), vec2<f32>(1.0));
    var col = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Fiber edge glow (pseudo cylindrical lighting)
    let edge = abs(stripUV - 0.5) * 2.0;
    let glowFactor = smoothstep(0.7, 1.0, edge) * glow;
    let lum = dot(col.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Signal pulse traveling along fiber — palette-mapped, golden-spaced per strip
    let pulsePos = fract(time * 0.4 + stripIndex * (PHI - 1.0));
    let pulseDist = abs(uv.x - pulsePos);
    let pulseGlow = exp(-pulseDist * 30.0) * (0.4 + bass * 0.6);
    let fiberBin = (u32(abs(stripIndex)) % 8u) + 1u;
    let fiberVoice = plasmaBuffer[fiberBin].x;
    let pulseColor = mix(vec3<f32>(0.15, 0.65, 1.0), vec3<f32>(1.0, 0.35, 0.8), fract(stripIndex * (PHI - 1.0)));

    // Add fiber glow + signal pulse + cyan tint baseline
    let glowColor = vec3<f32>(0.2, 0.8, 1.0) * glowFactor * lum
                  + pulseColor * (pulseGlow + clickPluck * 0.8) * glow * (1.0 + fiberVoice * 0.35);
    col = vec4<f32>(col.rgb + glowColor, col.a);

    // Semantic alpha: glow + pluck + signal pulse drive fiber compositing weight
    let alpha = clamp(0.5 + glowFactor * 0.3 + pulseGlow * 0.4 + max(pluck, clickPluck) * 0.2 + lum * 0.1, 0.0, 1.0);

    let peak = max(max(col.r, col.g), col.b);
    let finalRGB = max(col.rgb, vec3<f32>(0.0)) * min(1.0, 1.8 / max(peak, 0.001));

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r;
    let depthOut = clamp(depth - (glowFactor * 0.015 + max(pluck, clickPluck) * 0.03), 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
