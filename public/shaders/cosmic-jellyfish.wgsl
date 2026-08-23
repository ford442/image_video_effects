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

// SDF for the Jellyfish (silhouette hand-tuned: bell hollow +
// 8-tentacle capsule loop, smin k=0.2 - preserved verbatim).
fn map(p: vec3<f32>, time: f32) -> f32 {
    // Audio: bass drives the bell pulse amplitude, treble the tentacle
    // wave frequency. Read here (inside map) so the SDF stays honest.
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;

    // Pulse animation
    let pulse_speed = u.zoom_params.x * 2.0;
    let pulse = sin(time * pulse_speed) * (0.1 + bass * 0.12);

    // Tentacle Activity
    let tentacle_amp = u.zoom_params.y;

    // Bell (Ellipsoid-ish)
    var p_bell = p;
    p_bell.y -= 0.5;

    // Stretch
    let d_bell = length(p_bell / vec3<f32>(1.0 + pulse, 0.8 - pulse, 1.0 + pulse)) * 0.8 - 0.5;

    // Hollow out bottom
    let d_hollow = length(p_bell + vec3<f32>(0.0, 0.5, 0.0)) - 0.4;
    let bell_final = max(d_bell, -d_hollow);

    // Tentacles
    var d_tentacles = 100.0;
    let num_tentacles = 8.0;
    let wave_freq = 2.0 + treble * 4.0;
    for (var i = 0.0; i < num_tentacles; i = i + 1.0) {
        var angle = (i / num_tentacles) * 6.28318;
        let radius = 0.3;
        let tentacle_pos = vec3<f32>(cos(angle) * radius, 0.0, sin(angle) * radius);
        var p_t = p - tentacle_pos;

        // Waving motion (treble-modulated frequency)
        p_t.x += sin(p_t.y * 3.0 + time * wave_freq + i) * 0.1 * tentacle_amp;
        p_t.z += cos(p_t.y * 3.0 + time * wave_freq + i) * 0.1 * tentacle_amp;

        // Capsule shape for tentacle
        p_t.y += 1.0; // Shift down
        var h = 2.0; // Length
        p_t.y = clamp(p_t.y, 0.0, h);
        let d_t = length(p_t) - 0.05 * (1.0 - p_t.y / h); // Taper

        d_tentacles = min(d_tentacles, d_t);
    }

    // Smooth blend bell and tentacles
    return smin(bell_final, d_tentacles, 0.2);
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
    var uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
    let time = u.config.x;
    let mids = plasmaBuffer[0].y;

    let texUV = vec2<f32>(global_id.xy) / resolution;
    let pixel = vec2<i32>(global_id.xy);

    // Previous frame's temporal trail (dataTextureA of last frame,
    // mirrored read-only through dataTextureC).
    let prev = textureSampleLevel(dataTextureC, u_sampler, texUV, 0.0);

    // Camera
    var mouse = u.zoom_config.yz * 2.0 - 1.0;
    var ro = vec3<f32>(0.0, 0.0, -4.0);
    // Rotate camera based on mouse
    var cam_rot = rot(mouse.x * 2.0);
    ro.x = cam_rot[0][0] * ro.x + cam_rot[0][1] * ro.z;
    ro.z = cam_rot[1][0] * ro.x + cam_rot[1][1] * ro.z;

    cam_rot = rot(mouse.y * 2.0);
    ro.y = cam_rot[0][0] * ro.y + cam_rot[0][1] * ro.z;
    ro.z = cam_rot[1][0] * ro.y + cam_rot[1][1] * ro.z;

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

    // Starfield background
    col += vec3<f32>(stars(rd));

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

        let base_color = vec3<f32>(0.2, 0.5, 0.8);
        col = base_color * diff * 0.5 + base_color * fresnel * 0.8;
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
    col += glow * glowColor * glow_intensity * 0.02;

    // ── Temporal feedback: compute the trail AND display it ──────────
    // decay stays < 1.0 so the accumulation is stable; the accumulated
    // trail is clamped pre-tint at ~1.2 so old frames cannot blow out.
    let decay = 0.96;
    var temporal = mix(prev.rgb * decay, col, 0.25);
    temporal = min(temporal, vec3<f32>(1.2));
    textureStore(dataTextureA, pixel, vec4<f32>(temporal, 1.0));

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

    
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let aspect = u.config.z / max(u.config.w, 1.0);
    let screenUV = vec2<f32>(pixel) / vec2<f32>(u.config.z, u.config.w);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((screenUV - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(screenUV - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let __finalRGB = vec4<f32>(col, 1.0).rgb + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, pixel, vec4<f32>(__finalRGB, vec4<f32>(col, 1.0).a));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth_out, 0.0, 0.0, 0.0));
}
