// ═══════════════════════════════════════════════════════════════
//  Cosmic Jellyfish - A majestic, translucent jellyfish in a cosmic void.
//  Category: generative
//  Features: 3d, raymarching, bioluminescent, space, organic, calm
//
//  Upgrade notes (Batch 16):
//   - The temporal feedback buffer (dataTextureA) is now DISPLAYED:
//     the displayed frame blends toward the accumulated trail so the
//     jelly leaves bioluminescent motion trails behind it.
//   - writeDepthTexture now stores the real normalized raymarch hit
//     distance instead of a flat 0.0, so chained shaders see honest depth.
//   - Bass (plasmaBuffer[0].x) drives the bell pulse amplitude,
//     treble (plasmaBuffer[0].z) drives the tentacle wave frequency.
//   - Glow color uses an IQ cosine palette (cheaper + smoother than the
//     old Rodrigues RGB hue rotation).
//   - ACES tonemap + hue-preserving clamp tame Glow Intensity up to 5.0.
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // [time, rippleCount, resW, resH]
  zoom_config: vec4<f32>,  // [time, mouseX, mouseY, mouseDown]
  zoom_params: vec4<f32>,  // [pulseSpeed, tentacleActivity, hueShift, glowIntensity]
  ripples: array<vec4<f32>, 50>,
};

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// IQ cosine palette: cheap, smooth periodic color ramp.
fn cosinePalette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.2831853 * (c * t + d));
}

// Narkowicz ACES filmic tonemap (in/out roughly linear, clamped 0..1).
fn acesTonemap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Hue-preserving clamp: scale the whole color toward maxVal instead of
// clipping per-channel, so saturated glow keeps its hue instead of
// washing out to white.
fn huePreserveClamp(col: vec3<f32>, maxVal: f32) -> vec3<f32> {
    let peak = max(col.r, max(col.g, col.b));
    if (peak > maxVal) {
        return col * (maxVal / peak);
    }
    return col;
}

// Ribbed bell, scalloped rim, ten fine tentacles, and four broad oral arms.
fn map(pIn: vec3<f32>, time: f32) -> f32 {
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;
    let pulseSpeed = 0.35 + u.zoom_params.x * 1.8;
    let pulse = sin(time * pulseSpeed) * (0.075 + bass * 0.11);
    let activity = u.zoom_params.y;
    let pointer = (u.zoom_config.yz - 0.5) * vec2<f32>(0.55, -0.42);
    let held = select(0.35, 1.0, u.zoom_config.w > 0.5);

    var p = pIn;
    p = vec3<f32>(p.xy - pointer * held, p.z);
    var bellP = p - vec3<f32>(0.0, 0.46, 0.0);
    let azimuth = atan2(bellP.z, bellP.x);
    let ribs = 1.0 + cos(azimuth * 12.0 + time * 0.18) * 0.035 * (0.4 + activity);
    let bellScale = vec3<f32>((1.0 + pulse) * ribs, 0.78 - pulse * 0.55, (1.0 + pulse) * ribs);
    let outerBell = length(bellP / bellScale) * 0.79 - 0.51;
    let innerBell = length((bellP + vec3<f32>(0.0, 0.30, 0.0)) / vec3<f32>(0.78, 0.55, 0.78)) - 0.43;
    let scallop = cos(azimuth * 8.0) * 0.025 * (1.0 - smoothstep(-0.18, 0.08, bellP.y));
    let bell = max(outerBell + scallop, -innerBell);

    var fineTentacles = 100.0;
    let waveFrequency = 2.2 + treble * 4.5;
    for (var i = 0; i < 10; i += 1) {
        let fi = f32(i);
        let angle = fi / 10.0 * 6.2831853;
        let anchor = vec3<f32>(cos(angle) * 0.33, -0.02, sin(angle) * 0.33);
        var q = p - anchor;
        let lengthScale = 1.25 + 0.35 * sin(fi * 2.17);
        let along = clamp(-q.y, 0.0, lengthScale);
        q.x += sin(along * (3.0 + fi * 0.07) + time * waveFrequency + fi) * 0.10 * activity;
        q.z += cos(along * 2.7 - time * waveFrequency * 0.82 + fi * 1.7) * 0.10 * activity;
        q.y += along;
        let taper = mix(0.045, 0.012, along / lengthScale);
        fineTentacles = min(fineTentacles, length(q) - taper);
    }

    var oralArms = 100.0;
    for (var j = 0; j < 4; j += 1) {
        let fj = f32(j);
        let angle = fj * 1.5707963 + 0.785398;
        var q = p - vec3<f32>(cos(angle) * 0.13, -0.02, sin(angle) * 0.13);
        let along = clamp(-q.y, 0.0, 1.05);
        q.x += sin(along * 4.2 + time * 1.1 + fj * 1.9) * 0.15 * activity;
        q.z += cos(along * 3.4 - time * 0.9 + fj) * 0.12 * activity;
        q.y += along;
        let ribbon = length(vec2<f32>(length(q.xz) * 0.62, q.y)) - mix(0.09, 0.022, along / 1.05);
        oralArms = min(oralArms, ribbon);
    }

    return smin(smin(bell, fineTentacles, 0.11), oralArms, 0.14);
}

// Simple hash for stars
fn hash(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

fn stars(dir: vec3<f32>) -> f32 {
    var p = dir * 100.0;
    let cell = floor(p);
    let local = fract(p);
    var n = cell.x + cell.y * 57.0 + cell.z * 113.0;
    var h = hash(n);
    if (h > 0.95) {
        let star_pos = vec3<f32>(hash(n + 1.0), hash(n + 2.0), hash(n + 3.0));
        var d = length(local - star_pos);
        return smoothstep(0.1, 0.0, d);
    }
    return 0.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    var uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
    let time = u.config.x;
    let texUV = vec2<f32>(global_id.xy) / resolution;
    let pixel = vec2<i32>(global_id.xy);

    // Clicks send a pressure wave through the camera ray and the glow field.
    var clickGlow = 0.0;
    var clickWarp = vec2<f32>(0.0);
    let aspect = resolution.x / resolution.y;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.2) {
            let delta = (texUV - ripple.xy) * vec2<f32>(aspect, 1.0);
            let radius = length(delta);
            let front = smoothstep(0.028, 0.0, abs(radius - age * 0.31)) * exp(-age * 1.05);
            clickGlow += front;
            clickWarp += delta / max(radius, 0.001) * front;
        }
    }
    uv += clickWarp * 0.10;

    // Previous A is mirrored read-only through C and must be loaded exactly.
    let prev = textureLoad(dataTextureC, pixel, 0);

    // Camera
    var mouse = u.zoom_config.yz * 2.0 - 1.0;
    var ro = vec3<f32>(0.0, 0.0, -4.0);
    let yaw = rot(mouse.x * 1.45);
    let yawed = yaw * ro.xz;
    ro = vec3<f32>(yawed.x, ro.y, yawed.y);
    let pitch = rot(mouse.y * 1.05);
    let pitched = pitch * ro.yz;
    ro = vec3<f32>(ro.x, pitched.x, pitched.y);
    ro *= select(1.0, 0.88, u.zoom_config.w > 0.5);

    let look_at = vec3<f32>(0.0, 0.0, 0.0);
    let f = normalize(look_at - ro);
    let r = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), f));
    let up = cross(f, r);
    let rd = normalize(f + r * uv.x + up * uv.y);

    // Raymarch loop
    var t = 0.0;
    var glow = 0.0;
    var hit = false;

    for(var i=0; i<64; i++) {
        var p = ro + rd * t;
        var d = map(p, time);

        // Accumulate glow near the surface
        glow += 1.0 / (1.0 + d * d * 20.0);

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 10.0) { break; }
        t += d;
    }

    // Coloring
    var col = vec3<f32>(0.0);

    // Starfield plus a very low-frequency cosmic dust veil.
    let star = stars(rd);
    let dust = 0.5 + 0.5 * sin(rd.x * 17.0 + rd.y * 11.0 + time * 0.07)
        * sin(rd.z * 13.0 - rd.y * 7.0 - time * 0.05);
    col += vec3<f32>(star) + vec3<f32>(0.035, 0.012, 0.075) * dust;

    if (hit) {
        var p = ro + rd * t;
        // Simple normal calculation
        let e = vec2<f32>(0.01, 0.0);
        var n = normalize(vec3<f32>(
            map(p + e.xyy, time) - map(p - e.xyy, time),
            map(p + e.yxy, time) - map(p - e.yxy, time),
            map(p + e.yyx, time) - map(p - e.yyx, time)
        ));

        let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light_dir), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        let ribPhase = atan2(p.z, p.x) * 12.0;
        let ribGlow = pow(max(0.0, cos(ribPhase)), 10.0) * smoothstep(-0.2, 0.6, p.y);
        let base_color = vec3<f32>(0.16, 0.48, 0.82);
        col = base_color * diff * 0.45 + base_color * fresnel * 0.95;
        col += vec3<f32>(0.7, 0.86, 1.15) * ribGlow * (0.18 + plasmaBuffer[0].y * 0.28);
    }

    // Add accumulated glow (bioluminescence) via IQ cosine palette.
    // Hue Shift slider (zoom_params.z) phases the palette around the
    // spectrum; default 0.0 lands on a deep bioluminescent blue that
    // matches the original look.
    let hue_shift = u.zoom_params.z;
    let glowColor = max(cosinePalette(
        hue_shift,
        vec3<f32>(0.30, 0.40, 0.55),
        vec3<f32>(0.35, 0.35, 0.45),
        vec3<f32>(1.00, 1.00, 1.00),
        vec3<f32>(0.50, 0.33, 0.00)
    ), vec3<f32>(0.0));

    let glow_intensity = u.zoom_params.w;
    col += glow * glowColor * glow_intensity * 0.018;
    col += glowColor * clickGlow * (0.45 + glow_intensity * 0.18);

    // ── Temporal feedback: compute the trail AND display it ──────────
    // decay stays < 1.0 so the accumulation is stable; the accumulated
    // trail is clamped pre-tint at ~1.2 so old frames cannot blow out.
    let decay = 0.962;
    var temporal = mix(prev.rgb * decay, col, 0.28);
    temporal = min(temporal, vec3<f32>(5.0));
    let liveAlpha = clamp(select(glow * 0.006 + star * 0.7, 0.94, hit) + clickGlow * 0.3, 0.0, 1.0);
    let temporalAlpha = mix(prev.a * decay, liveAlpha, 0.30);
    textureStore(dataTextureA, pixel, vec4<f32>(temporal, temporalAlpha));

    // Blend the live frame toward the accumulated trail: the jelly now
    // leaves visible bioluminescent motion trails instead of dropping
    // the feedback on the floor.
    col = mix(col, temporal, 0.6);

    // Tone pipeline: ACES filmic curve, then a hue-preserving clamp so
    // Glow Intensity up to 5.0 stays colorful instead of clipping white.
    col = acesTonemap(col);
    col = huePreserveClamp(col, 1.0);

    // Honest depth: normalized raymarch hit distance (1.0 = miss / far
    // plane at t = 10.0) so chained shaders get real scene depth.
    var depth_out = 1.0;
    if (hit) {
        depth_out = clamp(t / 10.0, 0.0, 1.0);
    }

    textureStore(writeTexture, pixel, vec4<f32>(col, temporalAlpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth_out, 0.0, 0.0, 0.0));
}
