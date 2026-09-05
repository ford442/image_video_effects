// ═══════════════════════════════════════════════════════════════════
//  Quantum Ripples
//  Category: image
//  Techniques: mouse-driven, interactive, audio-reactive, temporal-feedback,
//             depth-aware, chromatic-aberration, domain-warped-fbm, curl-turbulence,
//             voronoi-displacement, sdf-masking, audio-palette
//  Complexity: Medium-High
//  Upgraded: 2026-07-08
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
const PHI: f32 = 1.61803398875;

// ── Canonical hash / noise ────────────────────────────────────────
fn hashf(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    let h = p * mat2x2<f32>(vec2<f32>(127.1, 311.7), vec2<f32>(269.5, 183.3));
    return fract(sin(h) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0; var amp = 0.5; var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}
fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
    return p + strength * q;
}

// ── Color utilities ───────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(TAU * (c * t + d));
}

// ── Divergence-free velocity field ────────────────────────────────
fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.001;
    let nx = fbm(p + vec2<f32>(0.0, eps), 4) - fbm(p - vec2<f32>(0.0, eps), 4);
    let ny = fbm(p + vec2<f32>(eps, 0.0), 4) - fbm(p - vec2<f32>(eps, 0.0), 4);
    return vec2<f32>(nx, -ny) / (2.0 * eps + t * 0.0);
}

// ── Voronoi displacement with jittered, time-evolving cells ───────
fn voronoi(p: vec2<f32>, t: f32) -> vec2<f32> {
    let k = floor(p);
    var md = 1e5;
    var cell = 0.0;
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash22(k + g) * 2.0 - 1.0;
            let r = g + 0.5 + 0.35 * sin(t * 0.4 + TAU * o);
            let d = dot(p - (k + r), p - (k + r));
            if (d < md) {
                md = d;
                cell = hashf(dot(k + g, vec2<f32>(12.9898, 78.233)));
            }
        }
    }
    return vec2<f32>(sqrt(md), cell);
}

// ── SDF rounded-box mask for spatial shaping ──────────────────────
fn sdRoundedBox(p: vec2<f32>, b: vec2<f32>, r: f32) -> f32 {
    let q = abs(p) - b + vec2<f32>(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2<f32>(0.0))) - r;
}

// ── Chromatic aberration for texture-backed shaders ───────────────
fn chromaticAberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
    let center = vec2<f32>(0.5);
    let delta = uv - center;
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * inverseSqrt(lenSq);
    let offset = dir * max(amount, 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    return vec3<f32>(r, g, b);
}

// ── Wave source with domain-warped FBM turbulence ─────────────────
fn waveField(uv: vec2<f32>, center: vec2<f32>, aspect: f32, t: f32,
             freq: f32, spd: f32, turb: f32) -> vec2<f32> {
    let dx = (uv.x - center.x) * aspect;
    let dy = uv.y - center.y;
    let d = sqrt(dx * dx + dy * dy);
    let dir = select(normalize(vec2<f32>(dx, dy)), vec2<f32>(0.0, 0.0), d < 0.001);
    let warpedUv = domainWarp(uv * 3.0 + dir * 2.0, 0.35, 3);
    let warp = fbm(warpedUv + t * 0.15, 3) * turb;
    let phase = d * freq - t * spd + warp;
    let harmonic = sin(phase * PHI + TAU * 0.25) * 0.5;
    let w = (sin(phase) + harmonic) * exp(-d * 3.0) * 0.666;
    return dir * w;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01  = vec2<f32>(pixel) / res;
    let uv    = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time  = u.config.x;
    let mouse = u.zoom_config.yz;
    let held = f32(u.zoom_config.w > 0.5);
    let aspect = res.x / res.y;

    let freq = u.zoom_params.x * 24.0 + 2.0;
    let spd  = u.zoom_params.y * 6.0;
    let amp  = u.zoom_params.z * 0.12;
    let csh  = u.zoom_params.w;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth  = textureLoad(readDepthTexture, pixel, 0).r;
    let prev   = textureLoad(dataTextureC, pixel, 0);

    // Curl-noise advection for organic, divergence-free turbulence
    let curl = curl2D(uv * 4.0 + time * 0.1, time) * (0.02 + bass * 0.02);
    let sampleUv = clamp(uv01 + curl, vec2<f32>(0.0), vec2<f32>(1.0));

    // Voronoi displacement perturbs the wave lattice into cellular interference
    let voroScale = 6.0 + mids * 4.0;
    let voro = voronoi(uv * voroScale + time * 0.2, time);
    let voroDisp = (voro.x - 0.45) * 0.03 * (1.0 + bass);

    var disp = waveField(sampleUv + voroDisp, mouse, aspect, time, freq, spd, 0.5 + bass * 0.2);

    // Entangled twin-ripple sources orbit the pointer in opposite phase.
    let twinAxis = vec2<f32>(cos(time * 1.3), sin(time * 1.1)) * (0.07 + u.zoom_params.z * 0.1);
    let twinA = clamp(mouse + twinAxis, vec2<f32>(0.0), vec2<f32>(1.0));
    let twinB = clamp(mouse - twinAxis, vec2<f32>(0.0), vec2<f32>(1.0));
    disp += waveField(sampleUv + voroDisp, twinA, aspect, time, freq * PHI, spd * 1.1, 0.35) * 0.42;
    disp -= waveField(sampleUv + voroDisp, twinB, aspect, time + PI, freq * PHI, spd * 1.1, 0.35) * 0.42;

    // Superpose historical ripple sources (max 8 for performance)
    let rippleCount = min(u32(u.config.y), 8u);
    var clickEnergy = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (rp.z > 0.0 && age >= 0.0 && age < 1.8) {
            let rf = freq * (1.0 + hash21(rp.xy) * 0.3);
            let decay = exp(-age * 1.6);
            disp += waveField(sampleUv + voroDisp, rp.xy, aspect, time, rf, spd * 0.7, 0.25) * decay * 0.7;
            clickEnergy += decay * exp(-abs(distance(uv01, rp.xy) - age * 0.5) * 70.0);
        }
    }

    let activeAmp = 1.0 + held * 1.8 + clickEnergy * 0.9;
    disp *= amp * activeAmp;

    // SDF mask centered on mouse shapes the ripple domain into a soft portal
    let boxUv = (uv01 - mouse) * vec2<f32>(aspect, 1.0);
    let boxSize = vec2<f32>(0.25 + bass * 0.08, 0.18 + treble * 0.05);
    let sdf = sdRoundedBox(boxUv, boxSize, 0.08);
    let mask = 1.0 - smoothstep(0.0, 0.35, sdf);

    // Depth-aware refraction sharpens the lensing at foreground edges
    let depthOffset = (uv01 - vec2<f32>(0.5)) * depth * 0.02;
    let srcUV = clamp(uv01 - disp * mask + depthOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    // Color from displaced source + chromatic aberration
    let base = textureSampleLevel(readTexture, u_sampler, srcUV, 0.0);
    var color = base.rgb;
    let caAmt = 0.003 * (1.0 + bass) + depth * 0.002 + length(disp) * 0.5;
    let ca = chromaticAberration(srcUV, caAmt);
    color = mix(color, ca, clamp(csh + depth * 0.3, 0.0, 1.0));

    // Audio-driven palette + energy-based hue shift
    let energy = length(disp) / (amp * activeAmp + 0.001);
    let palT = energy * 0.6 + time * 0.08 + voro.y * 0.2 + mids * 0.3;
    let pal = palette(palT,
                      vec3<f32>(0.5, 0.5, 0.5),
                      vec3<f32>(0.5, 0.5, 0.5),
                      vec3<f32>(1.0, 1.0, 0.9),
                      vec3<f32>(0.0, 0.33, 0.67));
    color = mix(color, color * pal * (1.0 + bass * 0.4), clamp(csh * energy + bass * 0.2, 0.0, 1.0));

    // Probability-cloud interference and chromatic Voronoi diffraction.
    let probability = exp(-length(boxUv) * (3.0 + freq * 0.04))
                    * pow(0.5 + 0.5 * cos(length(boxUv) * freq * 2.0 - time * spd), 2.0);
    let diffraction = pow(1.0 - smoothstep(0.04, 0.24, voro.x), 3.0);
    let quantumColor = palette(voro.y + probability + time * 0.06,
                               vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0),
                               vec3<f32>(0.0, 0.33, 0.67));
    color += quantumColor * (probability * 0.2 + diffraction * 0.16 + clickEnergy * 0.3)
           * (0.5 + mids + treble * 0.5);

    let shift = energy * csh * sin(time * 0.5) * 0.3;
    color.r += shift + energy * treble * 0.08;
    color.b -= shift;
    color += vec3<f32>(energy * bass * 0.12);

    // Temporal feedback with decay
    let decay = 0.97 - csh * 0.03;
    let blend = 0.18 + bass * 0.08;
    color = mix(prev.rgb * decay, color, blend);

    // ACES tone map + semantic alpha
    color = acesToneMap(color * (0.9 + mids * 0.2));
    let effectIntensity = energy * (0.5 + bass * 0.5) * mask;
    let alpha = mix(base.a, clamp(effectIntensity, 0.0, 0.95), 0.7);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
