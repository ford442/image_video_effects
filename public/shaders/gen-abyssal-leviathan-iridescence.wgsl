// ═══════════════════════════════════════════════════════════════════
//  Abyssal Leviathan Iridescence
//  Category: advanced-hybrid
//  Features: raymarching, thin-film-interference, spectral-render, mouse-driven
//  Complexity: Very High
//  Chunks From: gen-abyssal-leviathan-scales.wgsl, spec-iridescence-engine.wgsl
//  Created: 2026-04-18
//  By: Agent CB-20 — Generative Nature Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Leviathan scales rendered with physically-correct thin-film
//  interference. Each scale acts as an oil-slick surface where
//  viewing angle and film thickness determine spectral color.
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

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453); }
fn rot2D(a: f32) -> mat2x2<f32> { let c = cos(a); let s = sin(a); return mat2x2<f32>(c, -s, s, c); }

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + vec3<f32>(33.33));
    return fract((p3.x + p3.y) * p3.z);
}
fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let u = f*f*(vec3<f32>(3.0)-2.0*f); let n = i.x + i.y*157.0 + 113.0*i.z;
    return mix(mix(mix(hash31(vec3<f32>(n+0.0)), hash31(vec3<f32>(n+1.0)), u.x), mix(hash31(vec3<f32>(n+157.0)), hash31(vec3<f32>(n+158.0)), u.x), u.y), mix(mix(hash31(vec3<f32>(n+113.0)), hash31(vec3<f32>(n+114.0)), u.x), mix(hash31(vec3<f32>(n+270.0)), hash31(vec3<f32>(n+271.0)), u.x), u.y), u.z);
}
fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0; var w = 0.5; var pp = p;
    for (var i = 0; i < 4; i++) { f += w * noise3(pp); pp *= 2.0; w *= 0.5; }
    return f;
}

fn sdScale(p: vec3<f32>, size: vec2<f32>) -> f32 {
    let d = vec2<f32>(length(p.xz), p.y);
    return length(max(abs(d) - size, vec2<f32>(0.0))) + min(max(abs(d.x) - size.x, abs(d.y) - size.y), 0.0) - 0.1;
}

// ═══ CHUNK: wavelengthToRGB (from spec-iridescence-engine.wgsl) ═══
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
    let g = 1.0 - abs(t - 0.45) * 2.5;
    let b = 1.0 - smoothstep(0.0, 0.45, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

// ═══ CHUNK: thinFilmColor (from spec-iridescence-engine.wgsl) ═══
fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
    let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
    let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
    let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;
    var color = vec3<f32>(0.0);
    var sampleCount = 0.0;
    for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
        let phase = opd / lambda;
        let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
        color += wavelengthToRGB(lambda) * interference;
        sampleCount = sampleCount + 1.0;
    }
    return color / max(sampleCount, 1.0);
}

var<private> g_time: f32;
var<private> g_audio: f32;
var<private> g_mouse: vec2<f32>;

fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    let scaleDensity = max(1.0, u.zoom_params.x);
    let breathingSpeed = u.zoom_params.z;
    let spacing = 10.0 / scaleDensity;
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
    let fbmVal = fbm(vec3<f32>(cellId.x, cellId.y, g_time * breathingSpeed * 0.5));
    let localTime = g_time * breathingSpeed + fbmVal * 6.28;
    var lift = sin(localTime) * 0.2 + 0.2;
    var tilt = cos(localTime) * 0.3;
    let mouseWorld = vec2<f32>(g_mouse.x * 10.0, -g_mouse.y * 10.0 + g_time);
    let distToMouse = length(p.xz - mouseWorld);
    let repel = 1.0 - smoothstep(0.0, 5.0, distToMouse);
    lift += repel * 1.5;
    tilt += repel * 1.5;
    q.y -= lift;
    let rM = rot2D(tilt);
    let tmp = rM * vec2<f32>(q.y, q.z);
    q.y = tmp.x;
    q.z = tmp.y;
    let size = vec2<f32>(spacing * 0.45, 0.05);
    let dScale = sdScale(q, size);
    let plasmaWarp = fbm(p * 0.5 + vec3<f32>(0.0, 0.0, -g_time * 2.0));
    let dPlasma = p.y + 1.0 - plasmaWarp * 0.5;
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }
    var uv = (fragCoord * 2.0 - dims) / dims.y;
    g_time = u.config.x;
    g_audio = u.config.y * 0.1;
    let mX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mY = -(u.zoom_config.z / dims.y) * 2.0 + 1.0;
    g_mouse = vec2<f32>(mX, mY);

    var ro = vec3<f32>(0.0, 5.0, g_time);
    let ta = ro + vec3<f32>(0.0, -1.0, 1.0);
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
            glow += 0.01 / (0.01 + abs(d));
        }
        if (d < 0.001 || t > maxT) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    let plasmaIntensity = u.zoom_params.y;
    let coreHeat = u.zoom_params.w;
    let audioPulse = 1.0 + g_audio * 5.0;

    // Iridescence parameters
    let filmThicknessBase = mix(200.0, 800.0, u.zoom_params.y);
    let filmIOR = mix(1.2, 2.4, 0.3);
    let iridIntensity = mix(0.3, 1.5, u.zoom_params.z);

    if (t < maxT) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;

        if (m == 1.0) {
            let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
            let h = normalize(l + v);
            let ndotl = max(dot(n, l), 0.0);
            let ndoth = max(dot(n, h), 0.0);
            let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);

            // ═══ CHUNK: thin-film iridescence on scales ═══
            let cosTheta = sqrt(max(1.0 - (1.0 - max(dot(n, v), 0.0)) * 0.5, 0.01));
            let noiseVal = hash21(p.xz * 12.0 + g_time * 0.1) * 0.5
                         + hash21(p.xz * 25.0 - g_time * 0.15) * 0.25;
            var thickness = filmThicknessBase * (0.7 + noiseVal);
            let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * iridIntensity;

            let diff = vec3<f32>(0.05, 0.05, 0.06) * ndotl;
            let spec = iridescent * pow(ndoth, 32.0) * 0.5;
            col = diff + spec + iridescent * fresnel * 0.2;

            let plasmaProximity = exp(-p.y * 2.0);
            col += vec3<f32>(0.8, 0.2, 0.1) * plasmaProximity * 0.2 * plasmaIntensity * audioPulse;

        } else if (m == 2.0) {
            let heat = fbm(p * 2.0 - vec3<f32>(0.0, 0.0, g_time * 4.0)) * coreHeat;
            col = vec3<f32>(1.0, 0.2, 0.05) * heat * audioPulse * plasmaIntensity;
            col += vec3<f32>(0.1, 0.5, 1.0) * pow(heat, 3.0) * audioPulse * plasmaIntensity;
        }
    }

    col += vec3<f32>(1.0, 0.3, 0.1) * glow * 0.05 * plasmaIntensity * audioPulse * coreHeat;
    col = mix(col, vec3<f32>(0.01, 0.01, 0.02), 1.0 - exp(-t * 0.05));
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(t / maxT, 0.0, 0.0, 0.0));
}
