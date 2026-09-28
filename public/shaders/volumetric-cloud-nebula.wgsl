// ═══════════════════════════════════════════════════════════════════
//  Volumetric Cloud Nebula
//  Category: generative
//  Features: raymarched, volumetric, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: light-echo shell; absorbing dense cores; warp-flight star streaks
//  A packing: ACES display RGBA (rgb = trail colour, a = cloud coverage alpha) — C read as colour history
// ═══════════════════════════════════════════════════════════════════
//  Kept verbatim: fbm cloudDensity, cosine nebulaColor, Beer-Lambert raymarch integration,
//  warp-flight orbit camera, treble ionization flashes, advected history offset.
//  Sliders: x density, y colour shift, z camera distance, w extinction (w ALSO drives flowSpeed,
//  as at HEAD — that coupling is kept).
//  Floor fix: HEAD accumulated `finalCol + prev*0.85` (steady state ~6.7x, clamped to 5.5, no tone
//  map) so the frame was blown out. Now a bounded mix with the same 0.82+0.05*flow persistence
//  (same trail dynamics, normalized), ACES + HEAD's gamma encode on display.
//  Stars: HEAD hashed a continuously scrolling coordinate, so the "stars" were per-frame snow.
//  They are now fixed sky cells seen through the real orbit camera (Idea 3).

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

// Physical constants for nebula clouds
const SIGMA_T_NEBULA: f32 = 1.2;        // Nebula extinction
const SIGMA_S_NEBULA: f32 = 1.0;        // Scattering albedo ~0.83
const SIGMA_A_NEBULA: f32 = 0.2;        // Absorption (gas/dust)

// Idea 1 — light-echo shell constants (stateless periodic flash at the nebula centre)
const ECHO_PERIOD: f32 = 8.0;           // seconds between central flashes
const ECHO_C: f32 = 0.85;               // shell expansion speed (world units / s)
const ECHO_WIDTH: f32 = 0.35;           // shell thickness
// Idea 2 — density weight feeding the absorption term of the single-scatter albedo
const CORE_WEIGHT: f32 = 25.0;
// Idea 3 — sky star cells per radian, and the exposure window of the streak
const STAR_CELLS: f32 = 120.0;
const STREAK_DT: f32 = 0.008;
const STREAK_MAX: f32 = 1.6;            // cells; keeps the 3x3 neighbourhood sufficient

struct Cam {
  ro: vec3<f32>,
  fwd: vec3<f32>,
  right: vec3<f32>,
  up: vec3<f32>,
};

// Hash function for noise
fn hash3(p: vec3<f32>) -> vec3<f32> {
    let q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453);
}

// 3D Value noise
fn noise3d(p: vec3<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let f_smooth = f * f * (3.0 - 2.0 * f);

    let n = i.x + i.y * 157.0 + 113.0 * i.z;

    var result: f32 = 0.0;
    for (var z: i32 = 0; z < 2; z = z + 1) {
        for (var y: i32 = 0; y < 2; y = y + 1) {
            for (var x: i32 = 0; x < 2; x = x + 1) {
                let offset = vec3<f32>(f32(x), f32(y), f32(z));
                var h = hash3(i + offset);
                let w = abs(vec3<f32>(1.0) - offset - f);
                result = result + h.x * w.x * w.y * w.z;
            }
        }
    }
    return result;
}

// FBM (Fractal Brownian Motion) for clouds
fn fbmCloud(p: vec3<f32>) -> f32 {
    var value: f32 = 0.0;
    var amplitude: f32 = 0.5;
    var frequency: f32 = 1.0;

    for (var i: i32 = 0; i < 5; i = i + 1) {
        value = value + amplitude * noise3d(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// Cloud density function with volumetric properties
fn cloudDensity(p: vec3<f32>, time: f32, densityScale: f32, flowSpeed: f32) -> f32 {
    let animP = p + vec3<f32>(
        time * (0.18 + flowSpeed * 0.35),
        time * (0.08 + flowSpeed * 0.12),
        time * (0.12 + flowSpeed * 0.22)
    );

    var density = fbmCloud(animP * 0.8);

    // Create cloud-like shapes
    density = density - 0.3;
    density = max(density, 0.0);
    density = density * densityScale;

    // Falloff at edges
    let dist = length(p);
    density = density * smoothstep(6.0, 2.0, dist);

    return density;
}

// Nebula color palette (ionized gas emission)
fn nebulaColor(t: f32, shift: f32) -> vec3<f32> {
    let adjustedT = t + shift;
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);

    return a + b * cos(6.28318 * (c * adjustedT + d));
}

// Raymarch through clouds with volumetric integration
fn raymarchVolumetric(ro: vec3<f32>, rd: vec3<f32>, time: f32, densityScale: f32, colorShift: f32, flowSpeed: f32,
                      echoR: f32, echoAmp: f32) -> vec4<f32> {
    var accumulatedColor = vec3<f32>(0.0);
    var totalOpticalDepth = 0.0;
    var transmittance = 1.0;

    let tMax = 15.0;
    let stepSize = 0.15;
    var t: f32 = 0.1;

    for (var i: i32 = 0; i < 60; i = i + 1) {
        if (t > tMax || transmittance < 0.01) {
            break;
        }

        var p = ro + rd * t;
        var density = cloudDensity(p, time, densityScale, flowSpeed);

        if (density > 0.001) {
            // Calculate optical depth for this step
            let stepOpticalDepth = density * stepSize * mix(0.2, 3.0, u.zoom_params.w);
            totalOpticalDepth += stepOpticalDepth;

            // Transmittance through this step
            let stepTransmittance = exp(-stepOpticalDepth);

            // Nebula emission/absorption color
            let rLen = length(p);
            let colorT = rLen * 0.1 + density * 2.0;
            let cloudEmission = nebulaColor(colorT, colorShift);

            // Idea 1 — light-echo shell: gas crossed by the expanding flash front (radius c·age)
            // re-emits a white-blue rim (V838 Mon). Analytic: one exp per step, no extra fbm.
            let dr = (rLen - echoR) / ECHO_WIDTH;
            let echoLight = vec3<f32>(0.78, 0.9, 1.0) * (echoAmp * exp(-dr * dr));

            // Idea 2 — absorbing dense cores: single-scatter albedo σs/(σs+σa·w), w ∝ density².
            // Thin gas keeps albedo ≈ 1 (HEAD); the thickest knots sink dark inside bright envelopes.
            let coreW = CORE_WEIGHT * density * density;
            let albedo = SIGMA_S_NEBULA / (SIGMA_S_NEBULA + SIGMA_A_NEBULA * coreW);

            // Accumulate in-scattered light
            // L += T * emission * (1 - T_step)
            accumulatedColor += transmittance * (cloudEmission + echoLight) * (1.0 - stepTransmittance) * SIGMA_S_NEBULA * albedo;

            // Update transmittance
            transmittance *= stepTransmittance;
        }

        // Adaptive step size
        t = t + stepSize * (1.0 + t * 0.1);
    }

    // Final alpha from total optical depth
    let alpha = 1.0 - exp(-totalOpticalDepth);

    return vec4<f32>(accumulatedColor, alpha);
}

// Warp-flight camera — closed-form orbital conveyor (HEAD formulas, factored so Idea 3 can
// evaluate the same camera a few milliseconds earlier).
fn orbitCamera(time: f32, camDist: f32, flowSpeed: f32, bass: f32, mids: f32) -> Cam {
    let warpT = time + 0.4 * sin(time * 0.31);
    let orbitSpeed = 0.55 + flowSpeed * 0.9 + bass * 0.25;
    let ro = vec3<f32>(
        camDist * sin(warpT * orbitSpeed),
        1.0 + sin(warpT * 0.42) * 0.5 + mids * 0.15,
        camDist * cos(warpT * orbitSpeed)
    );

    let lookAt = vec3<f32>(sin(warpT * 0.2) * 0.5, 0.0, cos(warpT * 0.17) * 0.5);
    let forward = normalize(lookAt - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);
    return Cam(ro, forward, right, up);
}

// Sky direction -> star-cell coordinates (longitude/latitude, STAR_CELLS per radian).
fn skyCoord(d: vec3<f32>) -> vec2<f32> {
    return vec2<f32>(atan2(d.z, d.x), asin(clamp(d.y, -1.0, 1.0))) * STAR_CELLS;
}

// Idea 3 — warp-flight star streaks. Stars are fixed sky cells at infinity; over a short
// exposure the pixel's view ray sweeps the sky segment [qNow, qPrev] as the orbit camera turns,
// so each star smears along the camera's orbital motion (bass speeds the orbit -> longer streaks).
fn starStreaks(qNow: vec2<f32>, qPrevIn: vec2<f32>, pxPerCell: f32, time: f32) -> vec3<f32> {
    var seg = qPrevIn - qNow;
    if (abs(seg.x) > 0.5 * STAR_CELLS) { seg = vec2<f32>(0.0); }   // longitude wrap seam
    let segLen = length(seg);
    if (segLen > STREAK_MAX) { seg = seg * (STREAK_MAX / segLen); }
    let L = min(segLen, STREAK_MAX);
    let segLen2 = max(dot(seg, seg), 1e-6);
    let base = floor(qNow + seg * 0.5);
    let dimming = mix(1.0, 0.6, L / STREAK_MAX);

    var col = 0.0;
    for (var j: i32 = -1; j <= 1; j = j + 1) {
        for (var i: i32 = -1; i <= 1; i = i + 1) {
            let cell = base + vec2<f32>(f32(i), f32(j));
            let h = hash3(vec3<f32>(cell, 0.0));
            if (h.x > 0.98) {
                let sp = cell + 0.15 + 0.7 * h.yz;
                let s = clamp(dot(sp - qNow, seg) / segLen2, 0.0, 1.0);
                let dpx = length(sp - (qNow + seg * s)) * pxPerCell;
                let core = exp(-dpx * dpx * 0.9);
                let twinkle = 0.7 + 0.3 * sin(time * 3.0 + h.y * 10.0);   // HEAD twinkle
                col = max(col, core * twinkle * (1.0 - 0.65 * s) * dimming);
            }
        }
    }
    return vec3<f32>(col);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let pixel = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters from sliders
    let densityScale = u.zoom_params.x * 0.5 + 0.5;
    let colorShift = u.zoom_params.y * 0.5;
    let camDist = u.zoom_params.z * 3.0 + 3.0;
    let flowSpeed = u.zoom_params.w * 0.8 + 0.2;

    // Normalized UV for raymarching
    let aspect = resolution.x / resolution.y;
    let st = (uv - 0.5) * vec2<f32>(aspect, 1.0);

    // Warp-flight camera — closed-form orbital conveyor.
    let warpT = time + 0.4 * sin(time * 0.31);
    let cam = orbitCamera(time, camDist, flowSpeed, bass, mids);
    let ro = cam.ro;

    let rd = normalize(st.x * cam.right + st.y * cam.up + 1.5 * cam.fwd);

    // Idea 1 — light-echo timing: a stateless central flash every ECHO_PERIOD seconds; its light
    // front is a sphere of radius c·age. Bass at the moment brightens the flash and its echo.
    let echoAge = fract(time / ECHO_PERIOD) * ECHO_PERIOD;
    let echoR = ECHO_C * echoAge;
    let echoAmp = (1.0 + 1.5 * bass) * 1.6 * exp(-0.3 * echoAge);

    // Raymarch clouds with volumetric integration
    let cloudResult = raymarchVolumetric(ro, rd, warpT, densityScale, colorShift, flowSpeed, echoR, echoAmp);

    // Idea 1 — the flash itself: closest approach of the view ray to the nebula centre,
    // dimmed by the gas in front of it.
    let tc = max(-dot(ro, rd), 0.0);
    let dMin = length(ro + rd * tc);
    let flashGlow = echoAmp * exp(-echoAge * 3.5) * (exp(-dMin * dMin * 6.0) + 0.15 * exp(-dMin * 1.5))
                  * (1.0 - 0.7 * cloudResult.a);

    // Treble ionization flashes along the view ray.
    let ionFlash = treble * smoothstep(0.55, 1.0, sin(warpT * 4.0 + st.x * 8.0 + st.y * 6.0)) * 0.35;

    // Background gradient (deep space)
    let bgGradient = mix(
        vec3<f32>(0.02, 0.02, 0.08),
        vec3<f32>(0.05, 0.03, 0.1),
        uv.y * 0.5 + 0.5
    );

    // Add stars — Idea 3: fixed sky cells streaked along the orbit camera's motion.
    let camPrev = orbitCamera(time - STREAK_DT, camDist, flowSpeed, bass, mids);
    let rdPrev = normalize(st.x * camPrev.right + st.y * camPrev.up + 1.5 * camPrev.fwd);
    let pxPerCell = 1.5 * resolution.y / STAR_CELLS;
    let stars = starStreaks(skyCoord(rd), skyCoord(rdPrev), pxPerCell, warpT);
    let bg = bgGradient + stars * 0.8;

    // Volumetric composition
    let transmittance = 1.0 - cloudResult.a;
    var finalCol = cloudResult.rgb + bg * transmittance;
    finalCol += vec3<f32>(0.5, 0.7, 1.0) * ionFlash * cloudResult.a;
    finalCol += vec3<f32>(0.85, 0.93, 1.0) * flashGlow;

    // Tone mapping — ACES on display, then HEAD's gamma encode (base clamped >= 0).
    finalCol = acesToneMap(max(finalCol, vec3<f32>(0.0)));
    finalCol = pow(max(finalCol, vec3<f32>(0.0)), vec3<f32>(0.4545));

    // Advected HDR cloud streaks.
    let histCoord = clamp(pixel - vec2<i32>(vec2<f32>(cos(warpT * 0.5), sin(warpT * 0.45)) * (2.0 + flowSpeed * 3.0)),
                          vec2<i32>(0), vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1));
    let prev = textureLoad(dataTextureC, histCoord, 0).rgb;
    // Floor fix: bounded mix trail with HEAD's persistence (was an unbounded sum, ~6.7x blow-out).
    let persist = 0.82 + flowSpeed * 0.05;
    let temporal = clamp(mix(finalCol, prev, persist), vec3<f32>(0.0), vec3<f32>(1.0));

    let depth = clamp(1.0 - cloudResult.a * 0.85, 0.08, 0.98);
    let alpha = clamp(cloudResult.a + length(finalCol) * 0.15, 0.1, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(temporal, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(temporal, alpha));
}
