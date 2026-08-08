// ═══════════════════════════════════════════════════════════════════
//  Singularity Forge
//  Category: generative
//  Features: raymarched, black-hole, accretion-disk, audio-reactive,
//            aces-tone-mapping, chromatic-aberration, temporal-feedback,
//            depth-aware, semantic-alpha
//  Complexity: High
//  Created: 2026-05-31
//  Updated: 2026-06-01
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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Disk Density, y=Jet Intensity, z=Gravity Warp, w=Time Dilation
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                dot(hash3(i + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                dot(hash3(i + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
        mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                dot(hash3(i + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                dot(hash3(i + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var bp = p;
    var amp = 0.5;
    for(var i=0; i<4; i++) {
        f += amp * noise(bp);
        bp *= 2.0;
        amp *= 0.5;
    }
    return f;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn getRayDir(uv: vec2<f32>, time: f32, audioReactivity: f32) -> vec3<f32> {
    var rd = normalize(vec3<f32>(uv, 1.0));
    let camRotX = rotate2D(0.3);
    let camRotY = rotate2D(time * 0.1 * audioReactivity);
    let t1 = camRotX * rd.yz;
    rd.y = t1.x;
    rd.z = t1.y;
    let t2 = camRotY * rd.xz;
    rd.x = t2.x;
    rd.z = t2.y;
    return rd;
}

struct MarchResult {
    color: vec3<f32>,
    glow: f32,
    travel: f32,
    hit: bool,
};

fn marchRay(ro: vec3<f32>, rd: vec3<f32>, time: f32, dd: f32, ji: f32, gw: f32, bass: f32) -> MarchResult {
    var col = vec3<f32>(0.0);
    var t = 0.0;
    var glow = vec3<f32>(0.0);
    var hit = false;
    for(var i=0; i<100; i++) {
        var p = ro + rd * t;
        let distToOrigin = length(p);
        if (distToOrigin > 0.01) {
            p += normalize(p) * (gw * 0.5 / distToOrigin);
        }
        let dBlackHole = length(p) - 0.8;
        var pDisk = p;
        pDisk.y *= 5.0;
        var dDisk = sdTorus(pDisk, vec2<f32>(2.0, 0.4 * dd));
        let n = fbm(pDisk * 2.0 + vec3<f32>(time * 2.0 * (1.0 + bass * 0.5), bass * 5.0, time * 2.0));
        dDisk += n * 0.5;
        var pJet = p;
        let dJet = length(pJet.xz) - 0.1 / (abs(pJet.y) + 0.1);
        let d = min(dBlackHole, dDisk);
        if (d < 0.01) {
            hit = true;
            if (dBlackHole < dDisk) {
                col = vec3<f32>(0.0);
            } else {
                let diskDist = length(pDisk.xz);
                let heat = clamp(1.0 - (diskDist - 1.0) * 0.3, 0.0, 1.0);
                let diskAngle = atan2(pDisk.z, pDisk.x);
                let shear = 0.62 + 0.38 * sin(diskAngle * 16.0 - time * (7.0 + dd * 2.0));
                col = mix(vec3<f32>(0.8, 0.2, 0.0), vec3<f32>(0.8, 0.9, 1.0), heat) * heat * (1.4 + shear);
            }
            break;
        }
        let knotPhase = abs(fract(abs(pJet.y) * 0.18 - time * (0.9 + bass * 1.8)) - 0.5);
        let jetKnot = exp(-knotPhase * knotPhase * 180.0);
        glow += vec3<f32>(1.0, 0.9, 1.0) * 0.02 / (abs(dBlackHole) + 0.05);
        glow += vec3<f32>(0.45, 0.12, 1.2) * (0.008 * ji * (0.7 + jetKnot * 2.4)) / (abs(dJet) + 0.05);
        glow += vec3<f32>(1.0, 0.4, 0.1) * 0.005 / (abs(dDisk) + 0.1);
        t += max(abs(d) * 0.5, 0.003);
        if (distToOrigin < 0.8) {
            col = vec3<f32>(0.0);
            break;
        }
        if(t > 20.0) { break; }
    }
    return MarchResult(col + glow, length(glow), t, hit);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    let uv = (fragCoord * 2.0 - res) / res.y;

    // Parameters
    let diskDensity = u.zoom_params.x;
    let jetIntensity = u.zoom_params.y;
    let gravityWarp = u.zoom_params.z;
    let timeDilation = u.zoom_params.w;

    // ═══ AUDIO REACTIVITY (plasmaBuffer) ═══
    let time = u.config.x * timeDilation * 0.5;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioReactivity = 1.0 + bass * 0.5;

    let effectiveGravity = gravityWarp * (0.85 + bass * 0.25);

    // Camera origin (shared across channels)
    var ro = vec3<f32>(0.0, 1.5, -4.0);
    let camRotX = rotate2D(0.3);
    let camRotY = rotate2D(time * 0.1 * audioReactivity);
    let tr = camRotX * ro.yz;
    ro.y = tr.x;
    ro.z = tr.y;
    let tr2 = camRotY * ro.xz;
    ro.x = tr2.x;
    ro.z = tr2.y;

    // Screen-space mouse gravity bends the ray toward the visible cursor.
    let mouseUv = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(res.x / res.y, 1.0);
    let mouseDelta = mouseUv - uv;
    let mousePull = exp(-dot(mouseDelta, mouseDelta) * 2.8) * (0.10 + u.zoom_config.w * 0.16);
    let lensedUv = uv + mouseDelta * mousePull;
    let rd = getRayDir(lensedUv, time, audioReactivity);

    // One primary march replaces the former three full raymarches. Spectral
    // separation comes from orbital velocity and material-space Doppler shift.
    let result = marchRay(ro, rd, time, diskDensity, jetIntensity, effectiveGravity, bass);
    let orbitalPhase = atan2(lensedUv.y, lensedUv.x) - time * (4.0 + diskDensity);
    let doppler = sin(orbitalPhase) * (0.035 + treble * 0.045);
    var fresh = max(result.color * vec3<f32>(1.0 + doppler, 1.0, 1.0 - doppler), vec3<f32>(0.0));

    // Angularly advected, bounded lensing history leaves fast curved trails.
    let swirlVelocity = vec2<f32>(-uv.y, uv.x) * (3.0 + timeDilation * 2.0 + bass * 2.5);
    let maxCoord = vec2<i32>(max(i32(res.x) - 1, 0), max(i32(res.y) - 1, 0));
    let historyCoord = clamp(vec2<i32>(id.xy) - vec2<i32>(swirlVelocity), vec2<i32>(0), maxCoord);
    let history = textureLoad(dataTextureC, historyCoord, 0).rgb;
    let hdrColor = clamp(fresh + history * (0.28 + jetIntensity * 0.08), vec3<f32>(0.0), vec3<f32>(6.0));
    let alpha = clamp(result.glow * (1.0 + bass) * 1.2 + select(0.0, 0.35, result.hit), 0.02, 0.98);
    let depth = select(0.0, clamp(1.0 - result.travel / 20.0, 0.0, 1.0), result.hit);
    let coords = vec2<i32>(id.xy);
    textureStore(dataTextureA, coords, vec4<f32>(hdrColor, alpha));
    textureStore(writeTexture, coords, vec4<f32>(acesToneMap(hdrColor * 1.45), alpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
