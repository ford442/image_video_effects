// ----------------------------------------------------------------
// Crystalline Nebula-Weaver Void-Spider — Batch 63
// Category: generative
// The weaver works fast: skittering gait, psychedelic crystalline
// spectra, faceted carapace + multi-tier web detail, spring-cursor
// gravity drag, held lunge, capped click web-snap rings.
// Contract: 13 bindings, ACES, semantic alpha, dataTextureA writeback only,
//           exact textureLoad from dataTextureC, plasmaBuffer three-band audio,
//           bounded extraBuffer[133..138] state.
// ----------------------------------------------------------------
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
    zoom_config: vec4<f32>,  // x=Time, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Web Complexity, y=Gravity Distortion, z=Plasma Intensity, w=Void Depth
    ripples: array<vec4<f32>, 50>
}

const TAU: f32 = 6.28318530718;

const SPRING_X: i32 = 133;
const SPRING_Y: i32 = 134;
const SPRING_VX: i32 = 135;
const SPRING_VY: i32 = 136;
const SPRING_T: i32 = 137;
const SPRING_INIT: i32 = 138;

var<private> g_bass: f32;
var<private> g_mids: f32;
var<private> g_treble: f32;
var<private> g_held: f32;
var<private> g_snap: f32;

// ----------------------------------------------------------------
// Hash-based value noise + fbm
// ----------------------------------------------------------------

fn hash3(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.3183099 + vec3<f32>(0.1, 0.2, 0.3)) * 17.0;
    return fract(q.x * q.y * q.z * (q.x + q.y + q.z));
}

fn vnoise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), hash3(i + vec3<f32>(1.0, 0.0, 0.0)), s.x),
            mix(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), hash3(i + vec3<f32>(1.0, 1.0, 0.0)), s.x), s.y),
        mix(mix(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), hash3(i + vec3<f32>(1.0, 0.0, 1.0)), s.x),
            mix(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), hash3(i + vec3<f32>(1.0, 1.0, 1.0)), s.x), s.y),
        s.z);
}

const FBM_ROT = mat3x3<f32>(
    vec3<f32>( 0.00,  0.80,  0.60),
    vec3<f32>(-0.80,  0.36, -0.48),
    vec3<f32>(-0.60, -0.48,  0.64)
);

fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        value += amplitude * vnoise(pos);
        pos = FBM_ROT * pos * 2.03;
        amplitude *= 0.5;
    }
    return value;
}

// Psychedelic crystalline spectrum — the cosine palette, spun by the audio
fn palette(t: f32) -> vec3<f32> {
    let drive = g_mids * 1.2 + g_snap;
    let d = vec3<f32>(0.263, 0.416 + drive * 0.25, 0.557 - drive * 0.2);
    return 0.5 + 0.5 * cos(TAU * (t + d));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn rot2(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ----------------------------------------------------------------
// Spider Geometry — faceted carapace, skittering articulated legs
// ----------------------------------------------------------------

fn sdSpider(p: vec3<f32>, audioReact: f32, time: f32) -> f32 {
    // Abdomen and cephalothorax
    let abdomen = length(p * vec3<f32>(1.0, 1.5, 1.0)) - (1.0 + audioReact * 0.25 + g_snap * 0.2);
    let head = length(p - vec3<f32>(0.0, 0.0, 1.5)) - 0.7;
    var body = smin(abdomen, head, 0.5);

    // Faceted crystalline carapace (geometric detail)
    let facet = sin(p.x * 9.0) * sin(p.y * 9.0) * sin(p.z * 9.0);
    body -= facet * 0.035;
    let plates = abs(sin(atan2(p.z, p.x) * 8.0 + p.y * 4.0));
    body -= plates * 0.02;

    // Legs — fast skittering gait, mirrored and articulated
    var pLeg = p;
    pLeg.x = abs(pLeg.x) - 1.5;
    let gait = sin(time * (7.0 + g_bass * 6.0) + floor(pLeg.z * 1.5) * 1.7) * (0.22 + g_held * 0.2);
    let kneed = rot2(gait) * pLeg.yz;
    pLeg.y = kneed.x;
    pLeg.z = kneed.y;
    var leg = length(max(abs(pLeg) - vec3<f32>(0.2, 2.0, 0.2), vec3<f32>(0.0))) - 0.1;
    // Chitin ridging along each limb
    leg -= sin(pLeg.y * 26.0) * 0.008;

    return smin(body, leg, 0.2);
}

// ----------------------------------------------------------------
// Web and Environment Geometry — three tiers of thread
// ----------------------------------------------------------------

fn sdWeb(p: vec3<f32>) -> f32 {
    let web_complexity = max(u.zoom_params.x, 0.05);
    let p_scaled = p * web_complexity;
    let thread1 = length(p_scaled.xy) - 0.02;
    let thread2 = length(fract(p_scaled * 2.0) - vec3<f32>(0.5)) - 0.01;
    // Third tier: fine cross-bracing filaments (geometric detail)
    let thread3 = length(fract(p_scaled * 5.0) - vec3<f32>(0.5)) - 0.004;
    return min(min(thread1, thread2), thread3) / web_complexity;
}

fn displace(p: vec3<f32>, time: f32, mouse: vec2<f32>) -> vec3<f32> {
    let gravity_distortion = u.zoom_params.y * (1.0 + g_held * 0.8 + g_snap);
    let distortedP = p + vec3<f32>(fbm(p + vec3<f32>(time * 2.2))) * gravity_distortion;
    return distortedP - vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);
}

fn map(p: vec3<f32>, time: f32, audioReact: f32, mouse: vec2<f32>) -> f32 {
    let displacedP = displace(p, time, mouse);
    let spider = sdSpider(displacedP, audioReact, time);
    let web = sdWeb(displacedP) + fbm(p) * 0.1;
    return min(spider, web);
}

fn calcNormal(p: vec3<f32>, time: f32, audioReact: f32, mouse: vec2<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.002, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, audioReact, mouse) - map(p - e.xyy, time, audioReact, mouse),
        map(p + e.yxy, time, audioReact, mouse) - map(p - e.yxy, time, audioReact, mouse),
        map(p + e.yyx, time, audioReact, mouse) - map(p - e.yyx, time, audioReact, mouse)
    ));
}

fn hueClamp(col: vec3<f32>, limit: f32) -> vec3<f32> {
    let peak = max(col.r, max(col.g, col.b));
    return col * (limit / max(peak, limit));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let y = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
    return clamp(y, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ----------------------------------------------------------------
// Main Raymarching and Shading
// ----------------------------------------------------------------

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (global_id.x >= dimensions.x || global_id.y >= dimensions.y) { return; }

    let coord = vec2<i32>(global_id.xy);
    let dims = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let idf = vec2<f32>(f32(global_id.x), f32(global_id.y));
    let uv01 = idf / dims;
    let uv = (idf - 0.5 * dims) / dims.y;
    let aspect = vec2<f32>(dims.x / max(dims.y, 1.0), 1.0);

    let time = u.config.x;
    g_bass = plasmaBuffer[0].x;
    g_mids = plasmaBuffer[0].y;
    g_treble = plasmaBuffer[0].z;

    let rawMouse = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;
    g_held = select(0.0, 1.0, held);

    // ── spring cursor (extraBuffer[133..138] only) ──────────────────────
    var smoothMouse = rawMouse;
    let hasSpring = arrayLength(&extraBuffer) > 138u;
    if (hasSpring && extraBuffer[SPRING_INIT] > 0.5) {
        smoothMouse = vec2<f32>(extraBuffer[SPRING_X], extraBuffer[SPRING_Y]);
    }
    if (hasSpring && global_id.x == 0u && global_id.y == 0u) {
        var springPos = smoothMouse;
        var springVel = vec2<f32>(extraBuffer[SPRING_VX], extraBuffer[SPRING_VY]);
        if (extraBuffer[SPRING_INIT] <= 0.5) {
            springPos = rawMouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[SPRING_T], 0.001, 0.05);
            let omega = 10.0;
            let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[SPRING_X] = springPos.x;
        extraBuffer[SPRING_Y] = springPos.y;
        extraBuffer[SPRING_VX] = springVel.x;
        extraBuffer[SPRING_VY] = springVel.y;
        extraBuffer[SPRING_T] = time;
        extraBuffer[SPRING_INIT] = 1.0;
        smoothMouse = springPos;
    }

    // ── click web-snap rings (capped, bounded) ─────────────────────────
    var snap = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 1.3) {
            let front = abs(length((uv01 - rp.xy) * aspect) - age * 1.0);
            snap = max(snap, exp(-front * 30.0) * (1.0 - age / 1.3));
        }
    }
    snap = min(snap, 1.0);
    g_snap = snap;

    let mouse = smoothMouse;
    let audioBass = g_bass;
    let audioTreble = g_treble;

    // Ray setup — held lunges the camera in, snaps kick it back
    let void_depth = max(u.zoom_params.w, 0.05);
    let ro = vec3<f32>(0.0, 0.0, -5.0 * void_depth + g_held * 0.9 - snap * 0.8);
    var rd = normalize(vec3<f32>(uv, 1.0));
    // Fast motion: the void rolls under the weaver, bass spins it harder
    let roll = rot2(time * (0.4 + g_bass * 0.9)) * rd.xy;
    rd = normalize(vec3<f32>(roll, rd.z));

    var t = 0.0;
    var d = 0.0;
    var glow = 0.0;
    let max_dist = 20.0 * void_depth;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        d = map(p, time, audioBass, mouse);
        glow += exp(-max(d, 0.0) * 6.0) * 0.02;
        if (d < 0.001 || t > max_dist) { break; }
        t += d;
    }

    let plasma_intensity = u.zoom_params.z;

    // Nebula background: fbm density graded through the psychedelic palette
    let nebDens = fbm(vec3<f32>(uv * 2.5, time * (0.6 + g_mids * 0.8)));
    var col = palette(nebDens + uv.x * 0.15 + time * (0.12 + g_treble * 0.4)) * nebDens * nebDens * 0.35;

    var depthNorm = 1.0;
    var fres = 0.0;
    if (t < max_dist) {
        let hitP = ro + rd * t;
        let n = calcNormal(hitP, time, audioBass, mouse);
        let lightDir = normalize(vec3<f32>(0.6, 0.8, -0.4));
        let diff = max(dot(n, lightDir), 0.0);
        fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        depthNorm = clamp(t / max_dist, 0.0, 1.0);

        let hueT = fbm(hitP * 0.7 + vec3<f32>(time * 0.45)) + time * (0.1 + g_treble * 0.5) + snap * 0.35;
        var surf = palette(hueT) * (0.25 + 0.75 * diff) * (1.0 - depthNorm * 0.8);
        surf += palette(hueT + 0.35) * fres * 1.3;

        // Facet banding — surfaces the carved carapace detail
        let facetBand = 0.5 + 0.5 * sin(hitP.x * 9.0) * sin(hitP.y * 9.0) * sin(hitP.z * 9.0);
        surf *= 0.8 + facetBand * 0.4;

        // Bass-lit plasma body
        surf += palette(hueT + 0.6) * audioBass * (0.5 + fres);

        // Treble glint hugging the web threads
        let webD = sdWeb(displace(hitP, time, mouse));
        let sparkle = pow(vnoise(hitP * 24.0 + vec3<f32>(time * 8.0)), 8.0);
        surf += vec3<f32>(0.9, 0.95, 1.0) * sparkle * audioTreble * exp(-max(webD, 0.0) * 24.0) * 6.0;

        col += surf * plasma_intensity;
    }

    // Crystalline glow gathered along the march
    col += palette(nebDens + 0.5 + time * 0.1) * glow * (0.6 + audioBass * 0.9) * (0.5 + plasma_intensity);

    // Web-snap flash + cursor drag halo
    col += palette(time * 0.9) * snap * 1.4;
    let cursorDist = length((uv01 - smoothMouse) * aspect);
    col += palette(time * 0.4 + cursorDist) * exp(-cursorDist * 7.5) * (0.12 + g_held * 0.45);

    // ── temporal feedback — exact load, no filtering ────────────────────
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(col, prev.rgb * 0.93, 0.07 + g_bass * 0.04);

    col = hueClamp(col, 2.0);
    col = aces(col * (1.0 + g_mids * 0.2));

    // Semantic alpha: weaver/web presence + crystalline glow
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(
        select(0.0, 0.45 + fres * 0.3, t < max_dist)
        + luma * 0.45 + min(glow, 2.0) * 0.18 + snap * 0.25,
        0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depthNorm, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
