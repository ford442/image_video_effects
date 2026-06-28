// ═══════════════════════════════════════════════════════════════════
//  Crystalline Chrono-Dyson — Algorithmist Upgrade
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, chromatic,
//            depth-aware, Worley, KIFS, Fresnel-Schlick,
//            Beer-Lambert, domain-warping
//  Complexity: Very High
//  Upgraded: 2026-06-28
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Panel Density, y=Quasar Glow, z=Flux Speed, w=Swarm Count
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const PHI: f32 = 1.618033988749895;

fn fmod(x: f32, y: f32) -> f32 { return x - y * floor(x / y); }
fn rot2D(a: f32) -> mat2x2<f32> { let s = sin(a); let c = cos(a); return mat2x2<f32>(c, -s, s, c); }

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn hash1(p: vec3<f32>) -> f32 { return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453); }

fn vnoise(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let s = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash1(i), hash1(i + vec3<f32>(1.0, 0.0, 0.0)), s.x),
                   mix(hash1(i + vec3<f32>(0.0, 1.0, 0.0)), hash1(i + vec3<f32>(1.0, 1.0, 0.0)), s.x), s.y),
               mix(mix(hash1(i + vec3<f32>(0.0, 0.0, 1.0)), hash1(i + vec3<f32>(1.0, 0.0, 1.0)), s.x),
                   mix(hash1(i + vec3<f32>(0.0, 1.0, 1.0)), hash1(i + vec3<f32>(1.0, 1.0, 1.0)), s.x), s.y), s.z);
}

fn fbm(p: vec3<f32>, oct: i32) -> f32 {
    var v = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < 6; i++) { if (i >= oct) { break; } v += a * vnoise(p * f); f *= 2.0; a *= 0.5; }
    return v;
}

fn worley(p: vec3<f32>, density: f32) -> vec2<f32> {
    let n = floor(p * density); let f = fract(p * density);
    var md = 100.0; var md2 = 100.0;
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            for (var k: i32 = -1; k <= 1; k++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let r = g + o - f;
                let d = dot(r, r);
                if (d < md) { md2 = md; md = d; }
                else if (d < md2) { md2 = d; }
            }
        }
    }
    return vec2<f32>(sqrt(md), sqrt(md2) - sqrt(md));
}

fn domainWarp(p: vec3<f32>, t: f32) -> vec3<f32> {
    return p + vec3<f32>(fbm(p + vec3<f32>(0.0, 0.0, t), 3), fbm(p + vec3<f32>(5.2, 1.3, t), 3), fbm(p + vec3<f32>(1.7, 9.2, t), 3)) * 0.4;
}

fn fresnel(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> { return f0 + (vec3<f32>(1.0) - f0) * pow(1.0 - cosTheta, 5.0); }
fn smin(a: f32, b: f32, k: f32) -> f32 { let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }

fn sdSphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 { let d = abs(p) - b; return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, vec3<f32>(0.0))); }

fn kifsFold(p: vec3<f32>, normal: vec3<f32>, d: f32) -> vec3<f32> { let t = dot(p, normal) - d; return p - 2.0 * min(0.0, t) * normal; }

fn map(p: vec3<f32>) -> f32 {
    let audio = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
    let t = u.config.x * u.zoom_params.z; let density = u.zoom_params.x;
    var q = p;
    // Rotate entire Dyson sphere
    let a = t * 0.1; let rx = rot2D(a) * q.xz; q.x = rx.x; q.z = rx.y;
    // KIFS crystal fractal inside panel space
    var kq = q; var scale = 1.0;
    for (var i = 0; i < 4; i++) {
        kq = abs(kq) - vec3<f32>(0.3, 0.3, 0.3);
        let xy = rot2D(0.5 + treble * 0.2) * vec2<f32>(kq.x, kq.y); kq.x = xy.x; kq.y = xy.y;
        let yz = rot2D(0.3 + mids * 0.1) * vec2<f32>(kq.y, kq.z); kq.y = yz.x; kq.z = yz.y;
        scale *= 1.2; kq *= 1.2;
    }
    let kifs = sdBox(kq, vec3<f32>(0.1, 0.1, 0.01)) / scale;
    // Domain repetition for crystal panels
    var panel_q = fract(q * density) - 0.5;
    let w = worley(q * 0.5 + t * 0.05, density * 2.0);
    let crystal = sdBox(panel_q, vec3<f32>(0.15 + w.x * 0.05, 0.15 + w.y * 0.05, 0.01)) - 0.01;
    // Dyson shell
    let shell = abs(length(q) - 2.0) - 0.1;
    let panels = max(shell, crystal);
    // Central quasar with FBM turbulence
    let qwarp = domainWarp(q * 0.5, t * 0.3);
    let quasar = sdSphere(q, 0.5 + sin(t * 5.0 + q.x * 10.0) * 0.05 * audio) + fbm(qwarp, 3) * 0.1;
    // Plasma conduits between panels
    let conduit = sdTorus(q, vec2<f32>(1.8 + sin(t * 2.0) * 0.2, 0.02 + audio * 0.03));
    let h = 0.5; let blend = clamp(0.5 + 0.5 * (panels - quasar) / h, 0.0, 1.0);
    var d = mix(panels, quasar, blend) - h * blend * (1.0 - blend);
    d = smin(d, kifs, 0.15);
    d = smin(d, conduit, 0.08);
    return d;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 { let q = vec2<f32>(length(p.xz) - t.x, p.y); return length(q) - t.y; }

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p); let e = vec2<f32>(0.001, 0.0);
    return normalize(d - vec3<f32>(map(p - e.xyy), map(p - e.yxy), map(p - e.yyx)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy); let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) { return; }
    let uv01 = vec2<f32>(coords) / res; let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;
    let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
    var ro = vec3<f32>(0.0, 0.0, -5.0); var rd = normalize(vec3<f32>(uv, 1.0));
    // Mouse orbital camera (Y-flip: screen-top = +Y/up)
    let mx = (u.zoom_config.y - 0.5) * 6.28; let my = (0.5 - u.zoom_config.z) * 3.14;
    let ro_xz = rot2D(mx) * vec2<f32>(ro.x, ro.z); ro.x = ro_xz.x; ro.z = ro_xz.y;
    let ro_yz = rot2D(my) * vec2<f32>(ro.y, ro.z); ro.y = ro_yz.x; ro.z = ro_yz.y;
    let cw = normalize(-ro); let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0))); let cv = cross(cu, cw);
    rd = normalize(uv.x * cu + uv.y * cv + 1.0 * cw);
    // Gravity well warp
    let warp = 1.0 - smoothstep(0.0, 0.5, length(uv));
    rd = normalize(rd + vec3<f32>(warp * 0.1 * sin(u.config.x), warp * 0.1 * cos(u.config.x), 0.0));
    var t = 0.0; var hit = false;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t; let d = map(p);
        if (d < 0.001) { hit = true; break; }
        if (t > 20.0) { break; }
        t += d;
    }
    var col = vec3<f32>(0.0);
    if (hit) {
        let p = ro + rd * t; let n = getNormal(p); let v = -rd;
        let quasar_glow = u.zoom_params.y; let audio_pulse = 1.0 + bass * 0.5;
        let dist_to_center = length(p);
        let gradient = mix(vec3<f32>(0.2, 0.0, 0.5), vec3<f32>(1.0, 0.8, 0.2), 1.0 - smoothstep(0.0, 2.0, dist_to_center));
        let f0 = vec3<f32>(0.04, 0.02, 0.01); let fres = fresnel(max(dot(n, v), 0.0), f0);
        col = gradient * quasar_glow * audio_pulse / (t * 0.5 + 0.1);
        col += fres * (0.5 + mids * 0.5);
        // Crystal subsurface scattering via Beer-Lambert
        let thickness = clamp(2.0 - dist_to_center, 0.0, 2.0);
        let transmittance = exp(-thickness * 0.8);
        col += vec3<f32>(0.1, 0.3, 0.6) * transmittance * (1.0 + treble);
        // Swarm drones
        let swarm = u.zoom_params.w;
        col += vec3<f32>(0.1, 0.8, 1.0) * smoothstep(0.9, 1.0, sin(t * swarm + u.config.x + dist_to_center * 3.0));
    } else { col = vec3<f32>(0.05, 0.05, 0.1) * hash3(rd).x; }
    // Temporal feedback with chromatic dispersion
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0);
    col = mix(col, prev.rgb * 0.9, 0.03 + bass * 0.01);
    let cStr = 0.003 + bass * 0.005; let cDir = normalize(uv01 - vec2<f32>(0.5) + 0.001);
    let prevR = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (1.0 + mids), 0.0).r;
    let prevG = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (0.5 + treble), 0.0).g;
    let prevB = textureSampleLevel(dataTextureC, u_sampler, uv01 - cDir * cStr * (0.8 + bass * 0.5), 0.0).b;
    col.r = mix(col.r, prevR * 0.9, 0.02 + treble * 0.01);
    col.g = mix(col.g, prevG * 0.9, 0.02 + bass * 0.01);
    col.b = mix(col.b, prevB * 0.9, 0.02 + mids * 0.01);
    let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(lum * 0.7 + 0.2, 0.0, 1.0);
    textureStore(writeTexture, coords, vec4<f32>(col, alpha));
    let d_uv = clamp(vec2<f32>(coords) / res, vec2<f32>(0.0), vec2<f32>(1.0));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, d_uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(col, alpha));
}
