// ----------------------------------------------------------------
// Astro-Mechanical Quantum-Furnace Engine — Batch 63
// Category: generative
// KIFS gear-train around a plasma furnace, run hot and fast:
// psychedelic exhaust spectra, riveted gear greeble, spring-cursor
// magnetic well, held overdrive, capped click detonation rings.
// Contract: 13 bindings, ACES, semantic alpha, dataTextureA writeback only,
//           exact textureLoad from dataTextureC, plasmaBuffer three-band audio
//           (the legacy `audio = u.config.y` rippleCount misread is gone),
//           bounded extraBuffer[133..138] state.
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Gear Complexity, y=Plasma Intensity, z=Refraction Index, w=Emission Threshold
    ripples: array<vec4<f32>, 50>,
};

// --- Math & Noise Helpers ---

const PI: f32 = 3.14159265359;
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
var<private> g_held: f32;
var<private> g_blast: f32;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + vec3<f32>(33.33));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Psychedelic furnace spectrum — molten wheel spun by the audio
fn furnacePalette(t: f32, drive: f32) -> vec3<f32> {
    let phase = vec3<f32>(0.05, 1.85 + drive * 1.3, 3.95 - drive * 1.0);
    return 0.5 + 0.5 * cos(TAU * t + phase);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (vec3<f32>(3.0) - 2.0 * f);
    let n = i.x + i.y * 157.0 + i.z * 113.0;

    let a = hash3(vec3<f32>(n)).x;
    let b = hash3(vec3<f32>(n + 1.0)).x;
    let c = hash3(vec3<f32>(n + 157.0)).x;
    let d = hash3(vec3<f32>(n + 158.0)).x;
    let e = hash3(vec3<f32>(n + 113.0)).x;
    let f1 = hash3(vec3<f32>(n + 114.0)).x;
    let g = hash3(vec3<f32>(n + 270.0)).x;
    let h = hash3(vec3<f32>(n + 271.0)).x;

    let res = mix(
        mix(mix(a, b, w.x), mix(c, d, w.x), w.y),
        mix(mix(e, f1, w.x), mix(g, h, w.x), w.y),
        w.z
    );
    return res * 2.0 - 1.0;
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for(var i = 0; i < 4; i++) {
        f += amp * noise3D(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return f;
}

// --- SDF Scene ---

struct MapData {
    d: f32,
    mat: f32, // 0 = void/dust, 1 = gears, 2 = plasma core
    glow: f32
}

fn map(p: vec3<f32>, time: f32, audio: f32, gearComplexity: f32, mouseXY: vec2<f32>) -> MapData {
    var d = 1000.0;
    var mat = 0.0;
    var glow = 0.0;

    var pos = p;

    // Magnetic distortion well at the smoothed cursor — held deepens it
    let gravityWell = vec3<f32>(mouseXY.x * 10.0, -mouseXY.y * 10.0, 0.0);
    let distToMouse = length(pos - gravityWell);
    let warpAmt = exp(-distToMouse * 0.2) * (1.0 + g_held * 1.5 + g_blast * 1.2);
    pos += normalize(pos - gravityWell + vec3<f32>(1e-4)) * warpAmt * sin(time * 6.0);

    // Core plasma furnace
    let coreRadius = 2.0 + audio * 0.6 + g_blast * 0.5;
    let coreWarp = fbm(pos * 2.0 - time * 3.0);
    let dCore = length(pos) - coreRadius + coreWarp * 0.8;

    // KIFS fractal gears — spin rate scales with bass and the held throttle
    var q = pos;
    let spin = time * (1.2 + g_bass * 1.6 + g_held * 1.0);
    let new_xz1 = rot(spin) * vec2<f32>(q.x, q.z);
    q.x = new_xz1.x;
    q.z = new_xz1.y;
    let new_xy = rot(spin * 0.75) * vec2<f32>(q.x, q.y);
    q.x = new_xy.x;
    q.y = new_xy.y;

    let iterations = i32(mix(2.0, 6.0, clamp(gearComplexity, 0.0, 1.0)));
    var scale = 1.0;

    for(var i = 0; i < 6; i++) {
        if (i >= iterations) { break; }
        q = abs(q) - 1.5 * pow(0.6, f32(i));

        let a = dot(q, vec3<f32>(1.0)) * 0.5;
        q -= 2.0 * min(0.0, a) * vec3<f32>(1.0);
        q = q * 1.4;
        scale *= 1.4;

        let new_xz2 = rot(0.2 + f32(i) * 0.05) * vec2<f32>(q.x, q.z);
        q.x = new_xz2.x;
        q.z = new_xz2.y;
    }

    var dGears = sdTorus(q, vec2<f32>(3.0, 0.5)) / scale;

    // Gear greeble: cut teeth and rivet rows along the torus (geometric detail)
    let gearAngle = atan2(q.z, q.x);
    let teeth = abs(sin(gearAngle * 26.0));
    let rivets = sin(gearAngle * 13.0) * sin(q.y * 22.0);
    dGears -= (teeth * 0.06 + rivets * 0.03) / scale;

    // Audio-reactive exhaust streams
    var pStream = pos;
    pStream.y -= time * 14.0;
    let streamNoise = fbm(pStream * 3.0);
    let dStreams = length(pos.xz) - 0.5 - audio * streamNoise * 2.2;

    dGears = max(dGears, -(length(pos) - coreRadius - 0.5)); // carve the core cavity

    if (dCore < dGears && dCore < dStreams) {
        d = dCore;
        mat = 2.0;
        glow = pow(max(0.0, 1.0 - dCore), 2.0);
    } else if (dGears < dStreams) {
        d = dGears;
        mat = 1.0;
    } else {
        d = dStreams;
        mat = 2.0;
        glow = pow(max(0.0, 1.0 - dStreams), 2.0);
    }

    return MapData(d * 0.6, mat, glow); // safe step
}

fn getNormal(p: vec3<f32>, time: f32, audio: f32, complexity: f32, mouse: vec2<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, audio, complexity, mouse).d;
    let n = vec3<f32>(
        map(p + e.xyy, time, audio, complexity, mouse).d - d,
        map(p + e.yxy, time, audio, complexity, mouse).d - d,
        map(p + e.yyx, time, audio, complexity, mouse).d - d
    );
    return normalize(n);
}

// --- Main Compute ---

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) { return; }

    let coord = vec2<i32>(id.xy);
    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    let uv01 = fragCoord / res;
    let uv = (fragCoord - 0.5 * res) / res.y;
    let aspect = vec2<f32>(res.x / max(res.y, 1.0), 1.0);

    let time = u.config.x;

    // Three-band audio — plasmaBuffer, never config.y (that is rippleCount)
    g_bass = plasmaBuffer[0].x;
    g_mids = plasmaBuffer[0].y;
    g_treble = plasmaBuffer[0].z;
    let audio = g_bass * 0.6 + g_mids * 0.3 + g_treble * 0.2;

    // UI Sliders
    let gearComplexity = u.zoom_params.x;
    let plasmaIntensity = u.zoom_params.y;
    let refIndex = u.zoom_params.z;
    let emissionThresh = u.zoom_params.w;

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
            let omega = 9.5;
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
    // Mouse UV is 0..1 top-down; map straight to centred coords (no resolution divide)
    let mouseNorm = smoothMouse * 2.0 - 1.0;

    // ── click detonation rings (capped, bounded) ───────────────────────
    var blast = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 1.2) {
            let front = abs(length((uv01 - rp.xy) * aspect) - age * 1.0);
            blast = max(blast, exp(-front * 30.0) * (1.0 - age / 1.2));
        }
    }
    blast = min(blast, 1.0);
    g_blast = blast;

    // Camera — orbits fast, cursor tilts it, held pulls in
    var ro = vec3<f32>(0.0, 0.0, 12.0 - g_held * 2.0 + blast * 1.5);
    let orbit = rot(time * (0.35 + g_bass * 0.7) + (smoothMouse.x - 0.5) * 1.6) * ro.xz;
    ro.x = orbit.x;
    ro.z = orbit.y;
    ro.y = (0.5 - smoothMouse.y) * 6.0;

    let lookAt = vec3<f32>(0.0, 0.0, 0.0);
    let fwd = normalize(lookAt - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let rd = normalize(fwd + right * uv.x + up * uv.y);

    // Raymarch
    var t = 0.0;
    var d = 0.0;
    var mat = 0.0;
    var totalGlow = 0.0;
    var iter = 0;

    for(var i = 0; i < 120; i++) {
        iter = i;
        let p = ro + rd * t;
        let resData = map(p, time, audio, gearComplexity, mouseNorm);
        d = resData.d;
        mat = resData.mat;

        if (resData.mat == 2.0) {
            totalGlow += resData.glow * 0.05 * plasmaIntensity;
        }

        if (d < 0.001 || t > 30.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    var fre = 0.0;

    if (t < 30.0) {
        let p = ro + rd * t;
        let n = getNormal(p, time, audio, gearComplexity, mouseNorm);
        let hue = fract(length(p) * 0.1 + time * (0.2 + g_mids * 0.8) + blast * 0.4);

        if (mat == 1.0) {
            // Metallic brass shading, spectrally graded
            let lightDir = normalize(vec3<f32>(1.0, 1.0, 1.0));
            let diff = max(dot(n, lightDir), 0.0);
            let refl = reflect(rd, n);
            let spec = pow(max(dot(refl, lightDir), 0.0), 32.0);
            fre = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);

            let baseColor = mix(vec3<f32>(0.8, 0.6, 0.2), furnacePalette(hue, g_mids), 0.45);
            let envWarp = fbm(refl * max(refIndex, 0.01));

            col = baseColor * diff * 0.6 + vec3<f32>(1.0) * spec * 0.4 + baseColor * envWarp * 0.2;
            col += furnacePalette(hue + 0.3, g_treble) * fre * 0.7;

            // Tooth/rivet banding — surfaces the carved gear greeble
            let band = 0.5 + 0.5 * sin(atan2(p.z, p.x) * 26.0);
            col *= 0.82 + band * 0.36;

            let ao = clamp(1.0 - f32(iter) / 120.0, 0.0, 1.0);
            col *= ao;
        } else if (mat == 2.0) {
            // Quantum plasma core — white-hot centre bleeding into the spectrum
            col = mix(vec3<f32>(1.0), furnacePalette(hue + 0.5, 1.0 + g_bass), 0.45) * (1.5 + g_bass * 0.8);
        }
    } else {
        // Deep space nebula void
        let starNoise = fbm(rd * 50.0 + time * 0.4);
        col = mix(vec3<f32>(0.0), furnacePalette(fract(time * 0.03), g_mids) * 0.2, fbm(rd * 5.0 - time * 0.2) * 0.5 + 0.5);
        col += vec3<f32>(1.0) * pow(max(starNoise - 0.8, 0.0) * 5.0, 3.0);
    }

    // Volumetric exhaust glow
    let glowColor = furnacePalette(fract(time * 0.25 + totalGlow * 0.3), 1.0 + g_treble);
    col += glowColor * totalGlow * step(emissionThresh, totalGlow);

    // Detonation flash + cursor magnetic halo
    col += furnacePalette(fract(time * 1.1), 1.0) * blast * 1.5;
    let cursorDist = length((uv01 - smoothMouse) * aspect);
    col += furnacePalette(fract(time * 0.45 + cursorDist), g_bass) * exp(-cursorDist * 7.5) * (0.12 + g_held * 0.5);

    // Cinematic vignette
    col *= 1.0 - smoothstep(0.5, 1.5, length(uv));

    // ── temporal motion blur — exact load from dataTextureC, no filtering ─
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(prev.rgb * 0.94, col, 0.45 + g_bass * 0.15);

    col = acesToneMap(col * (1.1 + g_mids * 0.25));

    // Semantic alpha: machine presence + furnace emission
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(
        select(0.0, 0.45 + fre * 0.3, t < 30.0)
        + luma * 0.45 + min(totalGlow, 2.0) * 0.15 + blast * 0.3,
        0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));

    // Depth write was a hardcoded zero — pack normalized ray distance instead
    let depth = select(1.0, clamp(t / 30.0, 0.0, 0.995), t < 30.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
