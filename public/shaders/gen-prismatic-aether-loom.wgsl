// ═══════════════════════════════════════════════════════════════════
//  Prismatic Aether-Loom
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: plain-weave over-under interlacing (weft and warp threads bob past each other at every crossing); Snell-refracted thin-film thread sheath at true RGB wavelengths
//  A packing: ACES display RGBA in A
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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Thread Density, y=Braid Complexity, z=Cosmic Wind, w=Chromatic Shift
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// Custom mod function
fn mod_f32(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

fn hash(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 3D Noise for Cosmic Wind
fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash(i + vec3<f32>(0.0, 0.0, 0.0)), hash(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(hash(i + vec3<f32>(0.0, 1.0, 0.0)), hash(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(hash(i + vec3<f32>(0.0, 0.0, 1.0)), hash(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(hash(i + vec3<f32>(0.0, 1.0, 1.0)), hash(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z
    );
}

// Domain Warped FBM
fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        v += amp * noise3D(pos);
        pos = pos * 2.0 + vec3<f32>(1.5, 2.5, 3.5);
        amp *= 0.5;
    }
    return v;
}

// Color Palette for Thin-Film Interference
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// Idea 2: thin-film sheath on each thread. Two-beam interference with Snell
// refraction into a low-index sheath (n ~ 1.38) evaluated at 650/532/450 nm.
fn threadFilm(thicknessNm: f32, ndotv: f32) -> vec3<f32> {
    let nFilm = 1.38;
    let sinT = sqrt(max(1.0 - ndotv * ndotv, 0.0)) / nFilm;
    let cosT = sqrt(max(1.0 - sinT * sinT, 0.0));
    let opd = 2.0 * nFilm * thicknessNm * cosT;
    let lambda = vec3<f32>(650.0, 532.0, 450.0);
    return vec3<f32>(0.5) - 0.5 * cos(6.28318 * opd / lambda);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Analytic inverse of acesToneMap so display-space history in C decodes back to linear.
fn acesInverse(yIn: vec3<f32>) -> vec3<f32> {
    let y = clamp(yIn, vec3<f32>(0.0), vec3<f32>(0.98));
    let qa = 2.43 * y - vec3<f32>(2.51);
    let qb = 0.59 * y - vec3<f32>(0.03);
    let disc = max(qb * qb - 4.0 * qa * (0.14 * y), vec3<f32>(0.0));
    return max((-qb - sqrt(disc)) / (2.0 * qa), vec3<f32>(0.0));
}

// KIFS Fold
fn kifsFold(p: vec3<f32>, complexity: f32) -> vec3<f32> {
    var pos = p;
    let n1 = normalize(vec3<f32>(1.0, 1.0, 0.0));
    let n2 = normalize(vec3<f32>(0.0, 1.0, 1.0));
    let iters = i32(complexity);
    for (var i = 0; i < iters; i++) {
        pos.x = abs(pos.x);
        pos.y = abs(pos.y);
        pos.z = abs(pos.z);
        pos -= 2.0 * min(0.0, dot(pos, n1)) * n1;
        pos -= 2.0 * min(0.0, dot(pos, n2)) * n2;
        let rot = rotate2D(0.5);
        let xy = rot * pos.xy;
        pos.x = xy.x; pos.y = xy.y;
    }
    return pos;
}

// Map function
fn map(p: vec3<f32>) -> f32 {
    var pos = p;
    let density = u.zoom_params.x; // Thread Density
    let complexity = u.zoom_params.y; // Braid Complexity
    let wind = u.zoom_params.z; // Cosmic Wind

    // Cosmic Wind Displacement
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let windDisp = fbm(pos * 0.5 + time * wind) * wind * (1.0 + audio * 0.5);
    pos += vec3<f32>(windDisp);

    // KIFS Braid
    pos = kifsFold(pos, complexity);

    // Infinite Cylindrical Lattice
    let spacing = 100.0 / density;
    pos.x = mod_f32(pos.x, spacing) - spacing * 0.5;
    pos.y = mod_f32(pos.y, spacing) - spacing * 0.5;

    // Cylinders along Z
    let d1 = length(pos.xy) - 0.1;
    // Idea 1: plain-weave interlacing. Weft (along X) and warp (along Y) threads
    // undulate in z with opposite phase, so at every crossing one passes over
    // the other. Amplitude is capped by spacing to keep the SDF step-safe.
    let weave = min(0.12 * (1.0 + audio * 0.4), spacing * 0.08);
    // Cylinders along X (weft)
    let d2 = length(vec2<f32>(pos.y, pos.z - weave * cos(6.28318 * pos.x / spacing))) - 0.1;
    // Cylinders along Y (warp)
    let d3 = length(vec2<f32>(pos.z + weave * cos(6.28318 * pos.y / spacing), pos.x)) - 0.1;

    return min(min(d1, d2), d3);
}

// Normal Calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;

    let time = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let audio = bass;
    let chromaticShift = u.zoom_params.w;

    // Mouse Interaction
    // uv spans +-0.5 vertically, so map mouse uv into the same centered frame.
    let mouseX = (u.zoom_config.y - 0.5) * (res.x / res.y);
    let mouseY = u.zoom_config.z - 0.5;
    let mousePos = vec2<f32>(mouseX, mouseY);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

    let windSpeed = 0.7 + u.zoom_params.z * 1.8 + audio * 1.1;
    let travel = time * windSpeed;
    var ro = vec3<f32>(sin(travel * 0.17) * 0.25, cos(travel * 0.13) * 0.18, -3.5);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Gravity Sheer
    let mouseDist = length(uv - mousePos);
    if (mouseDist < 1.0) {
        let pull = 1.0 - smoothstep(0.0, 1.0, mouseDist);
        // Holding the mouse twists the braid harder (a tightened shuttle knot).
        let angle = pull * (2.0 + held * 1.5);
        let rot = rotate2D(angle);
        let rd_xy = rot * rd.xy;
        rd.x = rd_xy.x;
        rd.y = rd_xy.y;
    }

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var hit = false;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t + vec3<f32>(0.0, 0.0, travel);
        d = map(p);
        if (d < 0.001) { hit = true; break; }
        if (t > 20.0) { break; }
        t += d * 0.5;
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let p = ro + rd * t + vec3<f32>(0.0, 0.0, travel);
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = -rd;
        let reflDir = reflect(-lightDir, n);
        let spec = pow(max(dot(viewDir, reflDir), 0.0), 32.0);

        // Thin-film interference
        let ndotv = max(dot(n, viewDir), 0.0);
        let phase = ndotv * chromaticShift + time * 0.5;
        let paletteFilm = palette(phase,
                                   vec3<f32>(0.5), vec3<f32>(0.5),
                                   vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
        // Sheath thickness: Chromatic Shift sets the order, mids breathe it,
        // treble adds a fine shimmer along the thread length.
        let sheathNm = 180.0 + chromaticShift * 120.0 + mids * 60.0 + sin(p.z * 9.0 + time * 3.0) * treble * 25.0;
        let interference = mix(paletteFilm, threadFilm(sheathNm, ndotv), 0.45);

        // Stable lighting occupancy; the previous d/0.1 term approached zero
        // exactly at a hit and accidentally erased the material.
        let ao = 0.68 + 0.32 * diff;

        col = (interference * diff + vec3<f32>(spec)) * ao;

        // Bioluminescent bloom mapped to audio
        let bloom = interference * audio * 2.0;
        col += bloom;
    }

    // Velocity-aligned spectral threads rush toward the viewer between the
    // physical braids, reinforcing warp speed with smooth analytic motion.
    let radial = length(uv);
    let streakAngle = atan2(uv.y, uv.x);
    let streakPhase = streakAngle * (18.0 + u.zoom_params.x * 0.22) + travel * 9.0;
    let speedLines = pow(max(sin(streakPhase), 0.0), 18.0) * smoothstep(0.08, 0.75, radial) *
                     (0.16 + audio * 0.32);
    col += palette(streakAngle / 6.28318 + time * 0.08, vec3<f32>(0.5), vec3<f32>(0.5),
                   vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67)) * speedLines;

    // Clicks send prismatic shuttle waves across the loom.
    var clickThread = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let screenUv = vec2<f32>(coords) / res;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.5) {
            let delta = (screenUv - ripple.xy) * vec2<f32>(res.x / res.y, 1.0);
            clickThread = max(clickThread, exp(-abs(length(delta) - age * 0.62) * 70.0) * exp(-age * 1.9));
        }
    }
    col += vec3<f32>(0.45, 0.9, 1.6) * clickThread * (0.6 + audio * 0.8);

    // Fog
    col = mix(col, vec3<f32>(0.0, 0.0, 0.1), 1.0 - exp(-0.05 * t * t));

    // Radially advected, bounded braid history creates coherent warp trails.
    let radialDir = uv / max(length(uv), 0.001);
    let trailVelocity = radialDir * (2.0 + windSpeed * 3.0);
    let maxCoord = vec2<i32>(max(i32(res.x) - 1, 0), max(i32(res.y) - 1, 0));
    let historyCoord = clamp(coords - vec2<i32>(trailVelocity), vec2<i32>(0), maxCoord);
    let historyTex = textureLoad(dataTextureC, historyCoord, 0);
    let history = acesInverse(historyTex.rgb);
    let hdrColor = clamp(col + history / 1.2 * clamp(0.24 + u.zoom_params.z * 0.12, 0.24, 0.46), vec3<f32>(0.0), vec3<f32>(5.0));
    // Alpha = thread luminance coverage + spectral streaks + shuttle waves.
    let alpha = clamp(length(col) * 0.42 + speedLines * 0.35 + clickThread * (0.3 + held * 0.1), 0.02, 0.96);
    let depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);
    let outColor = vec4<f32>(acesToneMap(hdrColor * (1.2 + bass * 0.1)), alpha);
    textureStore(writeTexture, coords, outColor);
    textureStore(dataTextureA, coords, outColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
