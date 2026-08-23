// ═══════════════════════════════════════════════════════════════════
//  Celestial Forge — Batch 63
//  Category: generative
//  A stellar engine hammering at speed: contra-rotating greebled rings,
//  psychedelic plasma spectra, spring-cursor orbit, held forge surge,
//  capped click hammer-strike shockwaves.
//  Contract: 13 bindings, ACES, semantic alpha, dataTextureA writeback only,
//            exact textureLoad from dataTextureC, plasmaBuffer three-band audio,
//            bounded extraBuffer[133..138] state.
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Rotation Speed, y=Complexity, z=Ring Scale, w=Core Intensity
    ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

const SPRING_X: i32 = 133;
const SPRING_Y: i32 = 134;
const SPRING_VX: i32 = 135;
const SPRING_VY: i32 = 136;
const SPRING_T: i32 = 137;
const SPRING_INIT: i32 = 138;

var<private> g_bass: f32;
var<private> g_mids: f32;
var<private> g_treble: f32;
var<private> g_strike: f32;
var<private> g_held: f32;

// --- Helper Functions ---

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    return clamp((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Psychedelic forge spectrum — molten wheel spun by the audio
fn forgePalette(t: f32, drive: f32) -> vec3<f32> {
    let phase = vec3<f32>(0.1, 1.9 + drive * 1.3, 4.0 - drive * 1.0);
    return 0.5 + 0.5 * cos(TAU * t + phase);
}

// --- SDFs ---

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// --- Noise Functions ---
fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    var f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(
            mix(hash31(i + vec3<f32>(0.0, 0.0, 0.0)), hash31(i + vec3<f32>(1.0, 0.0, 0.0)), f.x),
            mix(hash31(i + vec3<f32>(0.0, 1.0, 0.0)), hash31(i + vec3<f32>(1.0, 1.0, 0.0)), f.x),
            f.y
        ),
        mix(
            mix(hash31(i + vec3<f32>(0.0, 0.0, 1.0)), hash31(i + vec3<f32>(1.0, 0.0, 1.0)), f.x),
            mix(hash31(i + vec3<f32>(0.0, 1.0, 1.0)), hash31(i + vec3<f32>(1.0, 1.0, 1.0)), f.x),
            f.y
        ),
        f.z
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i = 0; i < 4; i++) {
        value += amplitude * noise3D(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// --- Map Function ---
// Returns vec3: x = distance, y = material ID, z = emission
fn map(p_in: vec3<f32>) -> vec3<f32> {
    let p = p_in;
    let time = u.config.x;
    // Fast motion: the forge spins hard, bass and held both throttle it
    let speed = u.zoom_params.x * (3.2 + g_bass * 2.6 + g_held * 1.8);
    let complexity = u.zoom_params.y;
    let scale = u.zoom_params.z;

    var d = 1000.0;
    var mat = 0.0;
    var emission = 0.0;

    // --- Central energy core ---
    let corePulse = 1.0 + sin(time * (6.0 + g_bass * 6.0)) * 0.12 + g_strike * 0.25;
    let coreRadius = 0.8 * corePulse * scale;
    let dCore = sdSphere(p, coreRadius);

    let plasmaNoise = fbm(p * 3.0 + time * 1.6);
    let dCorePlasma = dCore - plasmaNoise * 0.1;

    if (dCorePlasma < d) {
        d = dCorePlasma;
        mat = 1.0;
        emission = u.zoom_params.w * (1.0 + plasmaNoise * 0.5);
    }

    // --- Contra-rotating rings ---
    let numRings = 3 + i32(complexity * 3.0);

    for (var i = 0; i < numRings; i++) {
        let fi = f32(i);

        let ringRadius = (1.5 + fi * 0.8) * scale;
        let ringThickness = 0.08 + complexity * 0.05;

        let rotSpeed1 = time * speed * (0.5 + fi * 0.2);
        let rotSpeed2 = time * speed * (0.3 - fi * 0.15);

        var ringP = p;

        if (i % 2 == 0) {
            ringP = rotX(rotSpeed1) * ringP;
            ringP = rotY(rotSpeed2 * 0.5) * ringP;
        } else {
            ringP = rotY(rotSpeed1) * ringP;
            ringP = rotZ(rotSpeed2 * 0.7) * ringP;
        }

        var dTorus = sdTorus(ringP, vec2<f32>(ringRadius, ringThickness));

        // Greeble pass: hull plating + rivet rows carved into every ring
        let ringAngle = atan2(ringP.z, ringP.x);
        let plating = sin(ringAngle * (24.0 + fi * 8.0)) * sin(ringP.y * 30.0);
        dTorus -= plating * 0.008 * (1.0 + complexity);

        // Boolean trenches
        let trenchCount = 6.0 + fi * 4.0;
        let trenchAngle = ringAngle * trenchCount + time * speed;
        let trenchPos = vec3<f32>(
            ringRadius * cos(trenchAngle / trenchCount),
            ringP.y,
            ringRadius * sin(trenchAngle / trenchCount)
        );
        let dTrench = sdBox(ringP - trenchPos, vec3<f32>(0.02, 0.15, 0.02) * scale);

        let dRingDetail = max(dTorus, -dTrench);

        // Glowing panels
        let panelCount = 12.0;
        let panelPhase = sin(ringAngle * panelCount + time * speed * 3.0);
        let isPanel = panelPhase > 0.7 - g_treble * 0.2;

        if (dRingDetail < d) {
            d = dRingDetail;
            mat = 2.0;
            if (isPanel) {
                mat = 3.0;
                emission = 0.5 * u.zoom_params.w;
            }
        }
    }

    // --- Plasma arcs — fast, and click strikes fire extra ones ---
    let arcTime = fract(time * (1.1 + g_mids * 0.8));
    if (arcTime < 0.3 + g_strike * 0.4) {
        let arcAngle = time * 6.0;
        let arcRadius = 1.2 * scale;
        let arcPos = vec3<f32>(
            arcRadius * cos(arcAngle),
            sin(time * 12.0) * 0.35,
            arcRadius * sin(arcAngle)
        );
        let dArc = sdSphere(p - arcPos, 0.05 * scale * max(1.0 - arcTime * 3.0, 0.05));

        if (dArc < d) {
            d = dArc;
            mat = 4.0;
            emission = 2.0 * u.zoom_params.w * max(1.0 - arcTime * 3.0, 0.0);
        }
    }

    return vec3<f32>(d, mat, emission);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);

    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }

    let coord = vec2<i32>(id.xy);
    let uv01 = fragCoord / dims;
    let uv = (fragCoord * 2.0 - dims) / dims.y;
    let aspect = vec2<f32>(dims.x / max(dims.y, 1.0), 1.0);
    let time = u.config.x;

    g_bass = plasmaBuffer[0].x;
    g_mids = plasmaBuffer[0].y;
    g_treble = plasmaBuffer[0].z;

    let rawMouse = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;
    g_held = select(0.0, 1.0, held);

    // ── spring cursor (extraBuffer[133..138] only) ──────────────────────
    var smoothMouse = rawMouse;
    let hasSpring = arrayLength(&extraBuffer) > 138u;
    if (hasSpring && extraBuffer[SPRING_INIT] > 0.5) {
        smoothMouse = vec2<f32>(extraBuffer[SPRING_X], extraBuffer[SPRING_Y]);
    }
    if (hasSpring && id.x == 0u && id.y == 0u) {
        var springPos = smoothMouse;
        var springVel = vec2<f32>(extraBuffer[SPRING_VX], extraBuffer[SPRING_VY]);
        if (extraBuffer[SPRING_INIT] <= 0.5) {
            springPos = rawMouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[SPRING_T], 0.001, 0.05);
            let omega = 9.0;
            let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
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

    // ── click hammer strikes (capped, bounded) ─────────────────────────
    var strike = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 1.1) {
            let front = abs(length((uv01 - rp.xy) * aspect) - age * 1.05);
            strike = max(strike, exp(-front * 32.0) * (1.0 - age / 1.1));
        }
    }
    strike = min(strike, 1.0);
    g_strike = strike;

    // Camera — orbit steered by the smoothed cursor, auto-spin runs fast
    var ro = vec3<f32>(0.0, 0.0, 6.0 - g_held * 1.2 + strike * 0.8);
    let mouseX = smoothMouse.x * 2.0 - 1.0;
    let mouseY = smoothMouse.y * 2.0 - 1.0;

    let temp_ro_yz = rot(mouseY * 1.5) * ro.yz;
    ro.y = temp_ro_yz.x;
    ro.z = temp_ro_yz.y;

    let temp_ro_xz = rot(mouseX * 3.14159 + time * (0.55 + g_bass * 0.9)) * ro.xz;
    ro.x = temp_ro_xz.x;
    ro.z = temp_ro_xz.y;

    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.8 * ww);

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var m = 0.0;
    var accumEmission = 0.0;
    let maxSteps = 96;
    let maxDist = 30.0;

    for (var i = 0; i < maxSteps; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        accumEmission += res.z;

        if (d < 0.001 || t > maxDist) { break; }
        let stepScale = select(0.85, 0.6, d < 0.3);
        t += d * stepScale;
    }

    // Space background with subtle nebula
    var col = vec3<f32>(0.005, 0.01, 0.02);
    let nebula = fbm(rd * 2.0 + time * 0.25);
    col += forgePalette(nebula + time * 0.05, g_mids) * nebula * 0.06 * max(0.0, rd.y + 0.4);

    let stars = pow(hash31(rd * 500.0), 20.0);
    col += vec3<f32>(stars);

    var fre = 0.0;

    if (t < maxDist) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = normalize(ro - p);

        let corePos = vec3<f32>(0.0);
        let toCore = normalize(corePos - p);
        let distToCore = length(p);
        let coreIntensity = u.zoom_params.w * (1.0 + g_bass * 0.8 + strike * 0.6);

        // Hue races around the forge with the mids
        let hue = fract(distToCore * 0.14 + time * (0.25 + g_mids * 0.85) + strike * 0.35);

        if (m == 1.0) {
            let plasmaDetail = fbm(p * 5.0 + time * 2.0);
            col = forgePalette(hue, 1.0 + g_bass) * (1.0 + plasmaDetail * 0.4) * coreIntensity * 2.0;

        } else if (m == 2.0 || m == 3.0) {
            let dif = max(dot(n, toCore), 0.0);
            let hal = normalize(toCore - rd);
            let spec = pow(max(dot(n, hal), 0.0), 64.0);
            fre = pow(1.0 - max(dot(n, v), 0.0), 5.0);

            let metalCol = vec3<f32>(0.4, 0.45, 0.5);
            let warmRim = forgePalette(hue + 0.2, g_treble) * fre * coreIntensity * 1.3;
            let ambientCore = coreIntensity / (distToCore * distToCore + 1.0);

            col = metalCol * (dif * coreIntensity + ambientCore * 0.3);
            col += vec3<f32>(1.0) * spec * coreIntensity;
            col += warmRim;

            // Plating banding — surfaces the greebled ring detail
            let band = 0.5 + 0.5 * sin(atan2(p.z, p.x) * 24.0 + p.y * 30.0);
            col *= 0.82 + band * 0.36;

            if (m == 3.0) {
                col += forgePalette(hue + 0.55, 1.0) * (0.6 + g_treble * 0.8) * coreIntensity;
            }

        } else if (m == 4.0) {
            col = forgePalette(hue + 0.7, 1.0 + g_treble) * coreIntensity * 3.2;
        }

        col += accumEmission * forgePalette(time * 0.3, g_mids) * 0.05;
        col = mix(col, vec3<f32>(0.005, 0.01, 0.02), 1.0 - exp(-0.08 * t));
    }

    // Hammer-strike flash + cursor forge halo
    col += forgePalette(time * 1.2, 1.0) * strike * 1.5;
    let cursorDist = length((uv01 - smoothMouse) * aspect);
    col += forgePalette(time * 0.5 + cursorDist, g_bass) * exp(-cursorDist * 7.5) * (0.14 + g_held * 0.5);

    // Vignette
    col *= 1.0 - 0.4 * length(uv);

    // ── temporal feedback — exact load, no filtering ────────────────────
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(col, prev.rgb * 0.93, 0.07 + g_bass * 0.04);

    col = acesToneMapping(col * (1.0 + g_mids * 0.25));

    // IGN dither — suppresses banding in the dark-space nebula gradient
    let ign = fract(52.9829189 * fract(dot(fragCoord, vec2<f32>(0.06711056, 0.00583715))));
    col = clamp(col + (ign - 0.5) * (1.0 / 255.0), vec3<f32>(0.0), vec3<f32>(1.0));

    // Semantic alpha: structure presence + forge emission
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(
        select(0.0, 0.45 + fre * 0.3, t < maxDist)
        + luma * 0.45 + min(accumEmission, 2.0) * 0.12 + strike * 0.3,
        0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));

    let sceneDepth = select(1.0, t / maxDist, t < maxDist);
    textureStore(writeDepthTexture, coord, vec4<f32>(sceneDepth, 0.0, 0.0, 0.0));
}
