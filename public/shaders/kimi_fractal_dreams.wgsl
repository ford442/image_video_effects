// ═══════════════════════════════════════════════════════════════════
//  Kimi Fractal Dreams
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-07-26 (Batch 15)
//   - NaN-guarded cdiv; spring-damped Julia morph (extraBuffer[133..136])
//   - Click-ripple zoom pulses; IQ orbit-trap palette; per-bin treble filaments
//   - Honest slider side-effects (labels now match real visual controls)
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

// Kimi Fractal Dreams - Multi-layer fractal with orbit traps

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Complex number operations
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    // Epsilon guard: when z ~= (-0.01, -0.01) the denominator collapses to
    // zero and the raw formula emitted inf/NaN pixels. Clamping the squared
    // magnitude preserves behavior everywhere else (denom >= 1e-4 normally).
    let denom = max(b.x * b.x + b.y * b.y, 1e-4);
    return vec2<f32>((a.x * b.x + a.y * b.y) / denom, (a.y * b.x - a.x * b.y) / denom);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// IQ cosine palette, keyed on the orbit-trap distance for banded filaments
fn iqCosinePalette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let cp = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(6.28318 * (cp * t + d));
}

// HSL -> RGB (kept from the original color path)
fn hslToRgb(hue: f32, sat: f32, light: f32) -> vec3<f32> {
    let c1 = (1.0 - abs(2.0 * light - 1.0)) * sat;
    let x = c1 * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
    let m = light - c1 * 0.5;

    var rgb: vec3<f32>;
    if (hue < 1.0 / 6.0) { rgb = vec3<f32>(c1, x, 0.0); }
    else if (hue < 2.0 / 6.0) { rgb = vec3<f32>(x, c1, 0.0); }
    else if (hue < 3.0 / 6.0) { rgb = vec3<f32>(0.0, c1, x); }
    else if (hue < 4.0 / 6.0) { rgb = vec3<f32>(0.0, x, c1); }
    else if (hue < 5.0 / 6.0) { rgb = vec3<f32>(x, 0.0, c1); }
    else { rgb = vec3<f32>(c1, 0.0, x); }
    return rgb + vec3<f32>(m);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let rawTime = u.config.x;
    let time = rawTime * 0.1;

    // Audio reactivity: bass pulses the zoom, mids cycle color, treble glows orbit traps
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse interaction
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Aspect correct coordinates
    let aspect = resolution.x / resolution.y;
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    // Mouse controls Julia set constant
    var mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= aspect;
    let targetC = mix(vec2<f32>(-0.8, 0.156), mousePos, 0.5);

    // ── Spring-damper Julia morph ────────────────────────────────────
    // Critically-damped spring glides c toward the mouse target instead of
    // snapping at a fixed 0.5 lerp. Persistent state: extraBuffer[133..136]
    // = (c.x, c.y, v.x, v.y). Only invocation (0,0) integrates; every other
    // invocation just reads the latest glide position (benign race).
    if (global_id.x == 0u && global_id.y == 0u) {
        var springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (springPos.x == 0.0 && springPos.y == 0.0) {
            // First frame after zero-init: snap so the dream starts on-target.
            springPos = targetC;
            springVel = vec2<f32>(0.0, 0.0);
        }
        let dt = 0.016;
        let omega = 7.0;
        let accel = (targetC - springPos) * omega * omega - 2.0 * omega * springVel;
        springVel += accel * dt;
        springPos += springVel * dt;
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
    }
    let c = vec2<f32>(extraBuffer[133], extraBuffer[134]);

    // ── Click ripples: temporary zoom-pulse impulses ─────────────────
    // Each click ripple injects a decaying zoom pulse; spatial falloff keeps
    // the pulse strongest near the click point. Age decays the impulse.
    var zoomPulse = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let rp = u.ripples[ri];
        let age = rawTime - rp.z;
        if (age >= 0.0 && age < 2.5) {
            let strength = select(1.0, rp.w, rp.w > 0.001);
            let local = smoothstep(0.45, 0.0, length(uv - rp.xy));
            zoomPulse += exp(-age * 2.2) * (0.35 + 0.65 * local) * strength * 0.25;
        }
    }

    // ── Parameters (preset contract: ids/defaults/mapping unchanged) ──
    // Intensity: zoom (original) + honest glow/filament intensity gain
    let intensity = u.zoom_params.x;
    let glowGain = 0.5 + intensity;
    let zoom = (intensity * 3.0 + 0.5) * (1.0 + bass * 0.2 + zoomPulse);
    // Speed: iterations (original) + honest layer-rotation rate
    let speedParam = u.zoom_params.y;
    let iterations = i32(speedParam * 100.0) + 50;
    let orbitRate = 0.5 + speedParam;
    // Scale: color cycles (original) + honest orbit-trap radius scale
    let scaleParam = u.zoom_params.z;
    let colorCycles = (scaleParam * 5.0 + 1.0) * (1.0 + mids * 0.5);
    let trapRadius = 0.5 * (0.6 + scaleParam * 0.8);
    // Detail: complexity (original) + honest filament sharpness
    let detailParam = u.zoom_params.w;
    let complexity = detailParam * 2.0 + 0.5;
    let filamentSharp = 5.0 + detailParam * 9.0;

    // Zoom towards mouse
    p = (p - mousePos) / zoom + mousePos;

    // Multiple fractal layers
    var col = vec3<f32>(0.0);
    var totalWeight = 0.0;

    let layers = 3;
    for (var layer = 0; layer < layers; layer++) {
        let fi = f32(layer);
        // Layer orbit rate is Speed-driven (1.0x at the default 0.5)
        let layerC = c + vec2<f32>(cos(time * orbitRate + fi), sin(time * orbitRate + fi)) * 0.1;
        var z = p;

        var orbitTrap = 1000.0;
        var minRadius = 1000.0;

        let layerIter = iterations + layer * 20;
        // Per-bin treble: each layer listens to its own high-frequency bin
        let binGlow = plasmaBuffer[1u + u32(layer)].x;

        for (var i = 0; i < layerIter; i++) {
            // Burning Ship variant with Julia
            z = vec2<f32>(abs(z.x), abs(z.y));
            z = cmul(z, z) + layerC;

            // Additional complexity (cdiv is epsilon-guarded against NaN)
            if (complexity > 1.5) {
                z = z + cdiv(vec2<f32>(0.1, 0.0), z + vec2<f32>(0.01));
            }

            // Orbit traps
            let r = length(z);
            orbitTrap = min(orbitTrap, abs(r - trapRadius));
            minRadius = min(minRadius, r);

            if (r > 4.0) {
                // Smooth coloring
                let smoothIter = f32(i) - log2(log2(r)) + 4.0;

                // Color based on escape time and orbit trap
                let hue = fract(smoothIter * 0.01 * colorCycles + fi * 0.33);
                let sat = 0.8;
                let light = 0.5 + orbitTrap * 2.0;

                var layerCol = hslToRgb(hue, sat, light);

                // Orbit-trap palette: IQ cosine bands keyed on trap distance
                let trapT = orbitTrap * 2.0 + hue * 0.35 + time * 0.05;
                let palCol = iqCosinePalette(trapT);
                layerCol = mix(layerCol, palCol * (0.4 + light * 0.8), 0.45);

                // Glow from orbit trap (treble intensifies the filament glow)
                layerCol += vec3<f32>(1.0, 0.8, 0.6) * orbitTrap * 2.0
                          * (1.0 + treble * 1.5) * glowGain;

                // Treble filaments: per-bin high-hat energy lights the edges
                let filament = exp(-orbitTrap * filamentSharp);
                layerCol += iqCosinePalette(fi * 0.21 + time * 0.03) * filament
                          * (0.25 + treble * 1.2 + binGlow * 2.0) * glowGain;

                let weight = 1.0 / (1.0 + fi);
                col += layerCol * weight;
                totalWeight += weight;
                break;
            }
        }

        // Rotation for next layer (1.047 rad / 0.8 scale signature preserved;
        // Speed adds a gentle wobble around the base angle, zero at default)
        let rotAngle = 1.047 + (speedParam - 0.5) * 0.35 * sin(time * 0.6);
        let rot = vec2<f32>(
            p.x * cos(rotAngle) - p.y * sin(rotAngle),
            p.x * sin(rotAngle) + p.y * cos(rotAngle)
        );
        p = rot * 0.8;
    }

    if (totalWeight > 0.0) {
        col /= totalWeight;
    } else {
        col = vec3<f32>(0.02, 0.0, 0.05);
    }

    // Mouse glow
    let dist = length(uv - mouse);
    col += vec3<f32>(1.0, 0.9, 0.7) * smoothstep(0.3, 0.0, dist) * mouseDown * 0.5;

    // Post-processing
    col = pow(col, vec3<f32>(0.9));
    col *= 1.2;
    // Subtle hash dither breaks up palette banding in smooth regions
    col += (hash(uv * resolution) - 0.5) * 0.004;

    // Alpha: fractal escape coverage + glow luminance, never flat 1.0
    let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(smoothstep(0.0, 1.0, totalWeight) * 0.5 + lum * 0.6, 0.0, 1.0);
    let out = vec4<f32>(acesToneMap(col * 1.1), alpha);

    // Depth: brighter escaped filaments read as nearer
    let depth = clamp(lum, 0.0, 1.0);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
