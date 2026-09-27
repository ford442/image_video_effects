// ----------------------------------------------------------------
// Stellar Plasma-Ouroboros
// Category: generative
// Features: raymarched, OkLab-color-mixing, blackbody-palette,
//           Fresnel-rim-lighting, audio-reactive, depth-aware,
//           upgraded-rgba, mouse-driven
// Upgraded: 2026-06-28 — Visualist Batch (OkLab + blackbody + Fresnel)
// Upgraded: 2026-09-27
// Ideas: peristaltic plasma bolus hinging the scale plates outward;
//        seam light leaking through the hex gaps, gated by the bolus phase
// A packing: display RGBA (ACES)
// ----------------------------------------------------------------

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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Scale Density, y=Plasma Intensity, z=Anomaly Gravity, w=Time Warp
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

fn sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let k = vec3<f32>(-0.8660254, 0.5, 0.57735);
    var p_abs = abs(p);
    p_abs.x -= 2.0 * min(dot(k.xy, p_abs.xy), 0.0) * k.x;
    p_abs.y -= 2.0 * min(dot(k.xy, p_abs.xy), 0.0) * k.y;
    let d1 = length(p_abs.xy - vec2<f32>(clamp(p_abs.x, -k.z * h.x, k.z * h.x), h.x)) * sign(p_abs.y - h.x);
    let d2 = p_abs.z - h.y;
    return min(max(d1, d2), 0.0) + length(max(vec2<f32>(d1, d2), vec2<f32>(0.0)));
}

fn sdCylinder(p: vec3<f32>, c: vec2<f32>) -> f32 {
    return length(p.xz) - c.x;
}

fn pModPolar(p: vec2<f32>, repetitions: f32) -> vec2<f32> {
    let angle = 6.2831853 / repetitions;
    let a = atan2(p.y, p.x) + angle / 2.0;
    let r = length(p);
    let c = floor(a / angle);
    let a_mod = (a % angle + angle) % angle - angle / 2.0;
    return vec2<f32>(cos(a_mod) * r, sin(a_mod) * r);
}

// ─── OkLab color utilities ───
fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(2.2));
}
fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(1.0 / 2.2));
}
fn linear_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let lms = mat3x3<f32>(
        0.8189330101, 0.3618667424, -0.1288597137,
        0.0329845436, 0.9293118715,  0.0361456387,
        0.0482003018, 0.2643662691,  0.6338517070
    ) * c;
    let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0 / 3.0));
    return mat3x3<f32>(
        0.2104542553,  0.7936177850, -0.0040720468,
        1.9779984951, -2.4285922050,  0.4505937099,
        0.0259040371,  0.7827717662, -0.8086757660
    ) * lms_;
}
fn oklab_to_linear(c: vec3<f32>) -> vec3<f32> {
    let lms_ = mat3x3<f32>(
        0.2104542553,  0.7936177850, -0.0040720468,
        1.9779984951, -2.4285922050,  0.4505937099,
        0.0259040371,  0.7827717662, -0.8086757660
    ) * c;
    let lms = lms_ * lms_ * lms_;
    return mat3x3<f32>(
        1.2270138511, -0.5577992887,  0.2812561490,
       -0.0405801784,  1.1122568696, -0.0716766787,
       -0.0763812845, -0.4214819784,  1.5861632204
    ) * lms;
}
fn oklab_mix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    let a_ok = linear_to_oklab(srgb_to_linear(a));
    let b_ok = linear_to_oklab(srgb_to_linear(b));
    return linear_to_srgb(oklab_to_linear(mix(a_ok, b_ok, t)));
}

// ─── Blackbody palette ───
fn blackbody(t: f32) -> vec3<f32> {
    let temp = clamp(t, 0.0, 1.0);
    let r = 1.0;
    let g = mix(0.3, 1.0, smoothstep(0.0, 0.5, temp));
    let b = mix(0.0, 0.8, smoothstep(0.3, 1.0, temp));
    return vec3<f32>(r, g, b) * (0.5 + temp * 0.5);
}

// ─── Fresnel rim lighting ───
fn fresnel_rim(n: vec3<f32>, viewDir: vec3<f32>, power: f32) -> f32 {
    return pow(1.0 - max(dot(n, viewDir), 0.0), power);
}

// IDEA 1: peristaltic bolus envelope. Soft pulse, period 16 z-units, travelling +z.
fn bolusAt(z: f32, time: f32) -> f32 {
    let w = fract(z * 0.0625 - time) - 0.5;
    return exp(-w * w * 30.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord * 2.0 - res) / res.y;

    let scaleDensity = u.zoom_params.x;
    let plasmaIntensity = u.zoom_params.y;
    let anomalyGravity = u.zoom_params.z;
    let timeWarp = u.zoom_params.w;

    let time = u.config.x * timeWarp * 0.2;
    let audioReactivity = plasmaBuffer[0].x; // bass
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var ro = vec3<f32>(0.0, 0.0, -10.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Y-flipped: screen-top (zoom_config.z=0) = +Y/up
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = (u.zoom_config.z * 2.0 - 1.0);
    let mousePos = vec3<f32>(mouseX * 8.0, mouseY * 8.0, 0.0);

    let mouseDist = distance(ro + rd * 10.0, mousePos);
    if (mouseDist > 0.1) {
        rd = normalize(rd + (mousePos - (ro + rd * 10.0)) * (anomalyGravity * 0.1 / mouseDist));
    }

    var col = vec3<f32>(0.0);
    var t = 0.0;
    var d = 0.0;
    var glow = vec3<f32>(0.0);
    var hitPlasma = false;
    var surfaceNormal = vec3<f32>(0.0);
    var hitSurface = false;
    var hitT = 0.0;
    var seamCov = 0.0;

    for (var i = 0; i < 100; i++) {
        var p = ro + rd * t;

        let pathDistort = vec3<f32>(sin(p.z * 0.2 + time) * 3.0, cos(p.z * 0.2 + time * 0.8) * 3.0, 0.0);
        p -= pathDistort;

        let rot1 = rotate2D(p.z * 0.1 + time * 0.5);
        let temp_p_xy = rot1 * p.xy;
        p.x = temp_p_xy.x;
        p.y = temp_p_xy.y;

        let cylD = sdCylinder(p, vec2<f32>(2.0, 0.0));

        var q = p;
        q.z = fract(q.z * (scaleDensity / 10.0)) - 0.5;
        let polar_xy = pModPolar(q.xy, scaleDensity);
        q.x = polar_xy.x;
        q.y = polar_xy.y;

        q.x -= 2.0;

        // IDEA 1: as the bolus passes, each plate hinges about its inner edge
        // (z tilt proportional to radial offset) and swings outward.
        let bolus = bolusAt(p.z, time);
        let hinge = bolus * (0.35 + 0.25 * mids);
        q.z += (q.x + 0.5) * hinge;
        q.x -= hinge * 0.35;

        let hexD = sdHexPrism(q, vec2<f32>(0.5, 0.1));

        d = max(cylD, -hexD);

        let innerPlasma = sdCylinder(p, vec2<f32>(1.8, 0.0));

        if (d < 0.01) {
            let n_fbm = fbm(p * 2.0 + vec3<f32>(0.0, 0.0, time * 2.0));
            // OkLab mix between cool and hot tones
            let cool = vec3<f32>(0.1, 0.2, 0.3);
            let hot = blackbody(0.6 + n_fbm * 0.4);
            col = oklab_mix(cool, hot, n_fbm);
            let refl = reflect(rd, normalize(p));
            col += textureSampleLevel(readTexture, u_sampler, refl.xy, 0.0).rgb * 0.5;

            // IDEA 2: seam light. Plasma leaks through the hex gaps: |hexD| contour,
            // ember between boluses, hot while the bolus passes.
            let seamGate = exp(-abs(hexD) * 14.0);
            let seamAmp = 0.25 + 1.6 * bolus;
            let seamCol = blackbody(0.75 + 0.25 * bolus) * (0.6 + 0.8 * n_fbm);
            col += seamCol * seamGate * seamAmp * (plasmaIntensity * 0.4) * (1.0 + treble * 0.5);
            seamCov = seamGate * clamp(seamAmp, 0.0, 1.0);
            hitSurface = true;
            hitT = t;

            // Approximate normal for Fresnel
            surfaceNormal = normalize(p);
            break;
        }

        if (innerPlasma < 0.1) {
            hitPlasma = true;
            let n_plasma = fbm(p * 5.0 - vec3<f32>(0.0, 0.0, time * 5.0 + audioReactivity * 10.0));
            let plasmaBB = blackbody(0.4 + n_plasma * 0.6);
            glow += plasmaBB * (0.05 * plasmaIntensity) / (abs(innerPlasma - n_plasma) + 0.05);
        }

        t += d * 0.5;
        if (t > 50.0) { break; }
    }

    if (!hitPlasma && d >= 0.01) {
        let stars = pow(fbm(rd * 100.0), 10.0);
        col = vec3<f32>(stars);
    }

    col += glow;

    // Fresnel rim on the ouroboros structure
    if (length(surfaceNormal) > 0.01) {
        let viewDir = -rd;
        let rim = fresnel_rim(surfaceNormal, viewDir, 2.0 + audioReactivity * 2.0);
        let rimCol = blackbody(0.5 + audioReactivity * 0.5) * rim * 0.4;
        col += rimCol;
    }

    // ACES display (exposure 0.8 keeps the old clamp look close while HDR glow rolls off)
    let hdrLuma = dot(max(glow, vec3<f32>(0.0)), vec3<f32>(0.299, 0.587, 0.114));
    let glowA = 1.0 - exp(-1.5 * hdrLuma);
    let cover = max(max(select(0.0, 1.0, hitSurface), glowA), seamCov);
    let alpha = mix(0.2, 1.0, clamp(cover, 0.0, 1.0));
    col = acesToneMap(max(col, vec3<f32>(0.0)) * 0.8);

    let outCol = vec4<f32>(col, alpha);
    textureStore(writeTexture, vec2<i32>(id.xy), outCol);
    textureStore(dataTextureA, vec2<i32>(id.xy), outCol);
    // Truthful depth from the march distance (near = 1, miss = 0)
    let depth = select(0.0, clamp(1.0 - hitT / 50.0, 0.0, 1.0), hitSurface);
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
