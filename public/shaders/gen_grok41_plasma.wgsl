// ═══════════════════════════════════════════════════════════════════
//  Spherical Harmonics Plasma v3 - Audio-reactive gas giant
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven,
//            spherical-harmonics, animated
//  Upgraded: 2026-05-02 (Tier-1 integration pass)
//  Upgraded: 2026-07-26 (Batch 18 swarm pass)
//  Batch 18 fixes: Hue Shift slider was DEAD (shiftMat built but never
//            applied) -> now a true grey-axis hue rotation applied to the
//            banded color; added missing out-of-bounds guard.
//  Batch 18 additions: band-specific harmonics (per-bin FFT: l1<-bass
//            bins 1..3, l2<-mid bins 4..6, l3<-treble bins 7..8) and a
//            subtle animated Worley storm-cell overlay (<20% mix).
//  Creative additions: lightning tendrils on treble, Rayleigh limb scattering
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn rotateX(p: vec3<f32>, angle: f32) -> vec3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec3<f32>(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

fn rotateY(p: vec3<f32>, angle: f32) -> vec3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec3<f32>(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

// ─── Spherical harmonics Y(l,m) — exact normalization coefficients ───
// DO NOT MODIFY: constants below are the real Y00..Y30 normalizations.
fn Y00(theta: f32, phi: f32) -> f32 { return 0.2820947918; }
fn Y10(theta: f32, phi: f32) -> f32 { return 0.4886025119 * cos(theta); }
fn Y1p1(theta: f32, phi: f32) -> f32 { return -0.4886025119 * sin(theta) * cos(phi); }
fn Y1n1(theta: f32, phi: f32) -> f32 { return -0.4886025119 * sin(theta) * sin(phi); }
fn Y20(theta: f32, phi: f32) -> f32 { return 0.3153915653 * (3.0 * cos(theta) * cos(theta) - 1.0); }
fn Y2p1(theta: f32, phi: f32) -> f32 { return -1.0219854764 * sin(theta) * cos(theta) * cos(phi); }
fn Y2n1(theta: f32, phi: f32) -> f32 { return -1.0219854764 * sin(theta) * cos(theta) * sin(phi); }
fn Y2p2(theta: f32, phi: f32) -> f32 { return 0.5462742153 * sin(theta) * sin(theta) * cos(2.0 * phi); }
fn Y2n2(theta: f32, phi: f32) -> f32 { return 0.5462742153 * sin(theta) * sin(theta) * sin(2.0 * phi); }
fn Y30(theta: f32, phi: f32) -> f32 {
    let ct = cos(theta);
    return 0.3731763326 * (5.0 * ct * ct * ct - 3.0 * ct);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(q) * 43758.5453);
}

// Animated Worley (cellular) F1 noise — drifting feature points give the
// gas-giant bands a cellular "storm cell" texture without touching the
// spherical-harmonic structure itself.
fn worley2D(p: vec2<f32>, t: f32) -> f32 {
    let cell = floor(p);
    let f = fract(p);
    var minDist = 8.0;
    for (var j = -1; j <= 1; j = j + 1) {
        for (var i = -1; i <= 1; i = i + 1) {
            let offset = vec2<f32>(f32(i), f32(j));
            let h = hash22(cell + offset);
            let point = offset + 0.5 + 0.4 * sin(t + TAU * h) - f;
            let d = dot(point, point);
            minDist = min(minDist, d);
        }
    }
    return sqrt(minDist);
}

fn gasGiantColor(value: f32, time: f32, hueShift: f32) -> vec3<f32> {
    let v = value * 0.5 + 0.5;
    let color1 = vec3<f32>(0.8, 0.6, 0.4);
    let color2 = vec3<f32>(0.6, 0.4, 0.2);
    let color3 = vec3<f32>(0.9, 0.5, 0.2);
    let color4 = vec3<f32>(0.7, 0.3, 0.15);
    let color5 = vec3<f32>(0.85, 0.7, 0.5);

    var color: vec3<f32>;
    if (v < 0.2) { color = mix(color1, color2, v * 5.0); }
    else if (v < 0.4) { color = mix(color2, color3, (v - 0.2) * 5.0); }
    else if (v < 0.6) { color = mix(color3, color4, (v - 0.4) * 5.0); }
    else if (v < 0.8) { color = mix(color4, color5, (v - 0.6) * 5.0); }
    else { color = mix(color5, color1, (v - 0.8) * 5.0); }

    // Hue rotation by hueShift — FIXED (Batch 18): the matrix used to be
    // built and then discarded (dead slider). It is now a proper Rodrigues
    // rotation about the grey axis (1,1,1)/sqrt(3), so rotating it shifts
    // hue while preserving luminance, and it is APPLIED to the final color.
    let shiftAngle = hueShift * TAU;
    let k = vec3<f32>(0.57735026919, 0.57735026919, 0.57735026919);
    let cs = cos(shiftAngle);
    let sn = sin(shiftAngle);
    let oneMinusC = 1.0 - cs;
    let shiftMat = mat3x3<f32>(
        vec3<f32>(cs + k.x * k.x * oneMinusC, k.y * k.x * oneMinusC + k.z * sn, k.z * k.x * oneMinusC - k.y * sn),
        vec3<f32>(k.x * k.y * oneMinusC - k.z * sn, cs + k.y * k.y * oneMinusC, k.z * k.y * oneMinusC + k.x * sn),
        vec3<f32>(k.x * k.z * oneMinusC + k.y * sn, k.y * k.z * oneMinusC - k.x * sn, cs + k.z * k.z * oneMinusC)
    );

    let variation = sin(v * 20.0 + time) * 0.1;
    return shiftMat * (color + vec3<f32>(variation));
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);

    // Out-of-bounds guard — FIXED (Batch 18): was missing entirely.
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }

    let timeRaw = u.config.x;
    let time = timeRaw * 0.15;
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / min(resolution.x, resolution.y);

    // Audio — aggregate bands (preserved) plus per-bin FFT for the
    // band-specific harmonic weighting below.
    let audioBands = plasmaBuffer[0].xyz;
    let bass = audioBands.x;
    let mids = audioBands.y;
    let treble = audioBands.z;

    // Per-bin FFT: each spherical-harmonic family dances to its own range.
    // l1 (Y1x) <- bass bins 1..3, l2 (Y2x) <- mid bins 4..6, l3 (Y3x) <- treble bins 7..8.
    let bassBins = (plasmaBuffer[1].x + plasmaBuffer[2].x + plasmaBuffer[3].x) / 3.0;
    let midBins = (plasmaBuffer[4].x + plasmaBuffer[5].x + plasmaBuffer[6].x) / 3.0;
    let trebleBins = (plasmaBuffer[7].x + plasmaBuffer[8].x) / 2.0;

    // Mouse for view + light direction
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    let mouseInfluence = u.zoom_config.w;

    // Sphere setup
    let sphereRadius = 0.45;
    let sphereCenter = vec3<f32>(0.0, 0.0, 0.0);
    let ro = vec3<f32>(0.0, 0.0, 1.8);
    let rd = normalize(vec3<f32>(uv.x, uv.y, -1.2));

    let rotTime = time * 0.5;
    let ro_rotated = rotateY(rotateX(ro, sin(time * 0.2) * 0.1), rotTime);
    let viewRotY = mouse.x * 0.5 * mouseInfluence;
    let viewRotX = mouse.y * 0.3 * mouseInfluence;
    let ro_final = rotateY(rotateX(ro_rotated, viewRotX), viewRotY);
    let rd_final = rotateY(rotateX(rd, viewRotX), viewRotY);

    let oc = ro_final - sphereCenter;
    let a = dot(rd_final, rd_final);
    let b = 2.0 * dot(oc, rd_final);
    let c_ = dot(oc, oc) - sphereRadius * sphereRadius;
    let discriminant = b * b - 4.0 * a * c_;

    let uv_norm = vec2<f32>(global_id.xy) / resolution;
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv_norm, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv_norm, 0.0).r;
    let previousTelemetry = textureLoad(dataTextureC, coord, 0);
    let telemetryValid = step(0.5, previousTelemetry.a);

    // Recent clicks launch bounded lightning rings across the visible globe.
    let screenAspect = resolution.x / max(resolution.y, 1.0);
    let rippleCount = min(u32(u.config.y), 50u);
    var clickLightning = 0.0;
    for (var i = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let age = timeRaw - ripple.z;
        if (age < 0.0 || age > 1.6) { continue; }
        let delta = (uv_norm - ripple.xy) * vec2<f32>(screenAspect, 1.0);
        let dist = length(delta);
        let angle = atan2(delta.y, delta.x);
        let strength = clamp(ripple.w, 0.0, 1.0) * exp(-age * 2.2);
        let ring = exp(-abs(dist - age * 0.42) * 90.0);
        let branches = pow(0.5 + 0.5 * sin(angle * 11.0 + dist * 95.0 - age * 31.0), 8.0);
        clickLightning += strength * ring * (0.35 + branches);
    }

    var outputColor = inputColor.rgb;
    var depth = inputDepth;
    var alpha = inputColor.a;
    let opacity = 0.9;
    // Aux data channel (dataTextureA): harmonic pattern, storm mask, limb factor.
    var auxData = vec4<f32>(0.0, 0.0, 0.0, 1.0);

    if (discriminant > 0.0) {
        let t = (-b - sqrt(discriminant)) / (2.0 * a);
        let hitPoint = ro_final + rd_final * t;
        let normal = normalize(hitPoint - sphereCenter);
        let theta = acos(clamp(normal.y, -1.0, 1.0));
        let phi = atan2(normal.z, normal.x);

        // Sliders: L1/L2/L3 harmonic coefficients + Hue Shift.
        // Each harmonic family is amplified by its own FFT bin range.
        let coeffs = u.zoom_params;
        let l1 = coeffs.x * (1.0 + bassBins * 0.9);
        let l2 = coeffs.y * (1.0 + midBins * 0.9);
        let l3 = coeffs.z * (1.0 + trebleBins * 0.9);
        let hueShift = coeffs.w + mids * 0.25;

        var pattern = 0.0;
        pattern = pattern + Y00(theta, phi) * 0.4;
        pattern = pattern + Y10(theta, phi) * sin(time * 0.5 + phi * 2.0) * l1;
        pattern = pattern + Y1p1(theta, phi) * cos(time * 0.3) * l1 * 0.5;
        pattern = pattern + Y1n1(theta, phi) * sin(time * 0.4) * l1 * 0.5;
        pattern = pattern + Y20(theta, phi) * cos(time * 0.6) * l2;
        pattern = pattern + Y2p1(theta, phi) * sin(time * 0.45 + theta) * l2 * 0.6;
        pattern = pattern + Y2n1(theta, phi) * cos(time * 0.55) * l2 * 0.6;
        pattern = pattern + Y2p2(theta, phi) * sin(time * 0.35 + phi * 3.0) * l2 * 0.4;
        pattern = pattern + Y2n2(theta, phi) * cos(time * 0.25) * l2 * 0.4;
        pattern = pattern + Y30(theta, phi) * sin(time * 0.7 + phi) * l3 * 0.5;

        // Exact prior A telemetry damps harmonic jumps without reinterpreting
        // the packed channels as display colour.
        pattern = mix(pattern, previousTelemetry.r * 0.97, telemetryValid * 0.32);

        // Bass turbulence path preserved from v2 (aggregate bass band).
        let turbulence = sin(theta * 15.0 + time) * sin(phi * 12.0 - time * 0.5) * 0.05;
        pattern = pattern + turbulence * (l1 + l2 + l3) * 0.3 * (1.0 + bass * 0.8);

        // ─── Storm cells: animated Worley overlay on the band structure ───
        // F1 distance in (theta, phi) space -> bright cellular cores. Kept
        // under a 20% mix so the spherical harmonics stay dominant.
        let stormCoord = vec2<f32>(theta * 4.0, phi * 2.0);
        let stormF1 = worley2D(stormCoord, time * 0.6);
        let stormMaskLive = smoothstep(0.9, 0.2, stormF1);
        let stormMask = mix(stormMaskLive, previousTelemetry.g * 0.94, telemetryValid * 0.35);
        let bassStorm = 1.0 + bass * 0.5;

        // Mouse-controlled light direction (replaces fixed (0.8, 0.3, 1.0))
        let mouseLight = vec3<f32>(mouse.x, mouse.y, 0.6);
        let staticLight = vec3<f32>(0.8, 0.3, 1.0);
        let lightDir = normalize(mix(staticLight, mouseLight, mouseInfluence));
        let diff = max(dot(normal, lightDir), 0.0);
        let ambient = 0.25;
        let viewDir = -rd_final;
        let halfDir = normalize(lightDir + viewDir);
        let spec = pow(max(dot(normal, halfDir), 0.0), 32.0) * 0.3;
        let limbT = 1.0 - abs(dot(normal, viewDir));
        let rim = pow(limbT, 3.0) * 0.4;

        var baseColor = gasGiantColor(pattern, time, hueShift);
        // Storm cells: darken cell walls / brighten cell cores by resampling
        // the band palette slightly off-pattern — subtle, capped at 18% mix.
        let stormTint = gasGiantColor(pattern + stormF1 * 0.6 - 0.3, time, hueShift) * (1.1 * bassStorm);
        baseColor = mix(baseColor, stormTint, stormMask * 0.18);

        // HDR accumulation (boost before tone map)
        var litColor = baseColor * (diff * 1.1 + ambient) * 1.4 + vec3<f32>(spec) * 1.5;

        // ─── Creative: Rayleigh-style blue limb scattering ───
        let rayleigh = pow(limbT, 2.5);
        let rayleighColor = vec3<f32>(0.35, 0.55, 1.0) * rayleigh * 0.9;
        litColor = litColor + rayleighColor;

        // Atmosphere rim + audio sparkle
        let atmosphereColor = vec3<f32>(0.6, 0.8, 1.0);
        litColor = litColor + atmosphereColor * rim;

        // ─── Creative: Lightning tendrils on treble (preserved from v2) ───
        let lightningSeed = hash21(vec2<f32>(floor(theta * 40.0), floor(phi * 40.0 + timeRaw * 30.0)));
        let lightningRand = hash21(vec2<f32>(floor(theta * 12.0), floor(phi * 12.0 + timeRaw * 8.0)));
        let lightningMask = step(0.985 - treble * 0.04, lightningSeed) * smoothstep(0.0, 0.6, limbT);
        let arcShape = pow(lightningRand, 8.0);
        litColor = litColor + vec3<f32>(0.7, 0.85, 1.0) * lightningMask * arcShape * (treble * 4.0 + 0.5);
        litColor = litColor + vec3<f32>(0.55, 0.82, 1.6) * clickLightning * (0.8 + treble * 1.8);

        // Tone map
        let tonedColor = acesToneMapping(litColor);

        let rimAlpha = pow(limbT, 2.0);
        let hitAlpha = mix(0.9, 1.0, rimAlpha * 0.5);

        outputColor = mix(inputColor.rgb, tonedColor, hitAlpha * opacity);
        alpha = max(inputColor.a, hitAlpha * opacity);
        auxData = vec4<f32>(pattern, stormMask, limbT, 1.0);

        let clipZ = hitPoint.z;
        let generatedDepth = (clipZ + sphereRadius) / (sphereRadius * 2.0 + 1.8);
        depth = mix(inputDepth, generatedDepth, hitAlpha * opacity);
    }

    textureStore(writeTexture, coord, vec4<f32>(outputColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, auxData);
}
