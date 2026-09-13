// ═══════════════════════════════════════════════════════════════════
//  Luminescent Chrono-Prism Astro-Stag
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-13
//  Ideas: recursive forked antler tines (Fractal Intensity); per-channel prism dispersion of the aurora rift (Prismatic Refraction); chrono-echo afterimage from exact C history (Temporal Distortion)
//  A packing: ACES display RGBA (C read back as colour for the chrono-echo)
// ═══════════════════════════════════════════════════════════════════
// Raymarched prismatic void-stag with volumetric aurora bloom.
// Outputs: writeTexture, writeDepthTexture (march distance, far = 1), dataTextureA (display history)

struct Uniforms {
    config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50, NOT audio), .zw = resolution
    zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down
    zoom_params: vec4<f32>,  // x=Temporal Distortion, y=Rift Density, z=Fractal Intensity, w=Prismatic Refraction
    ripples: array<vec4<f32>, 50>,
};

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


fn acesTone(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)),
                 vec3<f32>(0.0), vec3<f32>(1.0));
}

// --- SDF FUNCTIONS ---
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// --- NOISE / FBM ---
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                       dot(hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
                   mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                       dot(hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
               mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                       dot(hash3(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
                   mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                       dot(hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

// Idea 1: recursive antler tines. Three tines branch off the mirrored main
// beam, each forking once more; length follows Fractal Intensity.
fn sdAntlerTines(tp: vec3<f32>, a: vec3<f32>, b: vec3<f32>, time: f32, fractalAmt: f32) -> f32 {
    var d = 1e5;
    let lenGain = clamp(fractalAmt, 0.0, 2.0);
    for (var k = 1; k < 4; k = k + 1) {
        let fk = f32(k);
        let base = mix(a, b, 0.2 + 0.25 * fk);
        let sway = sin(time * 0.8 + fk * 1.7) * 0.15;
        let dir = normalize(vec3<f32>(0.55 - 0.12 * fk, 0.6 + 0.1 * fk, -0.35 + 0.25 * fk + sway));
        let len = 0.32 * lenGain * (1.0 - 0.2 * fk);
        let tip = base + dir * len;
        d = min(d, sdCapsule(tp, base, tip, 0.055 - 0.008 * fk));
        // second-level fork from the upper part of each tine
        let forkBase = base + dir * len * 0.6;
        let forkDir = normalize(dir + vec3<f32>(-0.35, 0.55, 0.2 * sway));
        d = min(d, sdCapsule(tp, forkBase, forkBase + forkDir * len * 0.5, 0.03));
    }
    return d;
}

// Idea 2: procedural aurora rift seen THROUGH the prism body
fn riftColor(dir: vec3<f32>, time: f32, rift: f32) -> vec3<f32> {
    let curtain = dir.y - 0.25 * sin(dir.x * 3.0 + time * 0.3) - 0.1 * sin(dir.z * 5.0 - time * 0.2);
    let band = exp(-abs(curtain) * 7.0);
    let fold = 0.5 + 0.5 * sin(dir.x * 11.0 + dir.z * 4.0 + time * 0.7);
    return vec3<f32>(0.01, 0.02, 0.05)
        + (vec3<f32>(0.1, 0.9, 0.6) * band + vec3<f32>(0.6, 0.2, 1.0) * band * fold * 0.6)
        * (0.35 + 0.35 * rift);
}

// --- SCENE MAP ---
fn map(p_in: vec3<f32>, time: f32, audio: f32, params: vec4<f32>) -> f32 {
    // Mouse drags the stag (canvas uv centred; y=0 is top so world y flips)
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0)) - vec2<f32>(0.5);
    let p = p_in - vec3<f32>(mouse.x * 2.0, -mouse.y * 2.0, 0.0);
    // Stag Core
    var body = sdCapsule(p, vec3<f32>(0.0, 0.0, -1.0), vec3<f32>(0.0, 0.0, 1.0), 0.5);
    // Add biomechanical noise details
    body += noise(p * 5.0 - vec3<f32>(0.0, 0.0, time)) * 0.1;

    // Antlers & Fractals (warped space)
    var tp = p;
    tp.x = abs(tp.x);
    let beamA = vec3<f32>(0.3, 0.5, 1.0);
    let beamB = vec3<f32>(0.8, 1.5, 1.2);
    var antler = sdCapsule(tp, beamA, beamB, 0.1);
    antler = smin(antler, sdAntlerTines(tp, beamA, beamB, time, params.z), 0.05);

    // Smooth blend
    var scene = smin(body, antler, 0.2);

    // Apply temporal shockwaves
    scene += sin(length(p) * 10.0 - time * 5.0) * audio * 0.05 * params.x;

    return scene;
}

// --- RAYMARCHING ---
fn calcNormal(p: vec3<f32>, time: f32, audio: f32, params: vec4<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * map(p + e.xyy, time, audio, params) +
                     e.yyx * map(p + e.yyx, time, audio, params) +
                     e.yxy * map(p + e.yxy, time, audio, params) +
                     e.xxx * map(p + e.xxx, time, audio, params));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= resolution.x || fragCoord.y >= resolution.y) { return; }

    let uv = (fragCoord - 0.5 * resolution) / resolution.y;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio = bass;
    let params = u.zoom_params; // Temporal, Rift, Fractal, Refraction

    // Camera — mouse orbits the prism, bass dollies it forward
    // (HEAD divided the 0..1 mouse uv by resolution, so the orbit never moved)
    let mouseRaw = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0)) - vec2<f32>(0.5);
    let mouseNorm = vec2<f32>(mouseRaw.x, -mouseRaw.y);
    let ro = vec3<f32>(mouseNorm.x * 1.5, mouseNorm.y * 1.5, -3.0 + bass * 0.5);
    let rd = normalize(vec3<f32>(uv.x, -uv.y, 1.0)); // screen y down -> world y up (antlers rise)

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var p = ro;
    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        d = map(p, time, audio, params);
        if (d < 0.001 || t > 10.0) { break; }
        t += d;
    }

    // Shading
    var col = vec3<f32>(0.01, 0.02, 0.05); // Volumetric Void BG
    let hit = t < 10.0;
    var fresnelOut = 0.0;
    if (hit) {
        let n = calcNormal(p, time, audio, params);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        fresnelOut = fresnel;

        // Liquid Aurora / Prismatic colors
        let baseColor = vec3<f32>(0.1, 0.8, 1.0) + sin(p * 2.0 + time) * 0.2;
        col = baseColor * diff + fresnel * vec3<f32>(0.8, 0.2, 1.0) * params.z;

        // Mids drive an iridescent spectral sheen across the surface
        let sheen = sin(dot(n, rd) * 8.0 + time * 2.0 + mids * 6.0) * 0.5 + 0.5;
        col += vec3<f32>(1.0, 0.4, 0.7) * sheen * mids * 0.4 * fresnel;

        // Idea 2: spectral prism dispersion — per-channel IOR spread
        let spread = 0.018 * params.w * (1.0 + treble * 0.5);
        var disp = vec3<f32>(0.0);
        for (var c = 0; c < 3; c = c + 1) {
            let eta = 1.0 / (1.42 + (f32(c) - 1.0) * spread);
            var r = refract(rd, n, eta);
            r = select(r, reflect(rd, n), dot(r, r) < 1e-6); // TIR fallback
            disp[c] = riftColor(normalize(r + vec3<f32>(0.0, 0.0, 1e-5)), time, params.y)[c];
        }
        let dispAmt = smoothstep(0.0, 1.0, params.w) * (1.0 - fresnel);
        col += disp * dispAmt * 1.2;
    }

    // Bloom / Volumetric Glow — bass pumps the volumetric haze
    col += vec3<f32>(0.1, 0.3, 0.8) * exp(-t * 0.2) * params.y * (1.0 + bass * 0.5);

    // Depth from raymarch distance, normalised into 0..1
    let depth = clamp(t / 10.0, 0.0, 1.0);

    // Alpha: surface hits are opaque, the void stays transparent
    // ACES on display RGB
    var tone = acesTone(max(col, vec3<f32>(0.0)));

    // Idea 3: chrono-echo — exact C history a few pixels back along a slow
    // drift, colour-rotated per generation so ghosts fan into the spectrum.
    let pixel = vec2<i32>(id.xy);
    let lag = params.x * 1.5;
    let drift = vec2<f32>(cos(time * 0.35), sin(time * 0.35)) * lag;
    let echoCoord = clamp(pixel - vec2<i32>(round(drift)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
    let prev = textureLoad(dataTextureC, echoCoord, 0);
    let echoW = clamp(params.x * 0.12, 0.0, 0.6) * (1.0 + bass * 0.3) * select(1.0, 0.25, hit);
    let ghost = prev.gbr * vec3<f32>(0.92, 0.85, 1.0) * clamp(echoW, 0.0, 0.7);
    tone = tone + (vec3<f32>(1.0) - tone) * ghost; // screen blend, stays <= 1

    // Alpha: hit coverage minus fresnel transmission; void carries haze + echo
    let hitAlpha = 0.78 + 0.2 * (1.0 - fresnelOut);
    let voidAlpha = clamp(length(tone) * 0.6 + dot(ghost, vec3<f32>(0.33)), 0.0, 0.9);
    let alpha = clamp(select(voidAlpha, hitAlpha, hit), 0.0, 1.0);
    let outColor = vec4<f32>(tone, alpha);

    textureStore(writeTexture, pixel, outColor);
    textureStore(dataTextureA, pixel, outColor);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
