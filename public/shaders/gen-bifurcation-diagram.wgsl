// ═══════════════════════════════════════════════════════════════════
//  Bifurcation Diagram
//  Category: generative
//  Features: mathematical, chaos, visualization, audio-parameter, mouse-exploration, temporal-evolution, density-color
//  Complexity: Medium
//  Updated: 2026-05-31
//  By: Grok (visual flourish pass — richer color, motion, and interactive depth)
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

// Logistic map: x_{n+1} = r * x_n * (1 - x_n)
fn logisticMap(r: f32, x0: f32, iterations: i32) -> f32 {
    var x = x0;
    for (var i: i32 = 0; i < iterations; i++) {
        x = r * x * (1.0 - x);
        if (x < 0.0 || x > 1.0) { break; }
    }
    return x;
}

// Multiple iterations to get attractor points
fn getAttractorPoints(r: f32, iterations: i32, skip: i32) -> vec4<f32> {
    var x = 0.5; // Initial condition
    
    // Skip transient
    for (var i: i32 = 0; i < skip; i++) {
        x = r * x * (1.0 - x);
    }
    
    // Collect attractor points
    var points = vec4<f32>(0.0);
    for (var i: i32 = 0; i < 4; i++) {
        x = r * x * (1.0 - x);
        points[i] = x;
    }
    
    return points;
}

// Color schemes
fn colorThermal(t: f32) -> vec3<f32> {
    // Black -> Red -> Yellow -> White
    if (t < 0.33) {
        return mix(vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), t / 0.33);
    } else if (t < 0.66) {
        return mix(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(1.0, 1.0, 0.0), (t - 0.33) / 0.33);
    } else {
        return mix(vec3<f32>(1.0, 1.0, 0.0), vec3<f32>(1.0, 1.0, 1.0), (t - 0.66) / 0.34);
    }
}

fn colorRainbow(t: f32) -> vec3<f32> {
    let hue = t;
    let sat = 0.8;
    let light = 0.5;
    
    let c = (1.0 - abs(2.0 * light - 1.0)) * sat;
    let x = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
    let m = light - c * 0.5;
    
    var r = 0.0; var g = 0.0; var b = 0.0;
    if (hue < 1.0/6.0) { r = c; g = x; }
    else if (hue < 2.0/6.0) { r = x; g = c; }
    else if (hue < 3.0/6.0) { g = c; b = x; }
    else if (hue < 4.0/6.0) { g = x; b = c; }
    else if (hue < 5.0/6.0) { r = x; b = c; }
    else { r = c; b = x; }
    
    return vec3<f32>(r + m, g + m, b + m);
}

fn colorOcean(t: f32) -> vec3<f32> {
    return mix(vec3<f32>(0.0, 0.05, 0.2), vec3<f32>(0.5, 0.8, 1.0), t);
}

fn colorFire(t: f32) -> vec3<f32> {
    return mix(vec3<f32>(0.2, 0.0, 0.0), vec3<f32>(1.0, 0.8, 0.2), pow(t, 0.5));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Lyapunov exponent approximation
fn lyapunov(r: f32) -> f32 {
    var x = 0.5;
    var sum = 0.0;
    let n = 100;
    
    for (var i: i32 = 0; i < n; i++) {
        x = r * x * (1.0 - x);
        let derivative = abs(r * (1.0 - 2.0 * x));
        if (derivative > 0.0001) {
            sum += log(derivative);
        }
    }
    
    return sum / f32(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x * 2.5;
    
    // Parameters - safe randomization
    let rPosition = mix(2.8, 4.0, u.zoom_params.x);
    let zoomLevel = mix(1.0, 50.0, u.zoom_params.y * u.zoom_params.y);
    let iterationCount = i32(mix(50.0, 200.0, u.zoom_params.z));
    let colorScheme = i32(u.zoom_params.w * 3.99);
    
    // R range with zoom and pan
    let rCenter = rPosition;
    let rRange = 1.2 / zoomLevel;
    let rMin = max(2.8, rCenter - rRange * 0.5);
    let rMax = min(4.0, rCenter + rRange * 0.5);
    
    // Mouse exploration locally bends the r/x window around the visible cursor
    // without replacing the saved R Position or Zoom controls.
    let mouseRaw = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let hasSpring = arrayLength(&extraBuffer) >= 139u;
    var mouseUv = mouseRaw; var springVel = vec2<f32>(0.0); var lastTime = t; var initialized = false;
    if (hasSpring) { mouseUv = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]); lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5; }
    if (!initialized) { mouseUv = mouseRaw; springVel = vec2<f32>(0.0); }
    let dt = select(0.0, clamp(t - lastTime, 0.0, 0.05), initialized);
    let omega = 8.0; let springDecay = exp(-omega * dt); let sdelta = mouseUv - mouseRaw; let temp = (springVel + omega * sdelta) * dt;
    springVel = (springVel - omega * temp) * springDecay; mouseUv = mouseRaw + (sdelta + temp) * springDecay;
    if (hasSpring && global_id.x == 0u && global_id.y == 0u) { extraBuffer[133] = mouseUv.x; extraBuffer[134] = mouseUv.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y; extraBuffer[137] = t; extraBuffer[138] = 1.0; }
    let mouseDelta = (uv - mouseUv) * vec2<f32>(resolution.x / resolution.y, 1.0);
    let mouseLens = exp(-dot(mouseDelta, mouseDelta) * 18.0) * (0.18 + u.zoom_config.w * 0.52);
    let baseR = mix(rMin, rMax, uv.x);
    let r = mix(baseR, mix(rMin, rMax, mouseUv.x), mouseLens * 0.42);
    let targetX = mix(uv.y, mouseUv.y, mouseLens * 0.24);

    // One bounded logistic loop now computes density and Lyapunov behavior;
    // the former unused attractor call plus separate 100-step Lyapunov pass
    // duplicated a large fraction of the per-pixel work.
    let skip = 80;
    var density = 0.0;
    let binSize = 0.5 / resolution.y;
    var x = 0.5;
    var lyapSum = 0.0;
    let totalIterations = skip + iterationCount;
    for (var i: i32 = 0; i < 280; i++) {
        if (i >= totalIterations) { break; }
        x = r * x * (1.0 - x);
        if (i >= skip) {
            let dist = abs(x - targetX);
            if (dist < binSize) {
                density += 1.0 - dist / binSize;
            }
            let derivative = abs(r * (1.0 - 2.0 * x));
            if (derivative > 0.0001) {
                lyapSum += log(derivative);
            }
        }
    }
    density = min(density / 10.0, 1.0);
    let lyap = lyapSum / max(f32(iterationCount), 1.0);
    
    // === Visual Flourish: Richer, audio-reactive coloring ===
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    var col = vec3<f32>(0.0);
    
    if (density > 0.01) {
        switch (colorScheme) {
            case 0: { col = colorThermal(density); }
            case 1: { col = colorRainbow(density); }
            case 2: { col = colorOcean(density); }
            case 3: { col = colorFire(density); }
            default: { col = colorThermal(density); }
        }
        
        // Audio-reactive color and brightness
        let audioBoost = 0.7 + 0.6 * density + bass * 0.4 + mids * 0.25;
        col = col * audioBoost;
        
        // Treble adds fine spectral detail / shimmer
        let shimmer = sin(density * 40.0 + t * 5.0) * treble * 0.15;
        col += vec3<f32>(0.1, 0.15, 0.2) * max(shimmer, 0.0);
    } else {
        // Background with subtle audio-reactive nebula
        let nebula = sin(uv.y * 8.0 + t * 0.3) * 0.02;
        col = vec3<f32>(0.015 + nebula * bass, 0.018, 0.025 + nebula * treble * 0.5);
    }
    
    // Highlight periodic windows
    if (lyap < 0.0) {
        // Periodic region - subtle glow
        let periodGlow = smoothstep(0.0, -0.5, lyap) * 0.1;
        col = col + vec3<f32>(0.2, 0.3, 0.5) * periodGlow;
    } else {
        // Chaotic region - warm tint
        let chaosTint = smoothstep(0.0, 0.5, lyap) * 0.1;
        col = col + vec3<f32>(0.5, 0.2, 0.1) * chaosTint;
    }

    // A fast chaos scanner races through the parameter axis, illuminating
    // derivative-rich branches without changing the logistic-map geometry.
    let scanPhase = fract(uv.x * 1.8 - t * (1.1 + bass * 1.8));
    let scanFront = exp(-abs(scanPhase - 0.5) * 34.0) *
                    smoothstep(-0.35, 0.55, lyap) * (0.25 + mids * 0.5);
    col += mix(vec3<f32>(1.1, 0.15, 0.95), vec3<f32>(0.15, 1.2, 0.55), treble) * scanFront;

    // Click wavefronts sweep across the diagram as stylized analysis overlays.
    var clickWave = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = t - ripple.z;
        if (age >= 0.0 && age < 1.5) {
            let delta = (uv - ripple.xy) * vec2<f32>(resolution.x / resolution.y, 1.0);
            clickWave = max(clickWave, exp(-abs(length(delta) - age * 0.72) * 64.0) * exp(-age * 1.8));
        }
    }
    col += vec3<f32>(0.95, 0.25, 1.35) * clickWave * (0.55 + treble * 0.7);
    
    // Grid lines for reference
    let gridX = fract(uv.x * 10.0);
    let gridY = fract(uv.y * 10.0);
    if (gridX < 0.02 || gridY < 0.02) {
        col = col * 0.8 + vec3<f32>(0.1) * 0.2;
    }
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    col *= vignette;
    
    // Derivative-aligned history produces branch trails rather than a static
    // afterimage. Energy is bounded before storage.
    let derivativeFlow = clamp(r * (1.0 - 2.0 * x), -4.0, 4.0);
    let historyVelocity = vec2<f32>(2.0 + bass * 3.0, derivativeFlow * (0.8 + u.zoom_params.y * 1.8));
    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
    let historyCoord = clamp(coord - vec2<i32>(historyVelocity), vec2<i32>(0), maxCoord);
    let history = textureLoad(dataTextureC, historyCoord, 0).rgb;
    let hdrColor = clamp(col + history * (0.2 + density * 0.18), vec3<f32>(0.0), vec3<f32>(4.0));
    let alpha = clamp(density * 0.78 + scanFront * 0.3 + clickWave * 0.28 + 0.025, 0.025, 0.96);
    let depth = clamp(density * 0.68 + smoothstep(-0.4, 0.6, lyap) * 0.18 + scanFront * 0.12, 0.0, 1.0);
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
    textureStore(writeTexture, coord, vec4<f32>(acesToneMap(hdrColor * 1.25), alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
