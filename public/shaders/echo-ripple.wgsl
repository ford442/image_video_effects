// ═══════════════════════════════════════════════════════════════════
//  Echo Ripple — Batch 60
//  Thin-film / bioluminescent harmonics, held gravity bowl, capped
//  click ripples (50), exact-load C advection, ACES display.
//  A packing: dataTextureA = [mixedRGB, bassEnvelope]
//             (history.a feeds bass_env; display RGB lives in A.rgb)
//  Unused: dataTextureB. Workgroup 16×16×1. Bindings 0–12 canonical.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
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
    for (var i: i32 = 0; i < oct; i++) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn echoWave(uv: vec2<f32>, center: vec2<f32>, aspect: f32, freq: f32, speed: f32, age: f32, phase: f32) -> f32 {
    let rd = (uv - center) * vec2<f32>(aspect, 1.0);
    let rdist = length(rd);
    return sin(rdist * freq - age * speed + phase) * smoothstep(0.7, 0.0, rdist) * step(0.0, age);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let held = f32(mouseDown > 0.5);

    let plasma = plasmaBuffer[0];
    let bass = plasma.x;
    let mids = plasma.y;
    let treble = plasma.z;
    // Optional FFT bins for local shimmer (engine fills 1–8 when available).
    var binShimmer = 0.0;
    if (arrayLength(&plasmaBuffer) > 4u) {
        binShimmer = (plasmaBuffer[1].x + plasmaBuffer[2].y + plasmaBuffer[3].z + plasmaBuffer[4].x) * 0.25;
    }

    let history = textureLoad(dataTextureC, pixel, 0);
    let envBass = bass_env(history.a, bass, 0.8, 0.15);
    let beat = envBass * (0.7 + 0.3 * sin(time * 3.0));

    let frequency = u.zoom_params.x * 30.0 + 2.0;
    let speed = u.zoom_params.y * 8.0 + 0.5;
    let decay = u.zoom_params.z * 0.97 + 0.02;
    let strength = u.zoom_params.w * 0.15 + 0.01;

    // Held gravity bowl: stronger inverse-square pull + soft bowl falloff.
    let d = (uv01 - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(d);
    let dist2 = dot(d, d) + 0.001;
    let bowl = exp(-dist * dist * mix(4.0, 10.0, held));
    let gravAmp = strength * (0.02 + held * 0.085) * (1.0 + bowl * held * 1.6);
    let grav = d * gravAmp / dist2;

    let wave = sin(dist * frequency - time * speed + mids * 2.0) * (1.0 + beat * 3.0);
    let atten = smoothstep(0.6, 0.0, dist);

    // Click ripples — contract cap 50 (was 12).
    let rippleCount = min(u32(u.config.y), 50u);
    var totalWave = wave;
    var echoFilm = 0.0;
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let age = time - r.z;
        let phase = f32(i) * 0.7;
        let rw = echoWave(uv01, r.xy, aspect, frequency, speed, age, phase);
        let ageFade = exp(-max(age, 0.0) * 0.7);
        totalWave += rw * ageFade;
        // Secondary thin-film harmonic per echo center.
        let rd = (uv01 - r.xy) * vec2<f32>(aspect, 1.0);
        let rdist = length(rd);
        echoFilm += abs(sin(rdist * frequency * 3.0 - age * speed * 2.1 + phase))
                  * smoothstep(0.55, 0.0, rdist) * ageFade;
    }

    let clickWave = sin(dist * 50.0 - time * 20.0) * mouseDown * smoothstep(0.25, 0.0, dist);
    // Held intensifies a standing bowl ripple under the cursor.
    let heldBowlWave = sin(dist * frequency * 1.4 - time * speed * 0.6) * held * bowl * (1.2 + beat);

    let rawDir = uv01 - mouse;
    let rawDist = length(rawDir) + 0.0001;
    let dir = rawDir / rawDist;

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let depthMod = mix(0.6, 1.2, depth);

    let lodOct = select(1, 3, dist < 0.45);
    let drift = fbm(uv01 * 4.0 + time * 0.1, lodOct) * 0.01 * (mids + binShimmer * 0.5);

    let distort = (totalWave + clickWave + heldBowlWave) * strength * atten * depthMod;
    let displacement = dir * (distort + drift) - grav;
    let sampleUV = clamp(uv01 - displacement, vec2<f32>(0.0), vec2<f32>(1.0));

    let sep = 0.003 * strength * (1.0 + held * 0.35);
    var color: vec3<f32>;
    color.r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(sep, 0.0), 0.0).r;
    color.g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    color.b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(sep, 0.0), 0.0).b;

    let fftTint = vec3<f32>(envBass * 0.5, mids * 0.3, treble * 0.6) * totalWave * atten * strength * 10.0;
    color += fftTint;

    let hash = fract(sin(dot(uv01 * 1000.0, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let sparkle = treble * step(0.90, hash) * atten * (0.45 + held * 0.25);
    color += vec3<f32>(sparkle);

    // Richer thin-film interference + bioluminescent wake harmonics.
    let filmPhase = TAU * (vec3<f32>(dist * frequency * 0.08 - time * 0.12)
                         + vec3<f32>(0.0, 0.33, 0.67)
                         + vec3<f32>(echoFilm * 0.15));
    let film = 0.5 + 0.5 * cos(filmPhase);
    let harmonic = pow(0.5 + 0.5 * sin(dist * frequency * 2.0 - time * speed * 1.7), 6.0);
    let harmonic2 = pow(0.5 + 0.5 * sin(dist * frequency * 4.2 - time * speed * 2.4 + mids), 8.0);
    let wake = exp(-abs(fract((uv01.x + uv01.y) * 3.0 - time * 0.45) - 0.5) * 28.0)
             * abs(totalWave) * atten;
    let bioGlow = vec3<f32>(0.15, 0.85, 0.55) * harmonic2 * (0.12 + treble * 0.2)
                + vec3<f32>(0.55, 0.25, 1.0) * echoFilm * 0.08 * (0.4 + mids);
    color += film * (harmonic * 0.22 + wake * 0.28 + held * bowl * 0.12) * (0.5 + mids + treble * 0.5 + binShimmer * 0.3);
    color += bioGlow;

    // Exact-load temporal advection (preserve feedback contract).
    let advect = displacement * 0.02;
    let advectUV = clamp(uv01 - advect, vec2<f32>(0.0), vec2<f32>(1.0));
    let advectPixel = vec2<i32>(clamp(advectUV * res, vec2<f32>(0.0), res - 1.0));
    let prev = textureLoad(dataTextureC, advectPixel, 0);
    let mixed = mix(color, prev.rgb, decay * (1.0 - atten * 0.25));

    let caStr = 0.003 * (1.0 + envBass) + depth * 0.001 + held * 0.0015;
    let caAngle = atan2(uv01.y - 0.5, uv01.x - 0.5);
    let caShift = vec2<f32>(cos(caAngle), sin(caAngle)) * caStr;
    var outColor = vec3<f32>(
        mixed.r * (1.0 + caShift.x * 0.8),
        mixed.g,
        mixed.b * (1.0 - caShift.y * 0.5)
    );
    outColor = acesToneMap(outColor * (0.9 + mids * 0.2 + held * bowl * 0.08));

    let inputAlpha = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).a;
    let finalAlpha = mix(inputAlpha, clamp(luma(outColor) * 1.5, 0.2, 0.95), atten * 0.7);

    textureStore(writeTexture, pixel, vec4<f32>(outColor, finalAlpha));
    // A = [mixed display RGB, bass envelope] — C.a feeds next-frame env.
    textureStore(dataTextureA, pixel, vec4<f32>(mixed, envBass));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
