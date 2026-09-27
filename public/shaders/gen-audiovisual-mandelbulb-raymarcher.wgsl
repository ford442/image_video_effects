// ═══════════════════════════════════════════════════════════════════════════════
//  Audiovisual Mandelbulb Raymarcher
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: escape-time strata (smooth escape-count onion shells, Escape Radius = real bailout); DE soft shadow + 5-tap AO; trap-coloured silhouette halo from closest approach
//  A packing: A.rgb = linear HDR scene colour after trail blend (pre-tint, pre-ACES), A.a = semantic alpha; C read as the same HDR
//  Fast power morphing, orbit-trap spectra, greebled micro-detail; cursor orbits
//  the camera, held throttles spin + dollies in, clicks fire shock rings.
//  Note: extraBuffer[133..138] spring is inert (slots are zeroed every frame).
// ═══════════════════════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,  // x=Iterations, y=Escape Radius, z=Glow, w=Video Blend
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── state slots (safe zone only) ───────────────────────────────────────────
const SPRING_X: i32 = 133;
const SPRING_Y: i32 = 134;
const SPRING_VX: i32 = 135;
const SPRING_VY: i32 = 136;
const SPRING_T: i32 = 137;
const SPRING_INIT: i32 = 138;

var<private> g_power: f32;
var<private> g_iters: i32;
var<private> g_shock: f32;
var<private> g_time: f32;
var<private> g_trap: f32;
var<private> g_bailout: f32;  // Idea 1: Escape Radius slider -> true bailout radius
var<private> g_esc: f32;      // Idea 1: smooth escape count from the last DE call

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

// ─── OkLab color utilities ───
fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}
fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
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

// ─── Psychedelic spectral palette — hue wheel with audio-driven phase split ───
fn psychePalette(t: f32, drive: f32) -> vec3<f32> {
    let phase = vec3<f32>(0.0, 2.094 + drive * 0.9, 4.189 - drive * 0.9);
    return 0.5 + 0.5 * cos(TAU * t + phase);
}

fn blackbody(t: f32) -> vec3<f32> {
    let temp = clamp(t, 0.0, 1.0);
    let g = mix(0.3, 1.0, smoothstep(0.0, 0.5, temp));
    let b = mix(0.0, 0.8, smoothstep(0.3, 1.0, temp));
    return vec3<f32>(1.0, g, b) * (0.5 + temp * 0.5);
}

fn fresnel_rim(n: vec3<f32>, viewDir: vec3<f32>, power: f32) -> f32 {
    return pow(1.0 - max(dot(n, viewDir), 0.0), power);
}

// Mandelbulb distance estimator with orbit-trap accumulation (geometric detail)
fn mandelbulbDE(p: vec3<f32>) -> f32 {
    var z = p;
    var dr = 1.0;
    var r = 0.0;
    var trap = 1e9;
    var esc = f32(g_iters);
    for (var i: i32 = 0; i < g_iters; i = i + 1) {
        r = length(z);
        if (r > g_bailout) {
            // Idea 1: smooth (continuous) escape-time count, nu in (i-1, i]
            let lr = log(max(r, 1.0001)) / log(g_bailout);
            esc = clamp(f32(i) - log(max(lr, 1e-6)) / log(max(g_power, 1.01)), 0.0, f32(g_iters));
            break;
        }
        trap = min(trap, length(z - vec3<f32>(0.0, 0.35, 0.0)));
        let theta = acos(clamp(z.y / max(r, 1e-6), -1.0, 1.0));
        let phi = atan2(z.z, z.x);
        let zr = pow(r, g_power);
        dr = pow(r, g_power - 1.0) * g_power * dr + 1.0;
        let st = sin(theta * g_power);
        let ct = cos(theta * g_power);
        let sp = sin(phi * g_power);
        let cp = cos(phi * g_power);
        z = zr * vec3<f32>(st * cp, ct, st * sp) + p;
    }
    g_trap = trap;
    g_esc = esc;
    var d = 0.5 * log(max(r, 1e-6)) * r / max(dr, 1e-6);
    // Greeble shell: high-frequency ridging carved into the surface (geometric detail)
    let ridge = sin(p.x * 24.0 + g_time * 3.0) * sin(p.y * 24.0 - g_time * 2.6) * sin(p.z * 24.0 + g_time * 3.4);
    d -= ridge * 0.0035 * (1.0 + g_shock * 2.0);
    return d;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.0012, 0.0);
    return normalize(vec3<f32>(
        mandelbulbDE(p + e.xyy) - mandelbulbDE(p - e.xyy),
        mandelbulbDE(p + e.yxy) - mandelbulbDE(p - e.yxy),
        mandelbulbDE(p + e.yyx) - mandelbulbDE(p - e.yyx)
    ));
}

// Idea 2: DE soft shadow — penumbra from the closest approach of the shadow ray
fn softShadow(ro: vec3<f32>, rd: vec3<f32>, k: f32) -> f32 {
    var res = 1.0;
    var t = 0.02;
    for (var i: i32 = 0; i < 20; i = i + 1) {
        let h = mandelbulbDE(ro + rd * t);
        res = min(res, k * h / t);
        t += clamp(h, 0.01, 0.18);
        if (res < 0.003 || t > 2.5) { break; }
    }
    return clamp(res, 0.0, 1.0);
}

// Idea 2: 5-tap ambient occlusion along the normal
fn calcAO(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        let h = 0.01 + 0.11 * f32(i) / 4.0;
        let d = mandelbulbDE(p + n * h);
        occ += max(h - d, 0.0) * sca;
        sca *= 0.9;
    }
    return clamp(1.0 - 2.0 * occ, 0.0, 1.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

    let coord = vec2<i32>(id.xy);
    let uv01 = vec2<f32>(id.xy) / res;
    let uv = (uv01 - 0.5) * vec2<f32>(res.x / max(res.y, 1.0), 1.0);
    let aspect = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
    let time = u.config.x;
    g_time = time;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;

    // ── spring cursor (extraBuffer[133..138] only) ─────────────────────────
    var smoothMouse = mouse;
    let hasSpring = arrayLength(&extraBuffer) > 138u;
    if (hasSpring && extraBuffer[SPRING_INIT] > 0.5) {
        smoothMouse = vec2<f32>(extraBuffer[SPRING_X], extraBuffer[SPRING_Y]);
    }
    if (hasSpring && id.x == 0u && id.y == 0u) {
        var springPos = smoothMouse;
        var springVel = vec2<f32>(extraBuffer[SPRING_VX], extraBuffer[SPRING_VY]);
        if (extraBuffer[SPRING_INIT] <= 0.5) {
            springPos = mouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[SPRING_T], 0.001, 0.05);
            let omega = 11.0;
            let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[SPRING_X] = springPos.x;
        extraBuffer[SPRING_Y] = springPos.y;
        extraBuffer[SPRING_VX] = springVel.x;
        extraBuffer[SPRING_VY] = springVel.y;
        extraBuffer[SPRING_T] = time;
        extraBuffer[SPRING_INIT] = 1.0;
        smoothMouse = springPos;
    }

    // ── click shock rings: capped, deform the bulb and flash the palette ───
    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 1.4) {
            let ring = abs(length((uv01 - rp.xy) * aspect) - age * 0.85);
            shock = max(shock, exp(-ring * 26.0) * (1.0 - age / 1.4));
        }
    }
    shock = min(shock, 1.0);
    g_shock = shock;

    // ── slider mapping ─────────────────────────────────────────────────────
    g_iters = i32(mix(5.0, 14.0, clamp(u.zoom_params.x, 0.0, 1.0)));
    let escapeRadius = clamp(u.zoom_params.y, 0.0, 1.0) * 2.0 + 6.0;
    // Idea 1: the same slider is the real DE bailout; exactly 2.4 (HEAD) at the saved default 0.5.
    // The set boundary barely moves with it (numpy: 99.97% same hit mask) — the escape strata slide.
    g_bailout = 2.4 * exp2((clamp(u.zoom_params.y, 0.0, 1.0) - 0.5) * 1.4);
    let glowStrength = u.zoom_params.z * 2.0;
    let textureBlend = clamp(u.zoom_params.w, 0.0, 1.0);

    // Fast motion: spun-up orbit, bass kicks the spin, held presses the throttle
    let spinRate = 0.55 + bass * 1.6 + select(0.0, 0.9, held);
    let mouseRotY = (smoothMouse.x - 0.5) * PI * 2.0 + time * spinRate;
    let mouseRotX = (smoothMouse.y - 0.5) * 1.5708 + sin(time * 0.9) * 0.25;

    // Held pulls the camera into the fractal; shock rings punch it back out
    let dolly = 2.5 - select(0.0, 0.7, held) + shock * 0.9;
    var ro = vec3<f32>(0.0, 0.0, -dolly);
    var rd = normalize(vec3<f32>(uv, 1.25));

    let cam = rotY(mouseRotY) * rotX(mouseRotX);
    ro = cam * ro;
    rd = cam * rd;

    // Fast power morph — audio-mutated exponent sweeps several times per second
    g_power = 8.0 + bass * 5.0 + sin(time * 2.4) * 2.6 + mids * 2.0 + shock * 3.0;

    var t = 0.0;
    var hit = false;
    var surfTrap = 0.0;
    var glowAccum = 0.0;
    var surfEsc = 0.0;
    // Idea 3: closest approach of the ray to the bulb, with the trap / radius seen there
    var minD = 1e9;
    var minTrap = 0.0;
    var minR = 0.0;
    for (var i: i32 = 0; i < 90; i = i + 1) {
        let p = ro + rd * t;
        let d = mandelbulbDE(p);
        glowAccum += exp(-abs(d) * 22.0) * 0.012;
        if (d < 0.0009) {
            hit = true;
            surfTrap = g_trap;
            surfEsc = g_esc;
            break;
        }
        if (d < minD) {
            minD = d;
            minTrap = min(g_trap, 4.0);
            minR = length(p);
        }
        t += d * 0.92;
        if (t > escapeRadius) { break; }
    }

    var col = vec3<f32>(0.0);
    var depth = 0.0;
    var hitFresnel = 0.0;

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let viewDir = -rd;

        // Psychedelic orbit-trap spectrum, hue racing with treble
        let orbit = fract(length(p) * 0.7 + surfTrap * 1.4 + time * (0.35 + treble * 0.9));
        let orbitCol = psychePalette(orbit, mids * 1.4 + shock);
        let bb = blackbody(orbit * 0.8 + bass * 0.3);
        let fractalCol = oklab_mix(orbitCol, bb, 0.32 + bass * 0.2);

        let texUV = vec2<f32>(atan2(n.z, n.x) / TAU + 0.5, n.y * 0.5 + 0.5);
        let videoCol = textureSampleLevel(readTexture, u_sampler, texUV, 0.0).rgb;
        col = mix(fractalCol, videoCol, textureBlend);

        let lig = normalize(vec3<f32>(0.8, 0.7, -0.6));
        let dif = max(dot(n, lig), 0.0);
        let hal = normalize(lig + viewDir);
        let spec = pow(max(dot(n, hal), 0.0), 48.0);
        // Idea 2: lobes shadow each other, crevices between greebled lobes occlude
        let pn = p + n * 0.003;
        // Shadow keeps a 0.4 sky-fill floor: numpy shows ~60% of lit-facing points are occluded by
        // neighbouring lobes, so a hard shadow would drown the key light.
        let sha = 0.4 + 0.6 * select(0.0, softShadow(pn, lig, 8.0), dif > 0.0);
        let ao = calcAO(pn, n);
        col = col * (0.28 * (0.4 + 0.6 * ao) + dif * 0.72 * sha) + vec3<f32>(1.0, 0.95, 0.9) * spec * sha * (0.35 + treble * 0.6);

        // Micro-detail bands read off the orbit trap — reads as engraved geometry
        let bands = 0.5 + 0.5 * sin(surfTrap * 90.0 - time * 6.0);
        col *= 0.78 + bands * 0.44;

        // Idea 1: escape-time strata — onion shells of the escape count, each shell ramps dark->light
        // toward its outer edge, with a thin hue-stepped contour at every integer escape crossing.
        if (surfEsc < f32(g_iters) - 0.001) {
            let sf = fract(surfEsc);
            let shell = floor(surfEsc);
            col *= 0.74 + 0.26 * smoothstep(0.0, 1.0, sf);
            let edge = abs(fract(surfEsc + 0.5) - 0.5);
            let contour = 1.0 - smoothstep(0.0, 0.06, edge);
            col += psychePalette(orbit + shell * 0.083, mids) * contour * 0.55;
        }

        hitFresnel = fresnel_rim(n, viewDir, 2.0 + bass * 2.0);
        col += psychePalette(orbit + 0.4, treble) * hitFresnel * 0.75 * (1.0 + bass);

        depth = clamp(1.0 - t / escapeRadius, 0.0, 1.0);
    } else {
        let bgUV = uv * 0.5 + vec2<f32>(0.5);
        col = textureSampleLevel(readTexture, u_sampler, bgUV, 0.0).rgb * 0.22;
        let glow = glowStrength * 0.02 / (t * t + 0.1);
        col += psychePalette(time * 0.12 + length(uv) * 0.6, mids) * glow * (1.0 + bass);

        // Idea 3: trap-coloured silhouette halo — grazing rays glow in the hue the surface
        // would have at their closest approach (same orbit-trap formula as the hit branch)
        let haloOrbit = fract(minR * 0.7 + minTrap * 1.4 + time * (0.35 + treble * 0.9));
        let halo = exp(-max(minD, 0.0) * 30.0) * glowStrength * 0.9;
        col += psychePalette(haloOrbit, mids * 1.4 + shock) * halo * (1.0 + bass * 0.5);
        depth = 0.0;
    }

    // Volumetric spectral haze gathered along the march
    col += psychePalette(time * 0.2 + glowAccum, treble * 1.5) * min(glowAccum, 2.0) * (0.25 + glowStrength * 0.2);

    // Shock ring flare
    col += psychePalette(time * 0.9, 1.0) * shock * 1.3;

    // Treble sparkle
    let sparkle = hash(vec2<f32>(f32(id.x), f32(id.y)) + time);
    col += vec3<f32>(1.0, 0.9, 0.7) * treble * step(0.9965 - treble * 0.002, sparkle);

    // Cursor bloom — the pointer lights the volume even when not pressed
    let cursorDist = length((uv01 - smoothMouse) * aspect);
    let cursorGlow = exp(-cursorDist * 7.0) * (0.18 + select(0.0, 0.45, held));
    col += psychePalette(time * 0.5 + cursorDist, bass) * cursorGlow;

    // ── temporal feedback — exact load, no filtering ───────────────────────
    let prev = textureLoad(dataTextureC, coord, 0);
    let trailAmount = 0.06 + bass * 0.05;
    col = mix(col, prev.rgb * 0.93, trailAmount);
    // A packing (fix: HEAD stored post-ACES colour here and re-ACES'd it next frame):
    // store the HDR scene colour so C decodes as the same space it is blended into.
    let hdrScene = max(col, vec3<f32>(0.0));

    let caStr = 0.004 * (1.0 + bass) + shock * 0.01;
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    col = acesToneMap(col * (1.3 + mids * 0.25));

    // Semantic alpha: surface presence + spectral energy, transparent in the void
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(
        select(0.0, 0.45 + hitFresnel * 0.35, hit)
        + luma * 0.45 + min(glowAccum, 1.0) * 0.25 + shock * 0.25,
        0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(hdrScene, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
