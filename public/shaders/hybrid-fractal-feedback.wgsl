// ═══════════════════════════════════════════════════════════════════
//  Hybrid Fractal Feedback
//  Category: hybrid
//  Features: advanced-alpha, fractal, feedback, hybrid
//  Complexity: High
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Zoom, y=Feedback, z=RGBDelay, w=ColorCycle
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 3: Accumulative Alpha
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.08) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    return vec4<f32>(color, totalAlpha);
}

// Complex multiplication
fn complexMul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let rawMouse = u.zoom_config.yz;

    // Honor the JSON control contract. These mappings were previously shifted:
    // every label drove a different internal behavior.
    let zoomControl = u.zoom_params.x;
    let feedbackControl = u.zoom_params.y;
    let rgbDelay = u.zoom_params.z;
    let colorCycle = u.zoom_params.w;
    let accumulationRate = mix(0.15, 0.50, feedbackControl);
    let fractalIter = 45;
    let zoom = 1.0 + zoomControl * 1.5;
    let feedback = mix(0.15, 0.65, feedbackControl);

    // Smooth the Julia parameter with a critically damped spring in safe state.
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
            let omega = 6.0;
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

    let current = textureLoad(readTexture, coord, 0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Clicks locally kick the complex Julia parameter at normalized ripple
    // positions rather than replacing the persistent feedback state.
    let aspect = resolution.x / max(resolution.y, 0.001);
    var clickC = vec2<f32>(0.0);
    var clickGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        let safeAge = max(age, 0.0);
        let live = step(0.0, age) * (1.0 - step(1.8, age));
        let rd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
        let local = (1.0 - smoothstep(0.0, 0.45 + safeAge * 0.08, rd)) * exp(-safeAge * 1.5) * live;
        clickC += (rp.xy - 0.5) * local * 0.35;
        clickGlow = max(clickGlow, local);
    }

    // Julia fractal — mouse steers c-parameter, bass adds breathing
    let cBase = vec2<f32>(cos(time * 0.2) * 0.7, sin(time * 0.3) * 0.3);
    let cMouse = (mouse - 0.5) * 1.4;
    let c = mix(cBase, cMouse, 0.5) * (1.0 + bass * 0.1) + clickC;
    let z = (uv - 0.5) * zoom * 2.0;
    
    var iter = 0;
    var zCurrent = z;
    for (var i: i32 = 0; i < fractalIter; i++) {
        zCurrent = complexMul(zCurrent, zCurrent) + c;
        if (dot(zCurrent, zCurrent) > 4.0) {
            iter = i;
            break;
        }
        iter = i;
    }
    
    let fractalValue = f32(iter) / f32(fractalIter);
    // Bounded cosine palette with per-region FFT shimmer. Only valid spectrum
    // bins 1..8 are addressed; the old 256-entry palette assumption was unsafe.
    let palettePhase = fract(fractalValue * PHI + time * mix(0.02, 0.18, colorCycle));
    let palette = 0.55 + 0.45 * cos(TAU * (palettePhase + vec3<f32>(0.00, 0.33, 0.67)));
    let regionBin = (u32(floor(uv.x * 4.0)) + u32(floor(uv.y * 4.0)) * 3u) % 8u + 1u;
    let fftVoice = plasmaBuffer[regionBin].x;
    let fractalColor = palette * fractalValue * (0.7 + bass * 0.35 + mids * 0.15 + fftVoice * 0.2 + clickGlow * 0.2);
    
    // The RGB-delay slider now samples distinct temporal offsets for red/blue.
    let delayAngle = time * 0.25 + fractalValue * TAU;
    let delayVec = vec2<f32>(cos(delayAngle) / aspect, sin(delayAngle)) * rgbDelay * (0.002 + treble * 0.004);
    let prevR = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + delayVec, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let prevB = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - delayVec, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let delayedPrev = vec3<f32>(prevR, prev.g, prevB);
    let blended = mix(delayedPrev, fractalColor, feedback);
    let newAlpha = fractalValue;
    
    let accumulated = accumulativeAlpha(blended, newAlpha, prev.rgb, prev.a, accumulationRate);
    
    textureStore(dataTextureA, coord, accumulated);
    
    // Blend feedback over current input, preserving base transparency
    let blend = accumulated.a;
    let finalColor = mix(current.rgb, accumulated.rgb, blend);
    let finalAlpha = mix(current.a, 1.0, blend * 0.7);
    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, finalAlpha));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthOut = clamp(depth - fractalValue * 0.035 - clickGlow * 0.02, 0.0, 1.0);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0, 0, 0.0));
}
