// ═══════════════════════════════════════════════════════════════════
//  Abyssal Plasma Void-Medusa
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: plasma node lanterns at the tentacle roots (SDF bulbs + volumetric halo); bell shell-thickness translucency (Beer-Lambert lantern light through the outer/inner shell gap); void-current filaments (iso-lines of the map() warp noise, dragged by the mouse)
//  A packing: HDR linear RGB (pre-ACES, with short C light-wake) + semantic alpha (body 1, glow coverage elsewhere)
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = bioluminescence, .y = fluid distortion, .z = tentacle length, .w = plasma hue
  ripples: array<vec4<f32>, 50>,
};

// --- SHADER START ---

const MAX_STEPS = 128;
const MAX_DIST = 100.0;
const SURF_DIST = 0.001;
const STEP_SCALE = 0.8; // domain warp is not 1-Lipschitz
const LANTERN_Y = 0.8;  // just below the tentacle roots (capsules start at y = 1)
const LANTERN_R = 0.17;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn smoothNoise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let n000 = dot(hash33(i + vec3<f32>(0.0, 0.0, 0.0)) - 0.5, f - vec3<f32>(0.0, 0.0, 0.0));
    let n100 = dot(hash33(i + vec3<f32>(1.0, 0.0, 0.0)) - 0.5, f - vec3<f32>(1.0, 0.0, 0.0));
    let n010 = dot(hash33(i + vec3<f32>(0.0, 1.0, 0.0)) - 0.5, f - vec3<f32>(0.0, 1.0, 0.0));
    let n110 = dot(hash33(i + vec3<f32>(1.0, 1.0, 0.0)) - 0.5, f - vec3<f32>(1.0, 1.0, 0.0));
    let n001 = dot(hash33(i + vec3<f32>(0.0, 0.0, 1.0)) - 0.5, f - vec3<f32>(0.0, 0.0, 1.0));
    let n101 = dot(hash33(i + vec3<f32>(1.0, 0.0, 1.0)) - 0.5, f - vec3<f32>(1.0, 0.0, 1.0));
    let n011 = dot(hash33(i + vec3<f32>(0.0, 1.0, 1.0)) - 0.5, f - vec3<f32>(0.0, 1.0, 1.0));
    let n111 = dot(hash33(i + vec3<f32>(1.0, 1.0, 1.0)) - 0.5, f - vec3<f32>(1.0, 1.0, 1.0));

    let nx00 = mix(n000, n100, u.x);
    let nx10 = mix(n010, n110, u.x);
    let nx01 = mix(n001, n101, u.x);
    let nx11 = mix(n011, n111, u.x);

    let nxy0 = mix(nx00, nx10, u.y);
    let nxy1 = mix(nx01, nx11, u.y);

    return mix(nxy0, nxy1, u.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Stateless bell breath (HEAD read a per-frame-zeroed extraBuffer[133] phase, so the bell never pulsed).
fn bellRadius() -> f32 {
    let time = u.config.x;
    let speed = 1.0 + u.zoom_params.x * 2.0;
    let bass = plasmaBuffer[0].x;
    return 1.5 + sin(time * speed) * 0.1 * u.zoom_params.x + bass * 0.06;
}

// Mouse drag of the body (verbatim HEAD rule, shared by map() and the void currents).
fn mouseDrag(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;
    if (u.zoom_config.w > 0.0) {
        let mousePos = u.zoom_config.yz * 2.0 - 1.0;
        let dragDist = length(p.xy - mousePos * 5.0);
        let dragForce = exp(-dragDist * 0.5);
        p = vec3<f32>(p.x + mousePos.x * dragForce, p.y - mousePos.y * dragForce, p.z);
    }
    return p;
}

// Raw void-current noise (the domain-warp field of map()).
fn voidCurrent(p: vec3<f32>) -> vec3<f32> {
    let time = u.config.x;
    let p2 = p * 2.0;
    return vec3<f32>(
        smoothNoise(p2 + vec3<f32>(time * 0.5, 0.0, 0.0)),
        smoothNoise(p2 + vec3<f32>(0.0, time * 0.5, 0.0)),
        smoothNoise(p2 + vec3<f32>(0.0, 0.0, time * 0.5))
    );
}

fn warpPoint(p_in: vec3<f32>) -> vec3<f32> {
    // Domain distortion
    let p = p_in + voidCurrent(p_in) * u.zoom_params.y * 0.5;
    return mouseDrag(p);
}

// Idea 1: plasma node lanterns — one core per tentacle, riding the tentacle's own sway at its root.
fn lanternPos(fi: f32) -> vec3<f32> {
    let time = u.config.x;
    let a = fi * 1.256637 + time * 0.5;
    let ph = LANTERN_Y * 2.0 - time * 2.0 + fi;
    return vec3<f32>(cos(a) * 0.8 - sin(ph) * 0.3, LANTERN_Y, sin(a) * 0.8 - cos(ph) * 0.3);
}

// Stateless flicker, visible with audio = 0; bass brightens.
fn lanternPower(fi: f32) -> f32 {
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let flick = 0.75 + 0.25 * sin(time * 1.7 + fi * 2.3) * sin(time * 0.63 + fi * 4.1);
    return flick * (0.3 + 1.4 * u.zoom_params.x) * (1.0 + bass * 1.5);
}

// .x = scene distance, .y = bell distance, .z = nearest-lantern distance (all in warped space)
fn medusa(p: vec3<f32>) -> vec3<f32> {
    let time = u.config.x;
    let tentacle_length = u.zoom_params.z;

    // Medusa Bell (inverted hemisphere) - modulated by breath
    var bellP = p;
    bellP.y -= 1.0;
    let bellRad = bellRadius();

    var dBell = length(bellP) - bellRad;
    let bellInner = length(bellP + vec3<f32>(0.0, 0.5, 0.0)) - (bellRad - 0.2);
    dBell = max(dBell, -bellInner);
    dBell = max(dBell, -bellP.y); // cut off bottom

    // Tentacles
    var dTentacles = 100.0;
    var dLantern = 100.0;
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        var tP = p;

        let a = fi * 1.256637 + time * 0.5; // 2PI/5 = 1.256637
        let r = 0.8;
        tP.x -= cos(a) * r;
        tP.z -= sin(a) * r;

        // Sine wave modulation along y
        tP.x += sin(tP.y * 2.0 - time * 2.0 + fi) * 0.3;
        tP.z += cos(tP.y * 2.0 - time * 2.0 + fi) * 0.3;

        // Capsule; taper along the tentacle's own length (HEAD tapered by the clamped, ~0 residual y)
        let yAlong = tP.y;
        tP.y -= clamp(tP.y, -tentacle_length * 3.0, 1.0);
        let along = clamp((1.0 - yAlong) / (1.0 + tentacle_length * 3.0), 0.0, 1.0);
        let dTen = length(tP) - 0.1 * (1.0 - 0.7 * along);

        dTentacles = smin(dTentacles, dTen, 0.3);

        // Idea 1: lantern bulb fused into the tentacle root
        dLantern = min(dLantern, length(p - lanternPos(fi)));
    }
    dTentacles = smin(dTentacles, dLantern - LANTERN_R, 0.1);

    return vec3<f32>(smin(dBell, dTentacles, 0.5), dBell, dLantern);
}

fn map(p: vec3<f32>) -> f32 {
    return medusa(warpPoint(p)).x;
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p);
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy),
        map(p - e.yxy),
        map(p - e.yyx)
    );
    return normalize(n);
}

// Sum of lantern light arriving at q (inverse-square with a soft core).
fn lanternLight(q: vec3<f32>) -> f32 {
    var s = 0.0;
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        let d = length(q - lanternPos(fi));
        s += lanternPower(fi) / (1.0 + d * d * 1.5);
    }
    return s;
}

fn isoLine(v: f32, w: f32) -> f32 {
    let d = abs(fract(v + 0.5) - 0.5);
    return 1.0 - smoothstep(0.0, w, d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }
    let coord = vec2<i32>(id.xy);

    let uv = (vec2<f32>(id.xy) * 2.0 - resolution) / min(resolution.x, resolution.y);
    let time = u.config.x;

    let biolum = u.zoom_params.x;
    let fluid = u.zoom_params.y;
    let plasmaHue = u.zoom_params.w;

    // Audio reactivity (HEAD read dataTextureC.r as "audio")
    let audio = plasmaBuffer[0].xyz;
    let audio_glow = (audio.x * 0.6 + audio.y * 0.3 + audio.z * 0.1) * 0.5;

    // Orbit camera: same default framing as HEAD (0,-1,5); mouse yaw/pitch on a clamped sphere
    // (HEAD's second .xzy swizzle swapped y/z, jumping the camera overhead and NaN-ing at ro.xz = 0).
    var ro = vec3<f32>(0.0, -1.0, 5.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let mouse = (u.zoom_config.yz * 2.0 - vec2<f32>(1.0)) * vec2<f32>(1.0, -1.0);
    if (u.zoom_config.w > 0.0) {
        let camR = length(ro);
        let az = -mouse.x * 3.14159;
        let el = clamp(atan2(-1.0, 5.0) - mouse.y * 1.5, -1.35, 1.35);
        ro = camR * vec3<f32>(cos(el) * sin(az), sin(el), cos(el) * cos(az));
    }

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    var p = ro;
    var dO = 0.0;
    var dS = 1.0;
    var vol = 0.0;
    var lanternHalo = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        let q = warpPoint(p);
        let m = medusa(q);
        dS = m.x;
        if (dS < SURF_DIST) {
            break;
        }

        // Volumetric scattering accumulation
        vol += 0.05 / (1.0 + abs(dS) * 10.0);

        let stepLen = dS * STEP_SCALE;

        // Idea 1: lantern halo, integrated along the ray (step-length weighted, soft core)
        if (m.z < 2.5) {
            for (var k = 0; k < 5; k++) {
                let fk = f32(k);
                let dl = length(q - lanternPos(fk));
                lanternHalo += stepLen * lanternPower(fk) * 0.012 / (dl * dl + 0.03);
            }
        }

        dO += stepLen;
        if (dO > MAX_DIST) {
            break;
        }
    }
    let hit = dS < 0.01 && dO < MAX_DIST;

    var col = vec3<f32>(0.0, 0.05, 0.1); // Deep oceanic background

    let hueShiftCol = vec3<f32>(
        0.5 + 0.5 * cos(plasmaHue * 6.28 + 0.0),
        0.5 + 0.5 * cos(plasmaHue * 6.28 + 2.1),
        0.5 + 0.5 * cos(plasmaHue * 6.28 + 4.2)
    );
    // Lantern plasma: the complementary hue of the bell, pushed toward white-hot
    let lanternCol = mix(vec3<f32>(
        0.5 + 0.5 * cos(plasmaHue * 6.28 + 3.14),
        0.5 + 0.5 * cos(plasmaHue * 6.28 + 5.24),
        0.5 + 0.5 * cos(plasmaHue * 6.28 + 7.34)
    ), vec3<f32>(1.0, 0.9, 0.75), 0.35);

    var depth = 0.0;
    var alpha = 0.0;

    if (hit) {
        let q = warpPoint(p);
        let m = medusa(q);
        let n = getNormal(p);
        let lightPos = vec3<f32>(2.0, 4.0, 3.0);
        let l = normalize(lightPos - p);

        let dif = clamp(dot(n, l), 0.0, 1.0);
        let amb = 0.1;

        // Subsurface / bioluminescence
        let fresnel = pow(clamp(1.0 - max(dot(n, -rd), 0.0), 0.0, 1.0), 3.0);

        var baseCol = vec3<f32>(0.1, 0.3, 0.6); // Base medusa color
        baseCol = mix(baseCol, hueShiftCol, plasmaHue);

        col = baseCol * (dif + amb);

        // Add bioluminescent glow and audio reaction
        col += hueShiftCol * fresnel * biolum * (1.0 + audio_glow * 2.0);

        let lan = lanternLight(q);

        // Idea 2: bell shell-thickness translucency. Radial gap between the outer and inner shells at the
        // hit: ~0.3 at the thin rim, ~0.7 at the thick crown. Lantern light is filtered Beer-Lambert style,
        // the tissue passing its own hue, so the rim glows lantern-hot and the crown deepens to bell colour.
        let bellMask = 1.0 - smoothstep(0.0, 0.12, m.y - m.x);
        var bellP = q;
        bellP.y -= 1.0;
        let bellRad = bellRadius();
        let gapOuter = max(length(bellP + vec3<f32>(0.0, 0.5, 0.0)) - (bellRad - 0.2), 0.0);
        let gapInner = max(bellRad - length(bellP), 0.0);
        let thick = gapOuter + gapInner;
        let absorb = (vec3<f32>(1.0) - hueShiftCol) * 3.0 + vec3<f32>(1.2);
        let transmit = exp(-absorb * thick);
        col += lanternCol * transmit * lan * bellMask * 1.6;

        // Idea 1: lantern light on tentacles, and the white-hot bulb cores themselves
        col += lanternCol * lan * (1.0 - bellMask) * (0.25 + 0.35 * max(dot(n, -rd), 0.0));
        let core = 1.0 - smoothstep(LANTERN_R * 0.7, LANTERN_R * 1.4, m.z);
        col += mix(lanternCol, vec3<f32>(1.0), 0.5) * core * (0.3 + 1.4 * biolum) * 2.5;

        // Falloff into void (hits only; HEAD also zeroed every miss because dO > MAX_DIST)
        col *= exp(-dO * 0.05);

        depth = clamp(1.0 - dO / 12.0, 0.05, 1.0);
        alpha = 1.0;
    } else {
        // Idea 3: void-current filaments. Iso-lines of the very noise field that warps map(), sampled on
        // the ray's closest approach to the medusa and dragged by the same mouse rule, so the background
        // shows the currents the body is swimming in. Two components cross into knotted filaments.
        let pc = mouseDrag(ro + rd * max(-dot(ro, rd), 0.0));
        let cur = voidCurrent(pc);
        let lx = isoLine(cur.x * 5.0, 0.09);
        let ly = isoLine(cur.y * 5.0, 0.09);
        let knot = lx * ly;
        let near = 0.35 + 0.65 * exp(-length(pc) * 0.35);
        let filStrength = (0.15 + fluid * 0.9) * near;
        let filCol = mix(vec3<f32>(0.05, 0.3, 0.5), hueShiftCol, 0.35);
        col += filCol * (lx * 0.55 + ly * 0.4 + knot * 0.8) * filStrength;
        // lantern light reaches the nearest currents
        col += lanternCol * (lx + ly) * lanternLight(pc) * 0.05;
    }

    // Add volumetric bloom
    col += vec3<f32>(0.1, 0.4, 0.8) * vol * biolum * (0.5 + audio_glow);
    // Idea 1: volumetric lantern halo
    col += lanternCol * lanternHalo;

    // Short HDR light-wake from the previous frame (C = last frame's A, stored as HDR linear)
    let prev = textureLoad(dataTextureC, coord, 0);
    col = max(col, vec3<f32>(0.0));
    col += max(prev.rgb - col, vec3<f32>(0.0)) * 0.45;

    if (!hit) {
        let glowLum = dot(col - vec3<f32>(0.0, 0.05, 0.1), vec3<f32>(0.2126, 0.7152, 0.0722));
        alpha = clamp(0.25 + glowLum * 2.0, 0.0, 1.0);
    }

    textureStore(dataTextureA, id.xy, vec4<f32>(col, alpha));
    textureStore(writeTexture, id.xy, vec4<f32>(acesToneMap(col * 1.4), alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
