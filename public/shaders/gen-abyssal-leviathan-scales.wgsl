// ----------------------------------------------------------------
// Abyssal Leviathan-Scales — Batch 63
// Category: generative
// A hexagonal scale conveyor over a fissured plasma bed, driven at
// speed: psychedelic thin-film spectra, greebled scale ridging,
// spring-cursor repulsion wake, held flare, capped click breach rings.
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Scale Density, y=Plasma Intensity, z=Conveyor Speed, w=Core Heat
    ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

const SPRING_X: i32 = 133;
const SPRING_Y: i32 = 134;
const SPRING_VX: i32 = 135;
const SPRING_VY: i32 = 136;
const SPRING_T: i32 = 137;
const SPRING_INIT: i32 = 138;

// --- UTILITY FUNCTIONS ---
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453); }
fn rot2D(a: f32) -> mat2x2<f32> { let c = cos(a); let s = sin(a); return mat2x2<f32>(c, -s, s, c); }

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + vec3<f32>(33.33));
    return fract((p3.x + p3.y) * p3.z);
}
fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let u2 = f*f*(vec3<f32>(3.0)-2.0*f); let n = i.x + i.y*157.0 + 113.0*i.z;
    return mix(mix(mix(hash31(vec3<f32>(n+0.0)), hash31(vec3<f32>(n+1.0)), u2.x), mix(hash31(vec3<f32>(n+157.0)), hash31(vec3<f32>(n+158.0)), u2.x), u2.y), mix(mix(hash31(vec3<f32>(n+113.0)), hash31(vec3<f32>(n+114.0)), u2.x), mix(hash31(vec3<f32>(n+270.0)), hash31(vec3<f32>(n+271.0)), u2.x), u2.y), u2.z);
}
fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0; var w = 0.5; var pp = p;
    for (var i = 0; i < 4; i++) { f += w * noise3(pp); pp *= 2.0; w *= 0.5; }
    return f;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Psychedelic thin-film / plasma spectrum
fn scalePalette(t: f32, drive: f32) -> vec3<f32> {
    let phase = vec3<f32>(0.15, 2.0 + drive * 1.2, 4.2 - drive * 0.8);
    return 0.5 + 0.5 * cos(TAU * t + phase);
}

// --- SDF FUNCTIONS ---
fn sdScale(p: vec3<f32>, size: vec2<f32>) -> f32 {
    let d = vec2<f32>(length(p.xz), p.y);
    return length(max(abs(d) - size, vec2<f32>(0.0))) + min(max(abs(d.x) - size.x, abs(d.y) - size.y), 0.0) - 0.1;
}

var<private> g_time: f32;
var<private> g_audio: vec3<f32>;
var<private> g_mouse: vec2<f32>;
var<private> g_held: f32;
var<private> g_breach: f32;

fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    let scaleDensity = max(1.0, u.zoom_params.x);
    let breathingSpeed = u.zoom_params.z;
    let spacing = 10.0 / scaleDensity;

    // Hexagonal grid setup on XZ plane
    let grid = vec2<f32>(1.0, 1.7320508) * spacing;
    let h1 = p.xz % grid - grid * 0.5;
    let h2 = (p.xz + grid * 0.5) % grid - grid * 0.5;
    var cellPos = h1;
    var cellId = floor(p.xz / grid);
    if (length(h1) > length(h2)) {
        cellPos = h2;
        cellId = floor((p.xz + grid * 0.5) / grid) + 0.5;
    }

    var q = p;
    q.x = cellPos.x;
    q.z = cellPos.y;

    // Fast conveyor wave: rows snap over in bursts, breach events accelerate them
    let fbmVal = fbm(vec3<f32>(cellId.x, cellId.y, g_time * breathingSpeed * 0.9));
    let rowSpeed = 8.5 + breathingSpeed * 4.0 + g_audio.x * 3.5 + g_breach * 6.0;
    let rowWave = sin(cellId.y * 1.7 - g_time * rowSpeed);
    let localTime = g_time * breathingSpeed * 3.5 + fbmVal * 6.28 + rowWave * 0.8;

    var lift = sin(localTime) * 0.2 + 0.2 + max(rowWave, 0.0) * (0.22 + g_audio.x * 0.16);
    var tilt = cos(localTime) * 0.3 + rowWave * 0.28;

    // Mouse repulsion — the smoothed cursor shoves scales open ahead of it
    let mouseWorld = vec2<f32>(g_mouse.x * 10.0, g_mouse.y * 7.0 + g_time * 3.4);
    let distToMouse = length(p.xz - mouseWorld);
    let repel = 1.0 - smoothstep(0.0, 5.0 + g_held * 2.5, distToMouse);
    lift += repel * (1.5 + g_held * 1.2);
    tilt += repel * (1.5 + g_held * 0.8);

    q.y -= lift;
    let rM = rot2D(tilt);
    let tmp = rM * vec2<f32>(q.y, q.z);
    q.y = tmp.x;
    q.z = tmp.y;

    // Scale SDF with concentric keel ridging (geometric detail)
    let size = vec2<f32>(spacing * 0.45, 0.05);
    var dScale = sdScale(q, size);
    let keel = sin(length(q.xz) * 34.0 - g_time * 5.0) * 0.006;
    let facets = sin(atan2(q.z, q.x) * 12.0) * 0.004;
    dScale -= keel + facets;

    // Plasma bed, domain-warped and fissured
    let plasmaWarp = fbm(p * 0.5 + vec3<f32>(g_time * 1.6, 0.0, -g_time * 7.5));
    let fissure = pow(abs(sin(p.x * 2.4 + p.z * 1.2 - g_time * (14.0 + g_audio.z * 4.0))), 12.0);
    let dPlasma = p.y + 1.0 - plasmaWarp * 0.5 - fissure * (0.08 + g_audio.y * 0.1);

    if (dScale < dPlasma) {
        return vec2<f32>(dScale * 0.6, 1.0);
    }
    return vec2<f32>(dPlasma * 0.6, 2.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let coord = vec2<i32>(id.xy);
    var uv = (fragCoord * 2.0 - dims) / dims.y;
    let dataUV = fragCoord / dims;
    let aspectFix = vec2<f32>(dims.x / max(dims.y, 1.0), 1.0);
    g_time = u.config.x;
    g_audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

    let rawMouse = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;
    g_held = select(0.0, 1.0, held);

    // ── spring cursor (extraBuffer[133..138] only) ──────────────────────
    var smoothMouse = rawMouse;
    let hasSpring = arrayLength(&extraBuffer) > 138u;
    if (hasSpring && extraBuffer[SPRING_INIT] > 0.5) {
        smoothMouse = vec2<f32>(extraBuffer[SPRING_X], extraBuffer[SPRING_Y]);
    }
    if (hasSpring && id.x == 0u && id.y == 0u) {
        var springPos = smoothMouse;
        var springVel = vec2<f32>(extraBuffer[SPRING_VX], extraBuffer[SPRING_VY]);
        if (extraBuffer[SPRING_INIT] <= 0.5) {
            springPos = rawMouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(g_time - extraBuffer[SPRING_T], 0.001, 0.05);
            let omega = 10.0;
            let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[SPRING_X] = springPos.x;
        extraBuffer[SPRING_Y] = springPos.y;
        extraBuffer[SPRING_VX] = springVel.x;
        extraBuffer[SPRING_VY] = springVel.y;
        extraBuffer[SPRING_T] = g_time;
        extraBuffer[SPRING_INIT] = 1.0;
        smoothMouse = springPos;
    }
    g_mouse = (smoothMouse - 0.5) * 2.0;

    // ── click breaches race down the conveyor (capped, bounded) ─────────
    var breach = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var r = 0u; r < rippleCount; r++) {
        let ripple = u.ripples[r];
        let age = g_time - ripple.z;
        if (age < 0.0 || age > 2.0) { continue; }
        let delta = (dataUV - ripple.xy) * aspectFix;
        let front = abs(length(delta) - age * (1.1 + u.zoom_params.z * 0.3));
        breach += exp(-front * 55.0) * (1.0 - age * 0.5);
    }
    breach = min(breach, 1.5);
    g_breach = breach;

    // Camera — the conveyor runs fast, audio and held throttle it further
    let runSpeed = 6.5 + u.zoom_params.z * 2.2 + g_audio.x * 1.6 + g_held * 2.5;
    var ro = vec3<f32>(0.0, 5.0, g_time * runSpeed);
    let ta = ro + vec3<f32>(g_mouse.x * 0.6, -1.0 + g_mouse.y * 0.3, 1.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    var t = 0.0;
    var d = 0.0;
    var m = 0.0;
    var glow = 0.0;
    let maxT = 30.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        if (m == 2.0) {
            glow += min(0.12, 0.004 / (0.01 + abs(d)));
        }
        if (d < 0.001 || t > maxT) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    var fres = 0.0;
    let plasmaIntensity = u.zoom_params.y;
    let coreHeat = u.zoom_params.w;
    let audioPulse = 1.0 + g_audio.x * 1.5;

    if (t < maxT) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;

        if (m == 1.0) {
            // Oily metallic scale — thin-film interference pushed into full spectrum
            let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
            let h = normalize(l + v);
            let ndotl = max(dot(n, l), 0.0);
            let ndoth = max(dot(n, h), 0.0);
            fres = pow(1.0 - max(dot(n, v), 0.0), 5.0);

            let filmT = fres * 2.4 + g_time * (0.25 + g_audio.z * 0.9) + p.z * 0.05;
            let sheen = scalePalette(filmT, g_audio.y * 1.4);
            let diff = vec3<f32>(0.05, 0.05, 0.06) * ndotl;
            let spec = sheen * pow(ndoth, 32.0) * 0.85;

            col = diff + spec + sheen * fres * 0.55;

            // Keel ridging shading — reads the carved geometry back as highlight bands
            let ridge = 0.5 + 0.5 * sin(length(p.xz % vec2<f32>(1.0) - 0.5) * 34.0 - g_time * 5.0);
            col *= 0.82 + ridge * 0.36;

            // Plasma bleed from below
            let plasmaProximity = exp(-p.y * 2.0);
            col += scalePalette(filmT + 0.45, 1.0) * plasmaProximity * 0.35 * plasmaIntensity * audioPulse;

        } else if (m == 2.0) {
            // Quantum fusion core — fast runners across the fissures
            let runner = pow(abs(sin(p.z * 3.0 - g_time * 22.0 + p.x)), 16.0);
            let heat = (fbm(p * 2.0 - vec3<f32>(0.0, 0.0, g_time * 12.0)) + runner * 0.55) * coreHeat;
            let hue = fract(heat * 0.6 + g_time * (0.2 + g_audio.y * 0.7));
            col = scalePalette(hue, g_audio.z * 1.5) * heat * audioPulse * plasmaIntensity;
            col += scalePalette(hue + 0.4, 1.0) * pow(heat, 3.0) * audioPulse * plasmaIntensity;
        }
    }

    // Volumetric glow, spectrally graded
    col += scalePalette(g_time * 0.3 + glow * 0.2, g_audio.x) * min(glow, 4.0) * 0.1 * plasmaIntensity * audioPulse * coreHeat;

    // Background fade (fog)
    col = mix(col, vec3<f32>(0.01, 0.01, 0.02), 1.0 - exp(-t * 0.05));

    // Breach flash + cursor wake halo
    col += scalePalette(g_time * 0.8, 1.0) * breach * 1.2;
    let cursorDist = length((dataUV - smoothMouse) * aspectFix);
    col += scalePalette(g_time * 0.5 + cursorDist, g_audio.y) * exp(-cursorDist * 8.0) * (0.12 + g_held * 0.5);

    col = acesToneMap(col * (1.1 + g_audio.y * 0.25));

    // Semantic alpha: surface presence + plasma energy
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(
        select(0.0, 0.45 + fres * 0.3, t < maxT)
        + luma * 0.45 + min(glow, 2.0) * 0.15 + breach * 0.3,
        0.0, 1.0);

    // Exact previous-frame state — no filtering
    let prev = textureLoad(dataTextureC, coord, 0);
    let temporal = clamp(max(col, prev.rgb * 0.9), vec3<f32>(0.0), vec3<f32>(5.0));
    let depth = select(1.0, clamp(t / maxT, 0.0, 0.995), t < maxT);

    textureStore(dataTextureA, coord, vec4<f32>(temporal, alpha));
    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
