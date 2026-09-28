// ═══════════════════════════════════════════════════════════════════
//  Astral-Silk Chrono-Weaver Arachnid
//  Category: generative
//  Features: raymarched, mouse-driven, audio-reactive, upgraded-rgba, temporal-feedback
//  Complexity: High
//  Chunks From: gen-protocell-division.wgsl (upgraded-rgba stack)
//  Upgraded: 2026-09-27
//  Ideas: leg-anchored radial spokes (exact ray-segment silk); orb-web capture spiral tugged by the gait; hub shockwave fronts through the silk
//  A packing: HDR linear RGB (pre-ACES) + semantic alpha
//  By: Claude Code Batch 3B
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
    config: vec4<f32>,       // x=Time, y=Audio/Click, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic
    zoom_params: vec4<f32>,  // x=Hue, y=ChronoSpeed+Anim, z=ThreadThickness, w=CoreIntensity
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + vec3<f32>(33.33));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn snoise(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f*f*(vec3<f32>(3.0)-2.0*f);
    let n = mix(mix(mix(dot(hash3(i), f), dot(hash3(i+vec3<f32>(1.0,0.0,0.0)), f-vec3<f32>(1.0,0.0,0.0)), u.x),
                     mix(dot(hash3(i+vec3<f32>(0.0,1.0,0.0)), f-vec3<f32>(0.0,1.0,0.0)), dot(hash3(i+vec3<f32>(1.0,1.0,0.0)), f-vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
                mix(mix(dot(hash3(i+vec3<f32>(0.0,0.0,1.0)), f-vec3<f32>(0.0,0.0,1.0)), dot(hash3(i+vec3<f32>(1.0,0.0,1.0)), f-vec3<f32>(1.0,0.0,1.0)), u.x),
                     mix(dot(hash3(i+vec3<f32>(0.0,1.0,1.0)), f-vec3<f32>(0.0,1.0,1.0)), dot(hash3(i+vec3<f32>(1.0,1.0,1.0)), f-vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
    return n;
}

fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0; var a = 0.5; var p2 = p;
    for (var i = 0; i < 4; i++) {
        v += a * snoise(p2); p2 = p2*2.0 + vec3<f32>(100.0); a *= 0.5;
    }
    return v;
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a; let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
    return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Leg tips / anchors are hoisted out of the march (they do not depend on p).
var<private> gTips: array<vec3<f32>, 8>;
var<private> gAnchors: array<vec3<f32>, 8>;
var<private> gLegR: f32;

// Spider SDF — body + abdomen + 8 leg capsules (HEAD geometry, verbatim).
fn mapSpider(p: vec3<f32>) -> f32 {
    let body = length(p - vec3<f32>(0.0, 0.0, 0.0)) - 0.65;
    let abdomen = length(p - vec3<f32>(0.0, -1.1, 0.0)) - 0.9;
    var d = min(body, abdomen);
    let base = vec3<f32>(0.0, -0.4, 0.0);
    for (var l = 0u; l < 8u; l++) {
        d = min(d, sdCapsule(p, base, gTips[l], gLegR));
    }
    return d;
}

// FIX: real SDF normal (HEAD used normalize(pHit), wrong on every leg).
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.002, 0.0);
    return normalize(vec3<f32>(
        mapSpider(p + e.xyy) - mapSpider(p - e.xyy),
        mapSpider(p + e.yxy) - mapSpider(p - e.yxy),
        mapSpider(p + e.yyx) - mapSpider(p - e.yyx)));
}

// Exact closest approach between the view ray [0, tMax] and silk segment a→b.
// Returns (glow, hub radius of the closest silk point). Replaces HEAD's single
// sample at ro + rd*t*0.6, which made the threads jump at the silhouette.
fn silkSeg(ro: vec3<f32>, rd: vec3<f32>, tMax: f32, a: vec3<f32>, b: vec3<f32>,
           radius: f32, k: f32) -> vec2<f32> {
    let ba = b - a;
    let oa = ro - a;
    let bb = max(dot(ba, ba), 1e-6);
    let d1 = dot(rd, ba);
    let rdoa = dot(rd, oa);
    let baoa = dot(ba, oa);
    var h = clamp((baoa - d1 * rdoa) / max(bb - d1 * d1, 1e-6), 0.0, 1.0);
    let s = clamp(d1 * h - rdoa, 0.0, tMax);
    h = clamp(dot(ba, oa + rd * s) / bb, 0.0, 1.0);
    let dist = length(oa + rd * s - ba * h) - radius;
    let q = a + ba * h;
    return vec2<f32>(exp(-dist * k), length(q.xz));
}

// Idea 3: shockwave fronts — two travelling rings leave the hub on a clock and
// fade as they run out to the anchor ring (radius measured in the web plane).
fn shockFront(r: f32, clock: f32) -> f32 {
    var e = 0.0;
    for (var k = 0; k < 2; k++) {
        let ph = fract(clock + f32(k) * 0.5);
        let x = (r - ph * 4.4) / 0.22;
        e += exp(-x * x) * (1.0 - ph);
    }
    return e;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dim = textureDimensions(writeTexture);
    if (global_id.x >= dim.x || global_id.y >= dim.y) { return; }

    let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    let iResolution = vec2<f32>(u.config.z, u.config.w);
    var uv = (fragCoord - 0.5 * iResolution) / iResolution.y;

    // FIX: zoom_config.yz is already 0..1 — HEAD divided it by resolution, pinning
    // m at (-1,-1) and the camera near overhead. Mouse (0.5,0.5) = 3/4 view.
    let m = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - vec2<f32>(1.0);
    let time = u.config.x;
    let chrono = u.zoom_params.y;
    let thick = u.zoom_params.z;
    let coreInt = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var ro = vec3<f32>(0.0, 0.0, 5.5);
    var rd = normalize(vec3<f32>(uv, -1.0));

    let rotX = rot(0.45 - m.y * 0.9);
    let rotY = rot(time * 0.08 + m.x * 2.8);
    ro = vec3<f32>(ro.x, ro.y*rotX[0][0]+ro.z*rotX[1][0], ro.y*rotX[0][1]+ro.z*rotX[1][1]);
    ro = vec3<f32>(ro.x*rotY[0][0]+ro.z*rotY[1][0], ro.y, ro.x*rotY[0][1]+ro.z*rotY[1][1]);
    rd = vec3<f32>(rd.x, rd.y*rotX[0][0]+rd.z*rotX[1][0], rd.y*rotX[0][1]+rd.z*rotX[1][1]);
    rd = vec3<f32>(rd.x*rotY[0][0]+rd.z*rotY[1][0], rd.y, rd.x*rotY[0][1]+rd.z*rotY[1][1]);

    // === Animated leg & thread positions (chrono-weaving motion) ===
    let legPhase = time * chrono * 0.6 * (1.0 + bass * 0.4);
    let legSpread = 1.8 + sin(time * 0.3) * 0.2;
    let legLift = sin(legPhase) * 0.6 * (0.5 + chrono*0.5);

    let phases = array<f32, 8>(0.0, 1.2, 2.4, 3.6, 0.6, 1.8, 3.0, 4.2);
    for (var l = 0u; l < 8u; l++) {
        let ph = phases[l] + legPhase;
        let angle = f32(l) * 0.7854 + sin(ph * 0.7) * 0.25;
        gTips[l] = vec3<f32>(
            sin(angle) * legSpread,
            -0.3 + cos(ph) * legLift * (f32(l % 2u) - 0.5),
            cos(angle) * legSpread * 0.6
        );
        // Web anchor ring: fixed at the leg's rest angle, so the gait wobble
        // stretches the spoke against its anchor.
        let a0 = f32(l) * 0.7854;
        gAnchors[l] = vec3<f32>(sin(a0) * 3.6, -0.7, cos(a0) * 3.6);
    }
    gLegR = 0.08 + thick * 0.04;

    var col = vec3<f32>(0.0);
    var t = 0.0;
    var hit = false;
    var pHit = vec3<f32>(0.0);

    // Raymarch main geometry (body + 8 legs)
    for (var i = 0; i < 90; i++) {
        let p = ro + rd * t;
        let d = mapSpider(p);
        if (d < 0.0015) { hit = true; pHit = p; break; }
        if (t > 12.0) { break; }
        t += d;
    }

    let hue = u.zoom_params.x;
    let shockClock = time * 0.22 * (0.6 + 0.4 * chrono);
    let shockAmp = coreInt * 1.6 * (1.0 + bass * 1.5);

    if (hit) {
        // Silk emissive shading + chrono pulse
        let pulse = 0.6 + 0.4 * sin(time * 3.5 * chrono + length(pHit) * 4.0);
        var silkCol = hsv2rgb(vec3<f32>(hue + fbm(pHit * 1.5) * 0.15, 0.75, 1.0)) * (1.2 + pulse * 0.8) * coreInt * (1.0 + mids * 0.3);
        // Idea 3: the shockwave is born in the spider — fronts run out along the legs first.
        silkCol *= 1.0 + 0.5 * shockFront(length(pHit.xz), shockClock) * shockAmp;

        // Fresnel rim on body
        let n = calcNormal(pHit);
        let fres = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
        col = silkCol * (1.0 + fres * 1.5);
    } else {
        // Cosmic dust + faint nebula background
        let dust = fbm(rd * 6.0 + vec3<f32>(time * 0.03));
        col = vec3<f32>(dust * 0.035 + 0.008);
        // Add distant star twinkles
        let star = step(0.996, hash3(floor(rd * 180.0)).x);
        col += star * vec3<f32>(0.6, 0.7, 1.0) * 0.8;
    }

    // Silk is occluded by the spider: the ray only runs to the hit distance.
    let tMax = select(1.0e4, t, hit);
    let silkR = 0.025 + thick * 0.035;
    // FIX: HEAD used (28 - thick*12), negative for thick > 2.33 -> e^(+) whiteout.
    let silkK = max(28.0 - thick * 12.0, 8.0);

    // === Extra astral silk thread glow (weaving strands) ===
    let threadCount = 6u;
    for (var s = 0u; s < threadCount; s++) {
        let ang = f32(s) * 1.047 + time * 0.15 * chrono;
        let threadA = vec3<f32>(0.0, 0.2, 0.0);
        let threadB = vec3<f32>(sin(ang) * 3.5, -1.5 + cos(ang * 0.6) * 1.2, cos(ang) * 3.5);
        let g = silkSeg(ro, rd, tMax, threadA, threadB, silkR, silkK);
        let threadGlow = g.x * 0.9 * (1.0 + treble * 0.5);
        let threadCol = hsv2rgb(vec3<f32>(hue + f32(s) * 0.07, 0.85, 1.0));
        col += threadCol * threadGlow * (0.7 + 0.3 * sin(time * 4.0 * chrono + f32(s)))
             * (1.0 + shockFront(g.y, shockClock) * shockAmp);
    }

    // Idea 1: leg-anchored radial spokes — each leg tip holds a spoke out to the
    // anchor ring, so the gait visibly tugs the web the spider is weaving.
    for (var l = 0u; l < 8u; l++) {
        let g = silkSeg(ro, rd, tMax, gTips[l], gAnchors[l], silkR * 0.8, silkK);
        let spokeCol = hsv2rgb(vec3<f32>(hue + 0.03 + f32(l) * 0.02, 0.8, 1.0));
        col += spokeCol * g.x * 0.75 * (1.0 + shockFront(g.y, shockClock) * shockAmp);
    }

    // Idea 2: orb-web capture spiral — 6 turns of chords between neighbouring
    // spokes, spacing tightening toward the hub (pow 1.4). Chord ends ride the
    // spokes, so the inner turns jitter with the leg gait and the outer stay taut.
    let spiralCol = hsv2rgb(vec3<f32>(hue - 0.05, 0.6, 1.0));
    for (var i = 0u; i < 48u; i++) {
        let s0 = f32(i) / 48.0;
        let s1 = f32(i + 1u) / 48.0;
        let j0 = i % 8u;
        let j1 = (i + 1u) % 8u;
        let u0 = 0.14 + 0.8 * pow(s0, 1.4);
        let u1 = 0.14 + 0.8 * pow(s1, 1.4);
        let a = mix(gTips[j0], gAnchors[j0], u0);
        let b = mix(gTips[j1], gAnchors[j1], u1);
        let g = silkSeg(ro, rd, tMax, a, b, silkR * 0.55, silkK * 1.3);
        col += spiralCol * g.x * 0.45 * (1.0 + shockFront(g.y, shockClock) * shockAmp);
    }

    let coord = vec2<i32>(global_id.xy);

    // ═══ CHUNK: temporal-feedback (dataTextureC → dataTextureA) ═══
    // FIX: A now stores HDR (pre-ACES) so C re-enters in the same space; HEAD
    // stored ACES colour and tone-mapped it a second time.
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(col, clamp(prev.rgb, vec3<f32>(0.0), vec3<f32>(64.0)) * 0.92, 0.05 + bass * 0.01);
    let hdr = col;

    // Warm tint shift (HEAD labelled this chromatic-aberration; it is a tint).
    let caStr = 0.003 * (1.0 + bass) + coreInt * 0.001;
    col = max(vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5), vec3<f32>(0.0));

    col = acesToneMap(col * 1.2);

    let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    // Semantic alpha: spider opaque; silk/void coverage by luminance.
    let alpha = select(clamp(lum * 1.4 + 0.05, 0.0, 1.0), 1.0, hit);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    // FIX: near = 1, miss = 0 (HEAD wrote t/12, inverted).
    let depthVal = select(0.0, clamp(1.0 - t / 12.0, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdr, alpha));
}
