// ----------------------------------------------------------------
// Stellar Web-Loom
// Category: generative
// Features: cosmic-thread-raymarch, volumetric-glow, starfield,
//           warp-speed-streaks, hdr-feedback-trails, audio-transient-burst,
//           audio-color-temperature, aces-tone-map, semantic-alpha,
//           generated-depth, fast-motion
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
    zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0–1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
    zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
    ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

const HDR_CLAMP: f32 = 6.0; // feedback history energy ceiling (stability at speed)

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn rot2D(a: f32) -> mat2x2<f32> {
    return rot(a);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + vec3<f32>(33.33));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    let n = i.x + i.y * 157.0 + 113.0 * i.z;
    return mix(
        mix(mix(hash31(vec3<f32>(n + 0.0)), hash31(vec3<f32>(n + 1.0)), u.x),
            mix(hash31(vec3<f32>(n + 157.0)), hash31(vec3<f32>(n + 158.0)), u.x), u.y),
        mix(mix(hash31(vec3<f32>(n + 113.0)), hash31(vec3<f32>(n + 114.0)), u.x),
            mix(hash31(vec3<f32>(n + 270.0)), hash31(vec3<f32>(n + 271.0)), u.x), u.y), u.z
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var pp = p;
    for (var i = 0; i < 4; i++) {
        f += w * noise3(pp);
        pp *= 2.0;
        w *= 0.5;
    }
    return f;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn sdCylinder(p: vec3<f32>, c: vec2<f32>) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - c;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

var<private> g_time: f32;
var<private> g_mouse: vec2<f32>;
var<private> g_audio: f32;

fn map(pos: vec3<f32>) -> vec2<f32> {
    let density = max(0.1, u.zoom_params.x);
    let weaveSpeed = u.zoom_params.y;
    let singularityPull = 1.5 + u.zoom_config.w * 1.5; // click deepens the singularity

    var p = pos;

    let mouseDist = length(p.xy - g_mouse * 5.0);
    if (mouseDist < 5.0) {
        let pull = singularityPull * (1.0 - smoothstep(0.0, 5.0, mouseDist));
        let theta = pull * 2.0;
        let temp_p_xy = rot2D(theta) * p.xy;
        p.x = temp_p_xy.x;
        p.y = temp_p_xy.y;

        p.x -= g_mouse.x * pull * 2.0;
        p.y -= g_mouse.y * pull * 2.0;
        p.z -= pull * 2.0;
    }

    let domainSpacing = 4.0 / density;

    var cell = floor((p + vec3<f32>(domainSpacing * 0.5)) / domainSpacing);
    var q = p;
    q.x = p.x - cell.x * domainSpacing;
    q.y = p.y - cell.y * domainSpacing;
    q.z = p.z - cell.z * domainSpacing;

    // Weave turbulence — time-warp eased for fast surges that never strobe
    let fbm_time = (g_time + 0.35 * sin(g_time * 0.43)) * weaveSpeed * 0.9 + g_audio;
    let warp = vec3<f32>(
        fbm(q + vec3<f32>(fbm_time, 0.0, 0.0)),
        fbm(q + vec3<f32>(0.0, fbm_time, 0.0)),
        fbm(q + vec3<f32>(0.0, 0.0, fbm_time))
    ) * 2.0 - vec3<f32>(1.0);

    let warped_q = q + warp * 0.5;

    let nodeDist = sdSphere(q, 0.3);

    let cylDistX = sdCylinder(warped_q.yzx, vec2<f32>(0.05, domainSpacing));
    let cylDistY = sdCylinder(warped_q.zxy, vec2<f32>(0.05, domainSpacing));
    let cylDistZ = sdCylinder(warped_q.xyz, vec2<f32>(0.05, domainSpacing));

    let threadDist = min(cylDistX, min(cylDistY, cylDistZ));

    let d = min(nodeDist, threadDist);
    var mat_id = 0.0;
    if (threadDist < nodeDist) { mat_id = 1.0; }

    return vec2<f32>(d * 0.6, mat_id);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let dims = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(dims.x) || pixel.y >= i32(dims.y)) { return; }

    let fragCoord = vec2<f32>(pixel);
    var uv = (fragCoord * 2.0 - dims) / dims.y;

    g_time = u.config.x;

    // Audio (plasmaBuffer only)
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    g_audio = bass * 0.5;

    // ── Audio transient burst envelope (rising-edge on bass, bounded decay) ──
    // extraBuffer[133] = previous bass, [134] = burst envelope. Single writer.
    let bufLen = arrayLength(&extraBuffer);
    if (global_id.x == 0u && global_id.y == 0u && bufLen > 135u) {
        let prevBass = extraBuffer[133];
        var env = extraBuffer[134] * 0.90; // smooth exp decay
        env = max(env, min((bass - prevBass) * 5.0, 2.0)); // rising-edge launch
        extraBuffer[133] = bass;
        extraBuffer[134] = clamp(env, 0.0, 2.0);
    }
    var burst = 0.0;
    if (bufLen > 135u) { burst = extraBuffer[134]; }

    // Mouse: zoom_config.yz is already 0–1 canvas uv (y=0 top, matching uv below)
    g_mouse = u.zoom_config.yz * 2.0 - vec2<f32>(1.0);

    let weaveSpeed = u.zoom_params.y;

    // Audio-reactive color temperature: mids swing the loom cool→warm
    let tempMix = clamp(mids * 0.45, 0.0, 1.0);
    let coolTint = vec3<f32>(0.35, 0.7, 1.0);
    let warmTint = vec3<f32>(1.0, 0.55, 0.25);
    let tempTint = mix(coolTint, warmTint, tempMix);

    // Starfield — smooth sinusoidal twinkle (no per-frame hash strobing)
    var starCol = vec3<f32>(0.0);
    let star_uv = uv + g_mouse * 0.1;
    for (var i = 1; i <= 3; i++) {
        let fi = f32(i);
        let cellId = floor(star_uv * 100.0 / fi);
        let s = hash31(vec3<f32>(cellId, fi));
        if (s > 0.98) {
            let twinkle = 0.65 + 0.35 * sin(g_time * (1.5 + fi) + s * 40.0);
            starCol += vec3<f32>(s) * (1.0 - fi * 0.2) * twinkle * (1.0 + treble * 0.6);
        }
    }

    // Camera — warp-flight: forward speed rides the Weave Speed slider so the
    // whole loom rushes past; lateral sway keeps the organic drift.
    let flightSpeed = 1.2 + weaveSpeed * 1.6;
    var ro = vec3<f32>(0.0, 0.0, -5.0 + g_time * flightSpeed);
    ro.x += sin(g_time * 0.35) * 1.0;
    ro.y += cos(g_time * 0.42) * 1.0;

    let ta = ro + vec3<f32>(0.0, 0.0, 1.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    var t = 0.0;
    var d = 0.0;
    var maxT = 20.0;
    var glow = 0.0;
    var colorAccum = vec3<f32>(0.0);
    let plasmaGlow = u.zoom_params.z;

    for (var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;

        let curGlow = 0.05 / (0.01 + abs(d));
        glow += curGlow;

        let mat_id = res.y;
        if (mat_id == 0.0) {
            colorAccum += vec3<f32>(0.1, 0.3, 0.8) * tempTint * curGlow * plasmaGlow * 0.02 * (1.0 + bass + burst);
        } else {
            colorAccum += vec3<f32>(0.5, 0.2, 0.9) * tempTint * curGlow * plasmaGlow * 0.015 * (1.0 + bass * 1.5 + burst * 1.5);
        }

        if (d < 0.001 || t > maxT) { break; }
        t += d;
    }

    colorAccum += vec3<f32>(1.0, 0.4, 0.2) * g_audio * glow * 0.005 * (1.0 + burst);

    var col = colorAccum + starCol * exp(-t * 0.1);

    // ── Warp speed streaks: radial speed-lines along flight direction ──
    // Stretched along the radial (motion) direction, rushing inward — smooth
    // noise only, temporally coherent at any speed.
    let r = max(length(uv), 0.001);
    let ang = atan2(uv.y, uv.x);
    let streakPhase = 1.6 / (r + 0.15) - g_time * (2.5 + weaveSpeed * 3.5);
    let streakN = noise3(vec3<f32>(ang * 9.0, streakPhase, g_time * 0.35));
    let streaks = smoothstep(0.60, 0.95, streakN) * exp(-r * 0.9);
    col += tempTint * streaks * (0.35 + bass * 0.4 + burst * 1.2);

    // ── HDR velocity feedback trails (dataTextureC → dataTextureA) ────
    // The warp flight smears luminous threads into light-trails. History is
    // clamped to HDR_CLAMP so speed can never blow up the feedback loop.
    let prev = textureLoad(dataTextureC, pixel, 0);
    let trailDecay = 0.82 + clamp(weaveSpeed, 0.0, 3.0) * 0.04; // faster weave → longer streaks
    let history = min(prev.rgb * trailDecay, vec3<f32>(HDR_CLAMP));
    var hdr = col + history;
    hdr = min(hdr, vec3<f32>(HDR_CLAMP));

    // Real generated depth (raymarch travel distance, normalized)
    let depthOut = clamp(t / maxT, 0.0, 1.0);
    textureStore(dataTextureA, pixel, vec4<f32>(hdr, depthOut));

    // ── ACES tone map (linear HDR workflow, exposure rides audio) ─────
    let exposure = 1.05 + plasmaGlow * 0.06 + mids * 0.2 + burst * 0.4;
    let outCol = acesToneMap(hdr * exposure);

    // Semantic alpha: luminous intensity shaped by the Thread Opacity slider
    let intensity = luma(outCol);
    let threadOpacityExp = u.zoom_params.w;
    let alpha = pow(clamp(intensity * 1.8, 0.0, 1.0), threadOpacityExp);

    textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(writeTexture, pixel, vec4<f32>(outCol, alpha));
}
