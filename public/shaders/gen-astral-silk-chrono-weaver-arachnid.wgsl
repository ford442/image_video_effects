// ═══════════════════════════════════════════════════════════════════
//  Astral-Silk Chrono-Weaver Arachnid
//  Category: generative
//  Features: raymarched, mouse-driven, audio-reactive,
//            upgraded-rgba, aces-tone-map, temporal-feedback, chromatic-aberration
//  Complexity: High
//  Chunks From: gen-protocell-division.wgsl (upgraded-rgba stack)
//  Upgraded: 2026-06-14
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dim = textureDimensions(writeTexture);
    if (global_id.x >= dim.x || global_id.y >= dim.y) { return; }

    let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    let iResolution = vec2<f32>(u.config.z, u.config.w);
    var uv = (fragCoord - 0.5 * iResolution) / iResolution.y;

    let m = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) / iResolution) * 2.0 - vec2<f32>(1.0);
    let time = u.config.x;
    let chrono = u.zoom_params.y;
    let thick = u.zoom_params.z;
    let coreInt = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var ro = vec3<f32>(0.0, 0.0, 5.5);
    var rd = normalize(vec3<f32>(uv, -1.0));

    let rotX = rot(-m.y * 1.8);
    let rotY = rot(time * 0.08 + m.x * 2.8);
    ro = vec3<f32>(ro.x, ro.y*rotX[0][0]+ro.z*rotX[1][0], ro.y*rotX[0][1]+ro.z*rotX[1][1]);
    ro = vec3<f32>(ro.x*rotY[0][0]+ro.z*rotY[1][0], ro.y, ro.x*rotY[0][1]+ro.z*rotY[1][1]);
    rd = vec3<f32>(rd.x, rd.y*rotX[0][0]+rd.z*rotX[1][0], rd.y*rotX[0][1]+rd.z*rotX[1][1]);
    rd = vec3<f32>(rd.x*rotY[0][0]+rd.z*rotY[1][0], rd.y, rd.x*rotY[0][1]+rd.z*rotY[1][1]);

    // === Animated leg & thread positions (chrono-weaving motion) ===
    let legPhase = time * chrono * 0.6 * (1.0 + bass * 0.4);
    let legSpread = 1.8 + sin(time * 0.3) * 0.2;
    let legLift = sin(legPhase) * 0.6 * (0.5 + chrono*0.5);

    var col = vec3<f32>(0.0);
    var t = 0.0;
    var hit = false;
    var pHit: vec3<f32>;

    // Raymarch main geometry (body + 8 legs)
    for (var i = 0; i < 90; i++) {
        let p = ro + rd * t;
        // Central body (radiant core + abdomen)
        let body = length(p - vec3<f32>(0.0, 0.0, 0.0)) - 0.65;
        let abdomen = length(p - vec3<f32>(0.0, -1.1, 0.0)) - 0.9;
        var d = min(body, abdomen);

        // 8 animated legs (capsules)
        let phases = array<f32, 8>(0.0, 1.2, 2.4, 3.6, 0.6, 1.8, 3.0, 4.2);
        for (var l = 0u; l < 8u; l++) {
            let ph = phases[l] + legPhase;
            let angle = f32(l) * 0.7854 + sin(ph * 0.7) * 0.25;
            let tip = vec3<f32>(
                sin(angle) * legSpread,
                -0.3 + cos(ph) * legLift * (f32(l % 2u) - 0.5),
                cos(angle) * legSpread * 0.6
            );
            let base = vec3<f32>(0.0, -0.4, 0.0);
            let legD = sdCapsule(p, base, tip, 0.08 + thick * 0.04);
            d = min(d, legD);
        }
        if (d < 0.0015) { hit = true; pHit = p; break; }
        if (t > 12.0) { break; }
        t += d;
    }

    if (hit) {
        // Silk emissive shading + chrono pulse
        let hue = u.zoom_params.x;
        let pulse = 0.6 + 0.4 * sin(time * 3.5 * chrono + length(pHit) * 4.0);
        let silkCol = hsv2rgb(vec3<f32>(hue + fbm(pHit * 1.5) * 0.15, 0.75, 1.0)) * (1.2 + pulse * 0.8) * coreInt * (1.0 + mids * 0.3);

        // Fresnel rim on body
        let n = normalize(pHit); // cheap normal
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

    // === Extra astral silk thread glow (weaving strands) ===
    let threadCount = 6u;
    for (var s = 0u; s < threadCount; s++) {
        let ang = f32(s) * 1.047 + time * 0.15 * chrono;
        let threadA = vec3<f32>(0.0, 0.2, 0.0);
        let threadB = vec3<f32>(sin(ang) * 3.5, -1.5 + cos(ang * 0.6) * 1.2, cos(ang) * 3.5);
        let td = sdCapsule(ro + rd * t * 0.6, threadA, threadB, 0.025 + thick * 0.035);
        let threadGlow = exp(-td * (28.0 - thick * 12.0)) * 0.9 * (1.0 + treble * 0.5);
        let hue = u.zoom_params.x;
        let threadCol = hsv2rgb(vec3<f32>(hue + f32(s) * 0.07, 0.85, 1.0));
        col += threadCol * threadGlow * (0.7 + 0.3 * sin(time * 4.0 * chrono + f32(s)));
    }

    let coord = vec2<i32>(global_id.xy);

    // ═══ CHUNK: temporal-feedback (dataTextureC → dataTextureA) ═══
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(col, prev.rgb * 0.92, 0.05 + bass * 0.01);

    // ═══ CHUNK: chromatic-aberration ═══
    let caStr = 0.003 * (1.0 + bass) + coreInt * 0.001;
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    col = acesToneMap(col * 1.2);

    let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(lum * 1.4 + 0.05, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    let depthVal = clamp(t / 12.0, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
