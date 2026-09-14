// ═══════════════════════════════════════════════════════════════════
//  Prismatic Cyber-Aurora Astral-Dragonfly
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: chitin wing-membrane thin-film interference (2*n*d*cos theta at 650/532/450 nm); longitudinal costa/radius/media vein spars with nodus and dark pterostigma cell
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
    zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv, .w = mouse_down
    zoom_params: vec4<f32>,  // .x = Wingspan, .y = Plasma Intensity, .z = Vein Density, .w = Flap Rate
    ripples: array<vec4<f32>, 50>, // .xy = click uv, .z = start time
};
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

const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + 7.13));
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
    return p + 0.3 * q;
}

// Smooth Voronoi/Worley layer returning F1 distance and cell id
fn voronoi(p: vec2<f32>) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);
    var md = 8.0;
    var cell = 0.0;
    for (var j = -1; j <= 1; j = j + 1) {
        for (var i = -1; i <= 1; i = i + 1) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash22(n + g);
            let r = g + o - f;
            let d = dot(r, r);
            let closer = d < md;
            md = select(md, d, closer);
            cell = select(cell, hash21(n + g), closer);
        }
    }
    return vec2<f32>(sqrt(md), cell);
}

// Curl noise from the gradient of FBM
fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
    let e = 0.01;
    let n0 = fbm(p + vec2<f32>(e, 0.0) + t, 4);
    let n1 = fbm(p - vec2<f32>(e, 0.0) + t, 4);
    let n2 = fbm(p + vec2<f32>(0.0, e) + t, 4);
    let n3 = fbm(p - vec2<f32>(0.0, e) + t, 4);
    return vec2<f32>(n3 - n2, n0 - n1) / (2.0 * e);
}

// Layered Worley/Voronoi sparkle field
fn worleyLayers(p: vec2<f32>, t: f32) -> f32 {
    var w = 0.0;
    var a = 0.5;
    var f = 1.0;
    var rotAcc = rot(t * 0.1);
    for (var i = 0; i < 4; i = i + 1) {
        let v = voronoi(rotAcc * p * f + vec2<f32>(t * 0.05 * f32(i + 1)));
        w += a * (1.0 - smoothstep(0.0, 0.25, v.x));
        f *= 2.0;
        a *= 0.5;
        rotAcc = rot(0.4 + t * 0.05);
    }
    return w;
}

fn sdEllipse(p: vec2<f32>, ab: vec2<f32>) -> f32 {
    let k0 = length(p / ab);
    let k1 = length(p / (ab * ab));
    return k0 * (k0 - 1.0) / (k1 + 0.0001);
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// SDF for the biomechanical dragonfly: body, four mirrored wings and tail
fn sdDragonfly(p: vec2<f32>, wingspan: f32, flap1: f32, flap2: f32) -> f32 {
    let body = sdEllipse(vec2<f32>(p.x * 5.0, p.y), vec2<f32>(0.12, 0.55));
    let head = length(p - vec2<f32>(0.0, 0.62)) - 0.09;

    let w1uv = rot(flap1) * vec2<f32>(abs(p.x) - 0.08, p.y - 0.12);
    let w1 = sdEllipse(vec2<f32>(w1uv.x * 0.45 / wingspan, w1uv.y * 3.0), vec2<f32>(0.55, 0.12));

    let w2uv = rot(flap2 + 0.4) * vec2<f32>(abs(p.x) - 0.08, p.y + 0.12);
    let w2 = sdEllipse(vec2<f32>(w2uv.x * 0.4 / wingspan, w2uv.y * 3.0), vec2<f32>(0.45, 0.1));

    let tail = sdSegment(p, vec2<f32>(0.0, -0.55), vec2<f32>(0.0, -1.25)) - 0.03;
    return min(min(min(body, head), w1), min(w2, tail));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Wing-local frame of the nearest wing (same transforms as sdDragonfly).
// Returns (span s: 0 root -> 1 tip, chord c: -1 trailing -> +1 leading, wing SDF, fore/hind 0/1).
fn wingFrame(p: vec2<f32>, wingspan: f32, flap1: f32, flap2: f32) -> vec4<f32> {
    let w1uv = rot(flap1) * vec2<f32>(abs(p.x) - 0.08, p.y - 0.12);
    let e1 = vec2<f32>(w1uv.x * 0.45 / wingspan, w1uv.y * 3.0);
    let w1 = sdEllipse(e1, vec2<f32>(0.55, 0.12));

    let w2uv = rot(flap2 + 0.4) * vec2<f32>(abs(p.x) - 0.08, p.y + 0.12);
    let e2 = vec2<f32>(w2uv.x * 0.4 / wingspan, w2uv.y * 3.0);
    let w2 = sdEllipse(e2, vec2<f32>(0.45, 0.1));

    let hind = w2 < w1;
    let s = select(e1.x / 0.55, e2.x / 0.45, hind);
    let c = select(-e1.y / 0.12, -e2.y / 0.1, hind);
    return vec4<f32>(s, c, min(w1, w2), select(0.0, 1.0, hind));
}

// Idea 1: chitin membrane thin-film interference.
// Membrane thickness thickens toward the root and the leading edge and varies per cross-vein cell;
// optical path difference 2*n*d*cos(theta_t) evaluated at three wavelengths gives structural color.
fn wingThinFilm(s: f32, c: f32, cellId: f32, flapTilt: f32, bass: f32) -> vec3<f32> {
    let n = 1.56; // chitin
    let thicknessNm = 420.0 * (1.25 - 0.45 * clamp(s, 0.0, 1.0)) * (1.0 + 0.12 * c)
                    + (cellId - 0.5) * 90.0 + bass * 40.0;
    let sinI = clamp(sin(flapTilt) * 0.9 + abs(c) * 0.25, -0.95, 0.95);
    let sinT = sinI / n;
    let cosT = sqrt(max(1.0 - sinT * sinT, 0.0));
    let opd = 2.0 * n * thicknessNm * cosT;
    let lambda = vec3<f32>(650.0, 532.0, 450.0);
    return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(opd * 2.0 * PI / lambda + PI);
}

// Idea 2: longitudinal vein spars (costa / radius / media / cubitus) converging at the wing root,
// the nodus kink on the leading edge, and the dark pigmented pterostigma cell near the tip.
// Returns (spar vein mask, pterostigma mask).
fn wingVenation(s: f32, c: f32, wingspan: f32) -> vec2<f32> {
    let sc = clamp(s, 0.0, 1.0);
    // Spars fan out from root: chord position compressed near root.
    let fan = c / (0.35 + 0.65 * sc);
    let nodus = smoothstep(0.42, 0.5, sc) * 0.12;
    let sparCoord = (fan - nodus) * 2.2 + 0.5;
    let sparLine = abs(fract(sparCoord) - 0.5);
    let sparWidth = 0.06 + 0.04 * (1.0 - sc) + (0.1 - wingspan) * 0.1;
    var spar = smoothstep(sparWidth, sparWidth * 0.3, sparLine);
    // Costa: thick leading-edge rim.
    spar = max(spar, smoothstep(0.78, 0.95, c));
    // Nodus cross-bar.
    spar = max(spar, smoothstep(0.035, 0.01, abs(sc - 0.46)) * smoothstep(0.2, 0.6, c));
    let stigma = smoothstep(0.09, 0.05, abs(sc - 0.82)) * smoothstep(0.55, 0.75, c) * smoothstep(1.05, 0.9, c);
    return vec2<f32>(spar * smoothstep(1.02, 0.9, sc), stigma);
}

// Strange-attractor crystal particles
fn attractorParticles(p: vec2<f32>, t: f32, audio: f32) -> f32 {
    var z = p * 3.0;
    var density = 0.0;
    let a = 1.7 + 0.2 * sin(t * 0.15);
    let b = 0.6 + audio * 0.3;
    for (var i = 0; i < 18; i = i + 1) {
        let nx = sin(a * z.y) - cos(b * z.x);
        let ny = sin(a * z.x) + cos(b * z.y);
        z = vec2<f32>(nx, ny);
        density += exp(-length(z - p) * 8.0);
    }
    return clamp(density * 0.15, 0.0, 1.0);
}

// Radial chromatic aberration for shattered-crystal optics
fn chromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
    let d = uv - vec2<f32>(0.5);
    let angle = atan2(d.y, d.x) + time * 0.3;
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(color.r * (1.0 + shift.x), color.g, color.b * (1.0 - shift.y));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }

    let res = vec2<f32>(dims);
    let uv01 = vec2<f32>(id.xy) / res;
    let uv = (vec2<f32>(id.xy) - 0.5 * res) / min(res.x, res.y);

    let time = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let mouse = u.zoom_config.yz;
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let wingspan = clamp(u.zoom_params.x, 0.05, 0.5);
    let plasma = u.zoom_params.y;
    let veinDensity = u.zoom_params.z;   // default 0.5 -> 14.0 cross-vein cells (original)
    let flapRate = u.zoom_params.w;      // default 0.5 -> 18.0 rad/s (original)

    let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);
    let inDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv01, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let prevCoord = clamp(vec2<i32>(id.xy), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
    let prev = textureLoad(dataTextureC, prevCoord, 0);

    // Click ripples: wing-downwash gust rings from each click
    var gust = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0 || age > 2.5) { continue; }
        let rd = length((uv01 - rp.xy) * vec2<f32>(res.x / min(res.x, res.y), res.y / min(res.x, res.y)));
        let ring = exp(-pow((rd - age * 0.45) * 22.0, 2.0));
        gust += ring * (1.0 - age / 2.5);
    }
    gust = clamp(gust, 0.0, 1.5);

    // Domain-warped aurora background with curl advection
    let warp = domainWarp(uv * 2.5 + vec2<f32>(0.0, time * 0.04), time * 0.06);
    let curl = curlNoise(uv * 3.0, time * 0.1);
    let bgNoise = fbm(warp + curl * 0.15 + vec2<f32>(gust * 0.2), 5);
    let worley = worleyLayers(uv * 4.0, time);
    let aurora = vec3<f32>(0.1, 0.35, 0.5) * bgNoise * (1.0 + bass * 0.5 + gust * 0.8);
    var bgColor = aurora + vec3<f32>(0.05, 0.0, 0.12) * (1.0 - bgNoise);
    bgColor += vec3<f32>(0.6, 0.9, 1.0) * worley * (treble * 0.6 + gust * 0.3);

    // Dragonfly SDF (Flap Rate slider; bass deepens the stroke, held mouse hovers faster)
    let flapSpeed = time * 36.0 * flapRate * (1.0 + held * 0.4);
    let strokeGain = 1.0 + bass * 0.4;
    let flap1 = sin(flapSpeed) * 0.35 * strokeGain + 0.45;
    let flap2 = sin(flapSpeed + 1.8) * 0.3 * strokeGain + 0.35;
    var p = uv;
    p = rot(mouse.x * 1.5) * p;
    let d = sdDragonfly(p, wingspan, flap1, flap2);
    let edge = abs(d);
    let density = smoothstep(0.08, 0.0, d);
    let shell = exp(-edge * 14.0);

    // Voronoi wing veins (branchless selection via smoothstep)
    let veinScale = 6.0 + veinDensity * 16.0;
    let v = voronoi(p * veinScale + vec2<f32>(time * 0.2));
    let vein = smoothstep(0.06, 0.02, v.x) * (1.0 - smoothstep(0.0, 0.2, p.y));

    // Iridescent palette + orbit trap around body axis
    let orbit = abs(p.x) * 8.0 + edge * 4.0;
    let irid = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(0.0, 0.33, 0.67) * PI * 2.0 + time * 1.2 + orbit - v.y * 4.0);
    var bodyColor = mix(irid, vec3<f32>(0.05, 0.1, 0.15), vein * 0.8);

    // Wing membrane: thin-film structural color, spar veins and pterostigma (native ideas)
    let wf = wingFrame(p, wingspan, flap1, flap2);
    let wingOnly = smoothstep(0.08, 0.0, wf.z) * smoothstep(0.03, 0.1, abs(p.x));
    let flapTilt = select(flap1, flap2 + 0.4, wf.w > 0.5);
    let film = wingThinFilm(wf.x, wf.y, v.y, flapTilt, bass);
    let ven = wingVenation(wf.x, wf.y, wingspan);
    let filmMix = wingOnly * (0.55 + mids * 0.2);
    bodyColor = mix(bodyColor, film * 1.15, filmMix * (1.0 - vein * 0.6));
    bodyColor = mix(bodyColor, vec3<f32>(0.04, 0.07, 0.1), wingOnly * ven.x * (0.4 + veinDensity * 0.5));
    bodyColor = mix(bodyColor, vec3<f32>(0.12, 0.02, 0.03), wingOnly * ven.y * 0.9);
    bodyColor += vec3<f32>(1.0, 0.35, 0.2) * wingOnly * ven.y * treble * 0.6;

    // Plasma core glow
    let core = smoothstep(0.15, 0.0, length(p - vec2<f32>(0.0, 0.2))) * plasma * 4.0;
    bodyColor += vec3<f32>(0.2, 0.9, 0.6) * core * (1.0 + bass * 0.5);

    // Strange-attractor crystal particles
    let particles = attractorParticles(uv, time, treble);
    let particleGlow = vec3<f32>(1.0, 0.85, 0.4) * particles * (treble * 0.6 + gust * 0.4);

    // Branchless mouse halo (held intensifies)
    let mouseDist = length(uv01 - mouse);
    let mouseGlow = exp(-mouseDist * 18.0) * (0.25 + mids * 0.4) * (1.0 + held * 1.5);

    // Composite with temporal feedback from dataTextureC (exact load)
    var color = mix(video.rgb, bodyColor, clamp(density + shell * 0.6, 0.0, 1.0));
    color = mix(color, bgColor, 0.45 * (1.0 - density));
    color += particleGlow;
    color += vec3<f32>(0.4, 0.8, 1.0) * mouseGlow;
    color += vec3<f32>(0.5, 0.9, 1.0) * gust * 0.25;
    color = mix(color, prev.rgb, 0.06 + mids * 0.04);

    // Post-processing: chromatic aberration and ACES display transform
    color = chromaticShift(color, uv01, treble * 0.025 + held * 0.01, time);
    color = acesToneMap(color * (1.0 + bass * 0.15));

    // Alpha: dragonfly coverage, SDF shell proximity, thin-film membrane and particle emission
    let alpha = clamp(density + shell * 0.35 + wingOnly * 0.15 + particles * 0.3 + gust * 0.2, 0.0, 1.0);
    let depth = mix(inDepth, 0.15 + density * 0.65, clamp(density + shell * 0.6, 0.0, 1.0));

    let finalColor = vec4<f32>(color, alpha);
    textureStore(writeTexture, id.xy, finalColor);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, finalColor);
}
