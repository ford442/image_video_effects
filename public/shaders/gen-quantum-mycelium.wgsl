// ═══════════════════════════════════════════════════════════════════
//  Quantum Mycelium
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13
//  Ideas: septate rings along cylinder axis; neighbor-cell fusion bridges
//  A packing: ACES display RGBA (C unused)
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
    config: vec4<f32>,       // x=Time, y=rippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=time, yz=mouse_uv (0-1), w=mouse_down
    zoom_params: vec4<f32>,  // x=Network Density, y=Growth Chaos, z=Pulse Speed, w=Edge Softness
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var bp = p;
    var amp = 0.5;
    for (var i = 0; i < 4; i++) {
        let h = hash33(bp);
        f += amp * h.x;
        bp *= 2.0;
        amp *= 0.5;
    }
    return f;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.001), 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdCylinder(p: vec3<f32>, c: vec3<f32>) -> f32 {
    return length(p.xz - c.xy) - c.z;
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

var<private> g_time: f32;
var<private> g_mouse: vec2<f32>;
var<private> g_audio: f32;

// returns (sdf, septum, threadCenterDist)
fn map(p: vec3<f32>) -> vec3<f32> {
    var bp = p;
    let density = max(u.zoom_params.x, 0.5);
    let chaos = u.zoom_params.y;

    let cell = vec3<f32>(5.0 / density);
    var q = bp;

    let noiseOffset = vec3<f32>(
        fbm(q * 0.5 + vec3<f32>(g_time * 0.2)),
        fbm(q * 0.4 - vec3<f32>(g_time * 0.1)),
        fbm(q * 0.6)
    ) * chaos;
    q += noiseOffset;

    q = q - cell * round(q / cell);

    q = abs(q) - vec3<f32>(1.0 / density);
    let temp_q_xy = rot(0.5) * q.xy;
    q.x = temp_q_xy.x;
    q.y = temp_q_xy.y;

    q = abs(q) - vec3<f32>(0.5 / density);
    let temp_q_xz = rot(0.3) * q.xz;
    q.x = temp_q_xz.x;
    q.z = temp_q_xz.y;

    let radius = 0.15 / density;
    var d = sdCylinder(q, vec3<f32>(0.0, 0.0, radius));
    let threadCenterDist = length(q.xz);

    // Idea 1 — septate rings along the cylinder Y axis (Edge Softness = count/softness)
    let edgeSoft = clamp(u.zoom_params.w, 0.0, 1.0);
    let septFreq = mix(3.0, 10.0, edgeSoft);
    let ring = abs(fract(q.y * septFreq) - 0.5);
    let septum = 1.0 - smoothstep(0.0, mix(0.10, 0.025, edgeSoft), ring);
    d = d - septum * (0.028 / density);

    // Idea 2 — neighbor fusion: capsule to the nearest domain-repeat face
    let qAbs = abs(q);
    let useX = (qAbs.x >= qAbs.y) && (qAbs.x >= qAbs.z);
    let useY = (qAbs.y >= qAbs.z) && !useX;
    let toFace = select(
        select(vec3<f32>(0.0, 0.0, sign(q.z) * cell.z * 0.5),
               vec3<f32>(0.0, sign(q.y) * cell.y * 0.5, 0.0),
               useY),
        vec3<f32>(sign(q.x) * cell.x * 0.5, 0.0, 0.0),
        useX);
    let dBridge = sdCapsule(q, vec3<f32>(0.0), toFace, radius * 0.55);
    d = smin(d, dBridge, 0.22);

    let mouse3D = vec3<f32>(g_mouse.x * 10.0, -g_mouse.y * 10.0, 5.0);
    let mouseDist = length(bp - mouse3D);
    let repulsionSphere = mouseDist - 2.5;
    d = smin(d, repulsionSphere + 2.0, 1.0);
    d = max(d, -repulsionSphere);

    return vec3<f32>(d, septum, threadCenterDist);
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

    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var uv = (fragCoord * 2.0 - dims) / dims.y;

    g_time = u.config.x;
    g_audio = bass;
    // zoom_config.yz is already 0–1 canvas UV
    g_mouse = vec2<f32>(u.zoom_config.y * 2.0 - 1.0, u.zoom_config.z * 2.0 - 1.0);

    var ro = vec3<f32>(0.0, 0.0, -g_time * 2.0);
    ro = vec3<f32>(ro.x + g_mouse.x * 2.0, ro.y - g_mouse.y * 2.0, ro.z);

    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var d = 0.0;
    let maxT = 30.0;
    var accumDens = 0.0;

    for (var i = 0; i < 90; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;

        let sporeThick = u.zoom_params.w * 0.5;
        if (d > 0.1) {
            accumDens += sporeThick * 0.02 * (1.0 / (1.0 + d * d));
        }

        if (d < 0.005 || t > maxT) { break; }
        t += d * 0.7;
    }

    var col = vec3<f32>(0.02, 0.01, 0.05);
    var alpha = 0.0;
    var septumLit = 0.0;
    let hit = t < maxT;

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let res = map(p);
        let distToThread = res.z;
        let edgeSoftness = max(u.zoom_params.w * 0.5, 0.001);
        alpha = 1.0 - smoothstep(0.0, edgeSoftness, distToThread);
        septumLit = res.y;

        let subsurfaceP = p - n * 0.15;
        let subsurfaceDist = map(subsurfaceP).x;
        let sss = smoothstep(0.0, 0.2, -subsurfaceDist) * 0.8;
        let fleshyCol = vec3<f32>(0.8, 0.3, 0.4);

        let pulseSpeed = u.zoom_params.z;
        let pulseWave = sin(p.z * 5.0 - g_time * pulseSpeed * 3.0 + g_audio * 5.0 + treble * 10.0);
        let pulse = smoothstep(0.8, 1.0, pulseWave);
        let glowCol = vec3<f32>(0.1, 0.9, 0.8) * pulse * 3.0;

        let dif = max(dot(n, vec3<f32>(0.5, 0.8, 0.5)), 0.0);
        let fre = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        col = fleshyCol * dif * 0.5;
        col += fleshyCol * sss;
        col += glowCol;
        col += fre * vec3<f32>(0.5, 0.7, 1.0) * 0.5;
        // Septum emission — pearly rings, not a pulse clone
        col += vec3<f32>(0.95, 0.85, 0.55) * septumLit * (0.55 + mids * 0.35);

        let fog = 1.0 - exp(-t * 0.15);
        col = mix(col, vec3<f32>(0.02, 0.01, 0.05), fog);
    }

    let sporeCol = vec3<f32>(0.4, 0.8, 0.5);
    col += sporeCol * min(accumDens, 1.0);

    alpha = clamp(alpha + min(accumDens, 1.0) * 0.25 + septumLit * 0.2, 0.04, 1.0);

    let display = acesToneMap(col);
    let screenUV = fragCoord / dims;
    let readDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, screenUV, 0.0).r;
    let depth = select(readDepth, clamp(1.0 - t / maxT, 0.0, 1.0), hit);
    let coord = vec2<i32>(id.xy);
    let outColor = vec4<f32>(display, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
