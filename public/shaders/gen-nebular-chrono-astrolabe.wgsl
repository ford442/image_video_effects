// ═══════════════════════════════════════════════════════════════════
//  Nebular Chrono-Astrolabe — Algorithmist Upgrade
//  Category: generative
//  Features: generative, mouse-driven, audio-reactive, temporal,
//            depth-aware, upgraded-rgba, FBM, domain-warping,
//            curl-noise, Beer-Lambert, Fresnel-Schlick
//  Complexity: Very High
//  Upgraded: 2026-08-03 (Batch 33)
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const PHI: f32 = 1.618033988749895;
const MAX_STEPS: i32 = 80;
const MAX_DIST: f32 = 80.0;
const SURF_DIST: f32 = 0.001;

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn hash1(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

fn vnoise(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash1(i), hash1(i+vec3<f32>(1,0,0)), s.x),
                   mix(hash1(i+vec3<f32>(0,1,0)), hash1(i+vec3<f32>(1,1,0)), s.x), s.y),
               mix(mix(hash1(i+vec3<f32>(0,0,1)), hash1(i+vec3<f32>(1,0,1)), s.x),
                   mix(hash1(i+vec3<f32>(0,1,1)), hash1(i+vec3<f32>(1,1,1)), s.x), s.y), s.z);
}

fn fbm(p: vec3<f32>, oct: i32) -> f32 {
    var v = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < 6; i++) { if (i >= oct) { break; } v += a * vnoise(p * f); f *= 2.0; a *= 0.5; }
    return v;
}

fn domainWarp(p: vec3<f32>, t: f32) -> vec3<f32> {
    return p + vec3<f32>(fbm(p+vec3<f32>(0,0,t),3), fbm(p+vec3<f32>(5.2,1.3,t),3), fbm(p+vec3<f32>(1.7,9.2,t),3)) * 0.5;
}

fn curl(p: vec3<f32>, t: f32) -> vec3<f32> {
    let e = 0.01;
    let n1 = vnoise(p+vec3<f32>(e,0,0)+t); let n2 = vnoise(p-vec3<f32>(e,0,0)+t);
    let n3 = vnoise(p+vec3<f32>(0,e,0)+t); let n4 = vnoise(p-vec3<f32>(0,e,0)+t);
    let n5 = vnoise(p+vec3<f32>(0,0,e)+t); let n6 = vnoise(p-vec3<f32>(0,0,e)+t);
    let dx = (n1-n2)/(2.0*e); let dy = (n3-n4)/(2.0*e); let dz = (n5-n6)/(2.0*e);
    return vec3<f32>(dy-dz, dz-dx, dx-dy);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 { let q = vec2<f32>(length(p.xz)-t.x, p.y); return length(q)-t.y; }
fn sdSphere(p: vec3<f32>, r: f32) -> f32 { return length(p)-r; }
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 { let d = abs(p)-b; return min(max(d.x,max(d.y,d.z)),0.0)+length(max(d,vec3<f32>(0.0))); }
fn smin(a: f32, b: f32, k: f32) -> f32 { let h = clamp(0.5+0.5*(b-a)/k,0.0,1.0); return mix(b,a,h)-k*h*(1.0-h); }
fn rot2D(a: f32) -> mat2x2<f32> { let s = sin(a); let c = cos(a); return mat2x2<f32>(c,-s,s,c); }
fn fresnel(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> { return f0 + (vec3<f32>(1.0)-f0)*pow(1.0-cosTheta,5.0); }
fn beer(d: f32, density: f32) -> f32 { return exp(-density*d); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn map(p: vec3<f32>) -> vec2<f32> {
    let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let t = u.config.x * u.zoom_params.x;
    var d = MAX_DIST; var mat_id = 0.0;
    var p1 = p;
    let raw_mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let sprung_mouse = select(raw_mouse, vec2<f32>(extraBuffer[133], extraBuffer[134]), extraBuffer[137] > 0.5);
    let mouse_pos = vec3<f32>((sprung_mouse.x-0.5)*5.0, (sprung_mouse.y-0.5)*5.0, 0.0);
    let dtm = length(p1-mouse_pos);
    p1 += (mouse_pos-p1)/max(dtm,0.001)*(1.0/(dtm*dtm+0.5))*u.zoom_params.w*(1.0+bass*2.0);
    p1 += curl(p1*0.3, t*0.1)*(0.2+mids*0.3);
    let core = sdSphere(p1, 0.5+bass*0.15);
    d = core; mat_id = 1.0;
    let num_rings = i32(u.zoom_params.y);
    for (var i = 0; i < 6; i++) {
        if (i >= num_rings) { break; }
        let fi = f32(i); var pr = p1;
        pr += vnoise(pr*0.5+fi*0.3)*0.3;
        let a1 = rot2D(t*0.5+bass*2.0+fi*0.5)*pr.yz; pr.y=a1.x; pr.z=a1.y;
        let a2 = rot2D(t*0.2*u.zoom_params.x+fi*1.2)*pr.xz; pr.x=a2.x; pr.z=a2.y;
        let ring = sdTorus(pr, vec2<f32>(1.5+fi*0.4+fi*0.1, 0.05+fi*0.02+bass*0.02));
        if (ring < d) { d = smin(d, ring, 0.1+fi*0.05); mat_id = 2.0+fi*0.5; }
    }
    let sat_pos = vec3<f32>(cos(t*0.3+bass*0.5)*3.0, sin(t*0.3+bass*0.5)*1.5, sin(t*0.21+bass*0.35)*2.0);
    let sat = sdBox(p1-sat_pos, vec3<f32>(0.1,0.3,0.05));
    if (sat < d) { d = sat; mat_id = 5.0; }
    return vec2<f32>(d, mat_id);
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec4<f32> {
    let bass = plasmaBuffer[0].x; let treble = plasmaBuffer[0].z;
    var dO = 0.0; var mat = 0.0; var glow = 0.0;
    let nd = 0.15+u.zoom_params.z*0.1;
    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO; let dS = map(p);
        dO += max(dS.x * 0.8, 0.002); mat = dS.y;
        glow += max(0.0, 0.05-dS.x)*u.zoom_params.z*(1.0+bass*0.5);
        if (dO > MAX_DIST || abs(dS.x) < SURF_DIST) { break; }
    }
    return vec4<f32>(dO, mat, glow, beer(dO, nd));
}

fn sampleNebula(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    let treble = plasmaBuffer[0].z;
    var nebula = vec3<f32>(0.0);
    for (var i = 0; i < 8; i = i + 1) {
        let fi = f32(i);
        let p = ro + rd * (1.0 + fi * 1.4);
        let warped = domainWarp(p * 0.18, u.config.x * 0.04);
        let cloud = fbm(warped, 3) * exp(-fi * 0.18);
        let tint = vec3<f32>(0.05, 0.16, 0.38) + vec3<f32>(0.22, 0.04, 0.3) * (0.5 + 0.5 * sin(p.y + u.config.x * 0.1));
        nebula += tint * cloud * (0.08 + treble * 0.025);
    }
    return nebula;
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p).x; let e = vec2<f32>(0.001, 0.0);
    return normalize(d - vec3<f32>(map(p-e.xyy).x, map(p-e.yxy).x, map(p-e.yyx).x));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(id.xy)*2.0-res)/res.y;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }
    let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
    let uv01 = vec2<f32>(id.xy)/res;
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { mouse = rawMouse; mouseVelocity = vec2<f32>(0.0); }
    let springDt = select(0.016, clamp(u.config.x - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let springOmega = 7.0;
    mouseVelocity += ((rawMouse - mouse) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
    mouse += mouseVelocity * springDt;
    if (id.x == 0u && id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = mouse.x; extraBuffer[134] = mouse.y;
        extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = u.config.x;
    }
    let ro = vec3<f32>(0.0, 0.0, -10.0); let rd = normalize(vec3<f32>(uv, 1.0));
    let rm = raymarch(ro, rd); let d = rm.x; let mat = rm.y; let glow = rm.z; let trans = rm.w;
    var col = vec3<f32>(0.0); var alpha = 0.3;
    if (d < MAX_DIST) {
        let p = ro + rd * d; let n = getNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0)); let diff = max(dot(n, l), 0.0);
        let v = -rd; let fres = fresnel(max(dot(n, v), 0.0), vec3<f32>(0.04, 0.08, 0.12));
        if (mat == 1.0) { col = vec3<f32>(0.2,0.8,1.0)*diff+vec3<f32>(0.0,0.4,0.8)*0.5+fres*(0.5+bass*0.5); }
        else if (mat >= 2.0 && mat < 5.0) { let rc = vec3<f32>(1.0,0.8,0.2)*(1.0-(mat-2.0)*0.2); col = rc*diff+vec3<f32>(0.8,0.4,0.0)*0.5+fres*(0.3+mids*0.3); }
        else if (mat == 5.0) { col = vec3<f32>(0.9,0.95,1.0)*diff+fres*0.8; }
        alpha = 0.85;
    } else { col = vec3<f32>(0.01, 0.02, 0.05); }
    col += sampleNebula(ro, rd);
    col += vec3<f32>(0.1,0.4,0.8)*glow*0.5;
    col *= trans; col += vec3<f32>(0.05,0.15,0.35)*glow*(1.0+treble);
    var clickGravity = 0.0;
    let aspect = res.x / res.y;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = u.config.x - ripple.z;
        if (age >= 0.0 && age < 2.2) {
            let radius = length((uv01 - ripple.xy) * vec2<f32>(aspect, 1.0));
            clickGravity = max(clickGravity, exp(-abs(radius - age * 0.22) * 60.0) * exp(-age * 1.5));
        }
    }
    col += vec3<f32>(0.25, 0.65, 1.2) * clickGravity * (0.45 + mids * 0.25);
    let prev = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);
    col = mix(col, prev.rgb*0.92, 0.04+bass*0.02);
    col = acesToneMap(max(col, vec3<f32>(0.0)));
    let lum = dot(col, vec3<f32>(0.299,0.587,0.114));
    alpha = clamp(lum*0.7+alpha*0.3, 0.0, 1.0);
    let out = vec4<f32>(col, alpha);
    textureStore(writeTexture, vec2<i32>(id.xy), out);
    let depth = select(0.0, clamp(1.0-d/MAX_DIST,0.0,1.0), d < MAX_DIST);
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), out);
}
