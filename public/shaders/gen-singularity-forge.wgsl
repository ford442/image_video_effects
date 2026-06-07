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
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
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

fn marchRay(ro: vec3<f32>, rd: vec3<f32>, time: f32, dd: f32, ji: f32, gw: f32, bass: f32) -> vec4<f32> {
    var col = vec3<f32>(0.0);
    var t = 0.0;
    var glow = vec3<f32>(0.0);
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
            if (d == dBlackHole) {
                col = vec3<f32>(0.0);
            } else {
                let diskDist = length(pDisk.xz);
                let heat = clamp(1.0 - (diskDist - 1.0) * 0.3, 0.0, 1.0);
                col = mix(vec3<f32>(0.8, 0.2, 0.0), vec3<f32>(0.8, 0.9, 1.0), heat) * heat * 2.0;
            }
            break;
        }
        glow += vec3<f32>(1.0, 0.9, 1.0) * 0.02 / (abs(dBlackHole) + 0.05);
        glow += vec3<f32>(0.6, 0.1, 1.0) * (0.01 * ji * (1.0 + sin(bass * 3.0))) / (abs(dJet) + 0.05);
        glow += vec3<f32>(1.0, 0.4, 0.1) * 0.005 / (abs(dDisk) + 0.1);
        t += d * 0.5;
        if (distToOrigin < 0.8) {
            col = vec3<f32>(0.0);
            break;
        }
        if(t > 20.0) { break; }
    }
    return vec4<f32>(col + glow, length(glow));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
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

    // ═══ DEPTH-BASED GRAVITATIONAL LENSING ═══
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, fragCoord / res, 0.0).r;
    let depthFactor = 0.5 + depth * 0.5;
    let effectiveGravity = gravityWarp * depthFactor;

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

    // Mouse Interaction - Additional Gravity Well
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = u.zoom_config.z * 2.0 - 1.0;
    let mousePos = vec3<f32>(mouseX * 5.0, mouseY * 5.0, 0.0);
    let mouseDist = distance(ro, mousePos);

    // ═══ CHROMATIC ABERRATION (3 offset rays) ═══
    let caStrength = 0.002 * (1.0 + bass);
    var rdR = getRayDir(uv + vec2<f32>(caStrength, 0.0), time, audioReactivity);
    var rdG = getRayDir(uv, time, audioReactivity);
    var rdB = getRayDir(uv - vec2<f32>(caStrength, 0.0), time, audioReactivity);

    if (mouseDist > 0.1) {
        let mg = (mousePos - ro) * (0.5 / pow(mouseDist, 2.0));
        rdR = normalize(rdR + mg);
        rdG = normalize(rdG + mg);
        rdB = normalize(rdB + mg);
    }

    // Raymarch each channel
    let resR = marchRay(ro, rdR, time, diskDensity, jetIntensity, effectiveGravity, bass);
    let resG = marchRay(ro, rdG, time, diskDensity, jetIntensity, effectiveGravity, bass);
    let resB = marchRay(ro, rdB, time, diskDensity, jetIntensity, effectiveGravity, bass);

    var col = vec3<f32>(resR.r, resG.g, resB.b);
    let glowAmt = (resR.a + resG.a + resB.a) * 0.333;

    // ═══ TEMPORAL JET PERSISTENCE ═══
    let prevFrame = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);
    col = max(col, prevFrame.rgb * 0.88);

    // ═══ ACES TONE MAPPING ═══
    col = acesToneMap(col * 1.5);

    // ═══ SEMANTIC ALPHA ═══
    let alpha = clamp(glowAmt * depthFactor * (1.0 + bass) * 1.5, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depthFactor * 0.3 + glowAmt * 0.15, 0.0, 0.0, 0.0));
}
