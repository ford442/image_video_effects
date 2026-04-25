// ═══════════════════════════════════════════════════════════════════
//  Astro Kinetic Chrono Orrery - Physically Accurate Orbital System
//  Category: generative
//  Features: mouse-driven
//  Complexity: High
//  Physics: Keplerian orbits, blackbody radiation, accretion disk
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
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Complexity, y=Speed, z=Glow Intensity, w=Audio Reactivity
    ripples: array<vec4<f32>, 50>,
};
const PI = 3.14159265359;
const MAX_STEPS = 100;
const SURF_DIST = 0.001;
const MAX_DIST = 100.0;
fn hash12(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}
fn keplerOrbit(theta: f32, a: f32, e: f32) -> f32 {
    return a * (1.0 - e * e) / (1.0 + e * cos(theta));
}
fn meanAnomalyToEccentric(M: f32, e: f32) -> f32 {
    var E = M;
    for (var i: i32 = 0; i < 6; i++) {
        let sinE = sin(E);
        let cosE = cos(E);
        let f = E - e * sinE - M;
        let fp = 1.0 - e * cosE;
        E = E - f / fp;
    }
    return E;
}
fn blackbodyColor(temp: f32) -> vec3<f32> {
    let t = temp / 1000.0;
    var c = vec3<f32>(1.0);
    if (t >= 6.6) {
        c.x = clamp(1.29 * pow(t - 6.6, -0.133), 0.0, 1.0);
        c.y = c.x;
    } else {
        c.x = 1.0;
        c.y = clamp(0.39 * log(max(t - 2.0, 0.001)) + 0.5, 0.0, 1.0);
        c.z = clamp(0.54 * log(max(t - 4.0, 0.001)) + 0.7, 0.0, 1.0);
        if (t <= 4.0) { c.z = 0.0; }
        if (t <= 2.0) { c.y = 0.0; c.x = clamp(t / 2.0, 0.0, 1.0); }
    }
    return c;
}
fn accretionDiskDensity(r: f32, theta: f32, t: f32) -> f32 {
    let inner = 0.6;
    let outer = 3.0;
    if (r < inner || r > outer) { return 0.0; }
    let radial = exp(-(r - 1.5) * (r - 1.5) * 2.0);
    let spiral = sin(theta * 3.0 + r * 4.0 - t * 0.5) * 0.5 + 0.5;
    let turb = hash12(vec2<f32>(r * 7.0 + theta * 2.0, t * 0.1)) * 0.3;
    return radial * (0.5 + spiral * 0.5 + turb);
}
fn spiralArmOffset(r: f32, armIndex: f32, numArms: f32, t: f32) -> vec2<f32> {
    let armAngle = (armIndex / numArms) * 2.0 * PI;
    let twist = log(r + 1.0) * 2.0 - t * 0.1;
    let angle = armAngle + twist;
    return vec2<f32>(cos(angle) * r * 0.15, sin(angle) * r * 0.15);
}
fn particlePosition(id: f32, t: f32, innerR: f32, outerR: f32) -> vec3<f32> {
    let a = mix(innerR, outerR, fract(id * 0.618034));
    let e = 0.05 + fract(id * 0.3718) * 0.25;
    let incline = fract(id * 0.2171) * 0.3;
    let M = fract(id * 0.9137) * 2.0 * PI + t * (0.1 + fract(id * 0.517) * 0.2);
    let E = meanAnomalyToEccentric(M, e);
    let trueAnomaly = 2.0 * atan(sqrt((1.0 + e) / (1.0 - e)) * tan(E * 0.5));
    let r = keplerOrbit(trueAnomaly, a, e);
    let basePos = vec2<f32>(r * cos(trueAnomaly), r * sin(trueAnomaly));
    let armOffset = spiralArmOffset(a, fract(id * 0.97) * 3.0, 3.0, t);
    let pos2d = basePos + armOffset;
    let moonR = 0.08 + fract(id * 0.333) * 0.12;
    let moonAngle = t * (1.0 + fract(id * 0.777) * 2.0) + id * 10.0;
    let moonPos = vec2<f32>(cos(moonAngle) * moonR, sin(moonAngle) * moonR);
    let z = sin(incline) * r + (hash12(vec2<f32>(id, 0.0)) - 0.5) * 0.1;
    return vec3<f32>(pos2d.x + moonPos.x, pos2d.y + moonPos.y, z);
}
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}
fn map(p: vec3<f32>, time: f32) -> vec4<f32> {
    var d = MAX_DIST;
    var temp = 1000.0;
    var metal = 0.0;
    var density = 0.0;
    var q = p;
    let rot_yz = rot2D(u.zoom_config.z * PI) * vec2<f32>(q.y, q.z);
    q.y = rot_yz.x; q.z = rot_yz.y;
    let rot_xz = rot2D(u.zoom_config.y * PI) * vec2<f32>(q.x, q.z);
    q.x = rot_xz.x; q.z = rot_xz.y;
    let centralDist = sdSphere(q, 0.25);
    if (centralDist < d) {
        d = centralDist; temp = 8000.0; metal = 0.9; density = 1.0;
    }
    let diskR = length(vec2<f32>(q.x, q.z));
    let diskTheta = atan(q.z, q.x);
    let diskDensity = accretionDiskDensity(diskR, diskTheta, time);
    let diskVertical = abs(q.y) - 0.05 - diskDensity * 0.08;
    let diskOuter = diskR - 3.0;
    let diskInner = 0.6 - diskR;
    let diskSdf = max(max(diskVertical, diskOuter), diskInner);
    if (diskSdf < d) {
        d = diskSdf; temp = 4000.0 + diskDensity * 4000.0;
        metal = 0.5 + diskDensity * 0.4; density = diskDensity;
    }
    for (var i: i32 = 1; i <= 6; i++) {
        let fi = f32(i);
        let bodyPos = particlePosition(fi, time, 0.8, 3.5);
        let bodyRadius = 0.04 + fract(fi * 0.618) * 0.03;
        let bodyDist = sdSphere(q - bodyPos, bodyRadius);
        if (bodyDist < d) {
            d = bodyDist; temp = 2000.0 + fract(fi * 0.419) * 4000.0;
            metal = fract(fi * 0.731); density = 1.0;
        }
    }
    return vec4<f32>(d, temp, metal, density);
}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let uv = (vec2<f32>(id.xy) * 2.0 - dims) / dims.y;
    let screen_uv = (vec2<f32>(id.xy) + 0.5) / dims;
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));
    let time = u.config.x * u.zoom_params.y;
    var t = 0.0;
    for (var i: i32 = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * t;
        let res = map(p, time);
        if (res.x < SURF_DIST || t > MAX_DIST) { break; }
        t += res.x;
    }
    var col = vec3<f32>(0.0);
    var alpha = 0.0;
    if (t < MAX_DIST) {
        let p = ro + rd * t;
        let res = map(p, time);
        let bb = blackbodyColor(res.y);
        col.r = clamp(res.y / 10000.0, 0.0, 1.0);
        col.g = res.z;
        col.b = dot(bb, vec3<f32>(0.299, 0.587, 0.114));
        alpha = clamp(res.w, 0.0, 1.0);
    }
    if (alpha < 0.01) {
        let starHash = hash12(uv * 100.0 + vec2<f32>(time * 0.01, 0.0));
        if (starHash > 0.995) {
            let starBright = (starHash - 0.995) * 200.0;
            col = vec3<f32>(0.8, 0.85, 1.0) * starBright;
            alpha = clamp(starBright, 0.0, 1.0);
        }
    }
    textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, screen_uv, 0.0).r;
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
