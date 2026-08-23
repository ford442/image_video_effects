// ═══════════════════════════════════════════════════════════════════
//  Fire Smoke Volumetric
//  Category: simulation
//  Features: advanced-alpha, fire, smoke, volumetric,
//            chromatic-temperature, temporal-smoke, audio-turbulence,
//            worley-embers, treble-edge-flicker, feedback-clamped
//  Complexity: High
//  Upgraded: 2026-08-23 (Batch 68 stateful smoke advection and ignition)
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ── Hashes ────────────────────────────────────────────────────────
fn hash(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 54.53))) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}

// ── Worley (cellular) noise — nearest feature point distance ──────
fn worley(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    var d = 1.0;
    for (var oy = -1; oy <= 1; oy++) {
        for (var ox = -1; ox <= 1; ox++) {
            let g = vec2<f32>(f32(ox), f32(oy));
            let o = hash22(i + g);
            d = min(d, length(g + o - f));
        }
    }
    return d;
}

// ── Volumetric helpers ────────────────────────────────────────────
fn physicalTransmittance(baseColor: vec3<f32>, opticalDepth: f32, absorptionCoeff: vec3<f32>) -> vec3<f32> {
    let transmittance = exp(-absorptionCoeff * opticalDepth);
    return baseColor * transmittance;
}

fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    return 1.0 - exp(-density * thickness);
}

fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    // Higher depth weight pushes the far-layer floor darker (deeper occlusion)
    let depthFloor = mix(0.45, 0.15, depthWeight);
    let depthAlpha = mix(depthFloor, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> {
    return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
}

// ── Ember field: rising worley cells, tinted by temperature ───────
fn emberField(uv: vec2<f32>, time: f32, turbOffset: f32, fireShape: f32, tempColor: vec3<f32>, intensity: f32) -> vec3<f32> {
    // Cells scroll upward; turbulence bends the ember column sideways
    let emberUV = vec2<f32>(uv.x * 9.0 + turbOffset * 0.5, uv.y * 9.0 - time * 1.6);
    let w = worley(emberUV);
    let core = pow(clamp(1.0 - w, 0.0, 1.0), 14.0);
    // Per-cell twinkle so sparks pulse as they rise
    let twinkle = 0.6 + 0.4 * sin(time * 7.0 + hash21(floor(emberUV)) * TAU);
    // Restrained: embers live inside the flame and fade toward the top
    let mask = fireShape * smoothstep(0.95, 0.25, uv.y);
    let embers = core * twinkle * mask * intensity * 0.35;
    return tempColor * embers;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let pixel = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let mouseDown = u.zoom_config.w;

    let hasSpring = arrayLength(&extraBuffer) >= 139u;
    var mouse = rawMouse;
    var springVel = vec2<f32>(0.0);
    var lastTime = time;
    var initialized = false;
    if (hasSpring) {
        mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        lastTime = extraBuffer[137];
        initialized = extraBuffer[138] > 0.5;
    }
    if (!initialized) { mouse = rawMouse; springVel = vec2<f32>(0.0); }
    let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
    let omega = 9.0;
    let springDecay = exp(-omega * dt);
    let springDelta = mouse - rawMouse;
    let springTemp = (springVel + omega * springDelta) * dt;
    springVel = (springVel - omega * springTemp) * springDecay;
    mouse = rawMouse + (springDelta + springTemp) * springDecay;
    if (hasSpring && global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = mouse.x; extraBuffer[134] = mouse.y;
        extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
        extraBuffer[137] = time; extraBuffer[138] = 1.0;
    }

    // ── Slider params (saved-preset contract: ids/defaults unchanged) ──
    let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
    let dM = length((uv - mouse) * aspectVec);
    let mouseHeat = exp(-dM * dM * 8.0) * (mouseDown * 0.6 + 0.2);
    // p1 Fire Intensity → core heat / brightness scale
    let fireIntensity = u.zoom_params.x * 2.0 * (1.0 + bass * 0.4 + mouseHeat * 0.5);
    // p2 Smoke Density → soot density AND volumetric slab thickness
    let smokeDensity = u.zoom_params.y;
    let slabThickness = 0.6 + smokeDensity * 2.4;
    // p3 Depth Weight → strength + contrast of depth-layered occlusion
    let depthWeight = u.zoom_params.z;
    // p4 Turbulence → flame-silhouette distortion amplitude, crackled by treble
    let edgeFlicker = 1.0 + treble * 0.8;
    let turbulence = u.zoom_params.w * (1.0 + bass * 0.3) * edgeFlicker;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Flame silhouette: animated turbulence distorts the vertical falloff
    let n = hash(vec3<f32>(uv * 50.0, time * 5.0));
    var ignition = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i]; let age = time - ripple.z;
        if (age < 0.0 || age > 2.4) { continue; }
        let rippleDist = length((uv - ripple.xy) * aspectVec);
        ignition += exp(-pow((rippleDist - age * 0.22) * 30.0, 2.0)) * (1.0 - age / 2.4);
    }
    let baseFireShape = smoothstep(0.3, 0.7, 1.0 - uv.y + n * turbulence);
    let fireShape = clamp(baseFireShape + mouseHeat * 0.45 + ignition * 0.75, 0.0, 1.0);
    let density = fireShape * smokeDensity;

    // Chromatic temperature gradient: hot core = white-yellow, cool edges = red-orange
    let temp = uv.y * fireIntensity;
    let fireR = mix(1.0, 0.9, temp) * (1.0 + treble * 0.2);
    let fireG = mix(0.8, 0.3, temp) * (1.0 + mids * 0.2);
    let fireB = mix(0.1, 0.05, temp) * (1.0 + bass * 0.1);
    let tempColor = vec3<f32>(fireR, fireG, fireB);
    let fireColor = tempColor * fireShape * (0.5 + fireIntensity * 0.5);

    let smokeColor = vec3<f32>(0.3, 0.3, 0.35) * density;
    let effectColor = mix(smokeColor, fireColor, fireShape);

    // Worley-noise ember sparks riding the flame, tinted by the same gradient
    let emberColor = emberField(uv, time, turbulence, fireShape, tempColor, fireIntensity);

    // Exact-load semi-Lagrangian smoke advection from authoritative C state.
    let historyDims = vec2<i32>(textureDimensions(dataTextureC));
    let curl = vec2<f32>(sin(uv.y * 13.0 + time), cos(uv.x * 11.0 - time * 0.7));
    let advectedUV = clamp(uv + vec2<f32>(curl.x * 0.004, 0.008 + curl.y * 0.002) * turbulence - springVel * mouseHeat * 0.018, vec2<f32>(0.0), vec2<f32>(1.0));
    let prevState = textureLoad(dataTextureC, historyCoord(advectedUV, historyDims), 0);
    let prevSmoke = prevState.rgb;
    let decay = 0.92 + smokeDensity * 0.04;
    // Feedback stability: clamp accumulation pre-write at 1.2 (luma-echo-warp lesson)
    let decayedPrev = min(prevSmoke * decay, vec3<f32>(1.2));
    let smokeBlend = clamp(0.18 + bass * 0.04 + smokeDensity * 0.18, 0.0, 0.65);
    let persistentSmoke = mix(effectColor, decayedPrev, smokeBlend);

    // Physical transmittance through the smoke slab
    let opticalDepth = density * (1.0 + turbulence) * slabThickness;
    let absorptionCoeff = vec3<f32>(0.5, 0.6, 0.7);
    let transmitted = physicalTransmittance(persistentSmoke + emberColor, opticalDepth, absorptionCoeff);

    // Depth-layered volumetric alpha + restrained ember alpha contribution
    let volAlpha = volumetricAlpha(density, slabThickness);
    let effectAlpha = volAlpha * depthLayeredAlpha(uv, depthWeight);
    let emberAlpha = clamp(dot(emberColor, vec3<f32>(0.2126, 0.7152, 0.0722)) * 0.6, 0.0, 0.25);
    let combinedAlpha = clamp(effectAlpha + emberAlpha + ignition * 0.25, 0.0, 1.0);

    let finalColor = mix(baseColor.rgb, transmitted, combinedAlpha);
    let finalAlpha = mix(baseColor.a, 1.0, combinedAlpha * 0.7);

    textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(finalColor * 1.1), finalAlpha));
    // dataTextureA feeds next frame's dataTextureC: write the clamped smoke state
    let smokeState = min(persistentSmoke, vec3<f32>(1.2));
    textureStore(dataTextureA, pixel, vec4<f32>(smokeState, clamp(density + ignition * 0.3, 0.0, 1.2)));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
