// ═══════════════════════════════════════════════════════════════════
//  Heighway Dragon Curve (Algorithmist Upgrade)
//  Category: generative
// ═══════════════════════════════════════════════════════════════════
const PI=3.14159265358979323846; const TAU=6.28318530717958647692;
const PHI=1.61803398874989484820; const SQRT2=1.41421356237309504880;
const SQRT3=1.73205080756887729352; const E=2.71828182845904523536;
const LN2=0.69314718055994530941; const INV_PI=0.31830988618379067154;

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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn segDist(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let ab = b - a; let ap = p - a;
    let t = clamp(dot(ap, ab) / (dot(ab, ab) + 1e-8), 0.0, 1.0);
    return length(ap - ab * t);
}

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var a = 0.5; var s = 0.0; var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        s = s + a * vnoise(q);
        q = q * 2.02; a = a * 0.5;
    }
    return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
    let r = vec2<f32>(fbm(p + 4.0*q + vec2<f32>(1.7, 9.2)), fbm(p + 4.0*q + vec2<f32>(8.3, 2.8)));
    return fbm(p + 4.0*r);
}

fn clifford(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
    return vec2<f32>(sin(a*p.y) + c*cos(a*p.x), sin(b*p.x) + d*cos(b*p.y));
}

fn kaleido(uv: vec2<f32>, segs: f32) -> vec2<f32> {
    let r = length(uv);
    var a = atan2(uv.y, uv.x);
    let seg = TAU / max(segs, 1.0);
    a = abs(((a % seg) + seg) % seg - seg * 0.5);
    return vec2<f32>(cos(a), sin(a)) * r;
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0/3.0, 1.0/3.0);
    let p = abs(fract(vec3<f32>(h) + k) * 6.0 - 3.0);
    return v * mix(vec3<f32>(1.0), clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0)), s);
}

// ── Visualist toolkit: thin-film iridescence + split-tone grading ──────
// Cos-palette thin-film: hue cycles with optical-path phase (fold order +
// distance falloff), giving the neon line an oil-slick / dragon-scale sheen.
fn thinFilm(phase: f32) -> vec3<f32> {
    return 0.5 + 0.5 * cos(TAU * (phase + vec3<f32>(0.0, 0.33, 0.67)));
}

// Split-tone: cool indigo shadows, warm gold highlights, smoothly keyed on
// luma. Applied in HDR before the ACES rolloff.
fn splitTone(col: vec3<f32>, shadowTint: vec3<f32>, highTint: vec3<f32>, amt: f32) -> vec3<f32> {
    let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
    let t = smoothstep(0.05, 0.8, luma);
    return mix(col, col * mix(shadowTint, highTint, t), amt);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if gid.x >= dims.x || gid.y >= dims.y { return; }

    let coord = vec2<i32>(gid.xy);
    let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
    let time = u.config.x * 2.3;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let hasSpring = arrayLength(&extraBuffer) >= 139u;
    var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
    if (hasSpring) { springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]); lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5; }
    if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
    let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
    let omega = 8.0; let springDecay = exp(-omega * dt); let sdelta = springPos - rawMouse; let temp = (springVel + omega * sdelta) * dt;
    springVel = (springVel - omega * temp) * springDecay; springPos = rawMouse + (sdelta + temp) * springDecay;
    if (hasSpring && gid.x == 0u && gid.y == 0u) { extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y; extraBuffer[137] = time; extraBuffer[138] = 1.0; }
    let mouse = springPos;
    let held = select(1.0, 1.4, u.zoom_config.w > 0.5);
    let depth = textureLoad(readDepthTexture, coord, 0).r;
    let fftPulse = clamp(bass * 0.55 + mids * 0.35 + treble * 0.25, 0.0, 1.5);

    let zoom = mix(0.8, 4.0, u.zoom_params.x);
    let glowWidth = mix(0.015, 0.004, u.zoom_params.y);
    let caAmt = u.zoom_params.z * 0.08;
    let feedback = u.zoom_params.w;

    let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
    let mp = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 0.45 * held;
    var p = ((uv - 0.5) * vec2<f32>(aspect, 1.0) - mp) * zoom * 40.0 + vec2<f32>(16.0, 8.0);

    var clickEnergy = 0.0;
    var clickWarp = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let ripple = u.ripples[ri];
        let age = u.config.x - ripple.z;
        if (age < 0.0 || age > 2.4) { continue; }
        let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
        let rippleDistance = length(delta);
        let front = exp(-abs(rippleDistance - age * 0.21) * 78.0) * exp(-age * 1.15);
        clickEnergy += front;
        clickWarp += delta / max(rippleDistance, 0.001) * front;
    }
    clickEnergy = clamp(clickEnergy, 0.0, 1.0);
    p += clickWarp * (1.4 + zoom * 0.35);

    // Kaleidoscope symmetry + Clifford strange-attractor warp
    let kSegs = mix(2.0, 8.0, sin(time * 0.28) * 0.5 + 0.5);
    p = kaleido(p - vec2<f32>(16.0, 8.0), kSegs) + vec2<f32>(16.0, 8.0);
    let cW = clifford(p * 0.05, 1.5 + time*0.03, -1.7, 1.3, -1.1) * 0.3 * sin(time*0.2);
    p = p + cW;

    let maxSeg = u32(mix(256.0, 512.0, clamp(bass * 1.2, 0.0, 1.0)));
    let segLen = mix(0.08, 0.04, depth);

    var pos = vec2<f32>(0.0, 0.0);
    var dir = vec2<f32>(segLen, 0.0);
    var minDist = 1e9;
    var closestIdx = 0u;
    var closestTurn = false;

    for (var i = 0u; i < maxSeg; i = i + 1u) {
        let a = pos; pos = pos + dir; let b = pos;
        let d = segDist(p, a, b);
        if d < minDist {
            minDist = d;
            closestIdx = i;
            let n = i + 1u;
            let lsb = n & (0u - n);
            closestTurn = ((lsb << 1u) & n) != 0u;
        }
        let n = i + 1u;
        let lsb = n & (0u - n);
        let turn = ((lsb << 1u) & n) != 0u;
        dir = select(vec2<f32>(dir.y, -dir.x), vec2<f32>(-dir.y, dir.x), turn);
    }

    let n1 = closestIdx + 1u;
    let lsb1 = n1 & (0u - n1);
    let t1 = ((lsb1 << 1u) & n1) != 0u;
    let n2 = closestIdx + 2u;
    let lsb2 = n2 & (0u - n2);
    let t2 = ((lsb2 << 1u) & n2) != 0u;
    let turnIntensity = 1.0 + select(0.0, 0.6, t1 != t2);

    // Branchless HSV with FBM hue perturbation
    let hue = mix(0.0, 0.88, f32(closestIdx) / f32(maxSeg)) + warpedFBM(uv * 3.0, time * 0.05) * 0.06;
    let sat = 0.92 + bass * 0.08;
    var neon = hsv2rgb(hue, sat, 1.0);

    // Thin-film iridescence fused into the neon: phase = fold order along
    // the curve + normalized distance falloff + slow temporal drift.
    let filmPhase = f32(closestIdx) / f32(maxSeg) * 0.5
                  + minDist / (glowWidth * 4.0)
                  + time * 0.03;
    neon = mix(neon, neon * thinFilm(filmPhase) * 1.6, 0.45);

    // HDR glow modulated by domain-warped background field
    let bgField = warpedFBM(p * 0.1 + vec2<f32>(time*0.03, 0.0), time) * 0.5 + 0.5;

    // ── 2-temperature lighting rig ─────────────────────────────────────
    // KEY: tight warm filament hugging the line (hot core, HDR > 1.0).
    // FILL: broad cool halo — a volumetric glow approximation 6x wider,
    // shimmered by the real FFT spectrum.
    // Dynamic temperature: treble cools the rig, bass warms it.
    let tempShift = clamp(treble - bass, -1.0, 1.0) * 0.15;
    let warmKey = vec3<f32>(1.28 - tempShift, 0.96, 0.70 + tempShift);
    let coolFill = vec3<f32>(0.58 + tempShift, 0.76, 1.32 - tempShift);

    let coreGlow = exp(-minDist / glowWidth) * turnIntensity * (1.0 + bgField * 0.3);
    let halo = exp(-minDist / (glowWidth * 6.0)) * (0.55 + fftPulse * 0.4);
    var color = neon * coreGlow * warmKey * 2.8
              + neon * halo * coolFill * 0.85;
    color += thinFilm(hue + time * 0.02) * clickEnergy * (0.35 + treble * 0.35);

    // Chromatic aberration on tight folds
    let fold = select(0.0, 1.0, t1 != t2) * smoothstep(0.0, glowWidth * 3.0, coreGlow);
    color = vec3<f32>(color.r * (1.0 + fold * caAmt), color.g,
                        color.b * (1.0 - fold * caAmt * 0.5));

    // Split-tone grade (cool indigo shadows / warm gold highlights) in HDR
    color = splitTone(color, vec3<f32>(0.72, 0.80, 1.22), vec3<f32>(1.22, 1.02, 0.78), 0.5);

    // Atmospheric depth haze: far fragments sink into a cool fog, kept
    // bounded so the fractal stays legible; suppressed on the hot core.
    let hazeColor = vec3<f32>(0.05, 0.07, 0.16);
    let hazeAmt = clamp((1.0 - depth) * 0.30 + bgField * 0.10, 0.0, 0.45)
                * (1.0 - saturate(coreGlow));
    color = mix(color, hazeColor * (1.0 + halo * 0.6), hazeAmt);

    color = acesToneMap(color);

    // Vibrance: mids lift saturation of mid-tones without clipping skin of
    // the highlights (post-ACES, bounded).
    let lumaPost = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
    color = clamp(mix(vec3<f32>(lumaPost), color, 1.0 + mids * 0.22), vec3<f32>(0.0), vec3<f32>(1.0));

    // Temporal persistence (non-filtering load of rgba32float history)
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    color = mix(color, prev * 0.95, 0.04 + feedback * 0.06 + bass * 0.02);

    // Depth controls line thickness perspective
    let curveDensity = exp(-minDist / (glowWidth * (1.0 + depth)));
    let alpha = clamp(curveDensity * turnIntensity * (0.3 + depth * 0.7)
      + clickEnergy * halo * 0.18, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(curveDensity * depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
