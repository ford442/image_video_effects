// ═══════════════════════════════════════════════════════════════════
//  Neon Acid Geometry
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium-High
//  Upgraded: 2026-09-14
//  Ideas: positive-column striations (ionisation waves with Faraday dark spaces travelling along each neon rim); click titration fronts (expanding neutralisation wave with a sigmoid equivalence-point jump in indicator pH)
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse uv, .w = mouse down
  zoom_params: vec4<f32>,  // .x = Intensity, .y = Speed, .z = Scale, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

// Hash functions
fn hash2(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453123);
}

// Value noise
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// Fractal Brownian Motion
fn fbm(p: vec2<f32>, t: f32) -> f32 {
    var val: f32 = 0.0;
    var amp: f32 = 0.5;
    var freq: f32 = 1.0;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        val += amp * vnoise(p * freq + t * 0.3);
        freq *= 2.0;
        amp *= 0.5;
    }
    return val;
}

// 2D rotation matrix
fn rot2(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ═══ CHUNK: acesToneMap (standard ACES) ═══
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: phToColor (universal indicator pH→RGB) ═══
// pH 0-3: strong acid → red
// pH 4-6: weak acid → orange/yellow
// pH 7:   neutral → green
// pH 8-10: weak base → blue
// pH 11-14: strong base → purple
fn phToColor(ph: f32) -> vec3<f32> {
    let p = clamp(ph, 0.0, 14.0);
    let c0 = vec3<f32>(1.0, 0.0, 0.2);   // pH 0  strong acid
    let c1 = vec3<f32>(1.0, 0.6, 0.0);   // pH 3.5 weak acid
    let c2 = vec3<f32>(0.0, 0.8, 0.3);   // pH 7   neutral
    let c3 = vec3<f32>(0.0, 0.4, 1.0);   // pH 9   weak base
    let c4 = vec3<f32>(0.6, 0.0, 1.0);   // pH 14  strong base
    let t1 = smoothstep(0.0, 3.5, p);
    let t2 = smoothstep(3.5, 7.0, p);
    let t3 = smoothstep(7.0, 9.0, p);
    let t4 = smoothstep(9.0, 14.0, p);
    var col = mix(c0, c1, t1);
    col = mix(col, c2, t2);
    col = mix(col, c3, t3);
    col = mix(col, c4, t4);
    return col;
}

// ═══ CHUNK: Snell's Law / Critical Angle ═══
fn snellRefract(incident: f32, n1: f32, n2: f32) -> f32 {
    let sinTheta2 = (n1 / n2) * sin(incident);
    return asin(clamp(sinTheta2, -1.0, 1.0));
}

fn criticalAngle(n1: f32, n2: f32) -> f32 {
    return asin(clamp(n2 / n1, 0.0, 1.0));
}

// Triangle SDF
fn sdTriangle(p: vec2<f32>, r: f32) -> f32 {
    let k = sqrt(3.0);
    let q = abs(p);
    return max(q.x - r, max(q.x + k * p.y, q.x - k * p.y) * 0.5);
}

// Hexagon SDF
fn sdHexagon(p: vec2<f32>, r: f32) -> f32 {
    let q = abs(p);
    return max(q.x - r * 0.866, max(q.x * 0.5 + q.y * 0.866 - r * 0.866, q.y - r * 0.5));
}

// Circle SDF
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

// Smooth minimum for blending shapes
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Glow from SDF
fn sdfGlow(d: f32, width: f32, audioIntensity: f32) -> f32 {
    return smoothstep(width, 0.0, d) * audioIntensity;
}

// ── IDEA 1 helper: positive-column striations ──
// In a DC glow discharge the positive column breaks into standing/moving
// ionisation waves: bright luminous striae separated by dark spaces, drifting
// from anode to cathode. Parameterised by arc position along the tube rim.
fn striation(arc: f32, phase: f32) -> f32 {
    let w = 0.5 + 0.5 * cos(arc - phase);
    // Sharp luminous head, long darker tail (asymmetric ionisation front)
    return 0.35 + 0.65 * pow(w, 3.0);
}

// ── IDEA 2 helper: titration curve ──
// Fraction of equivalence reached (0..1+) → pH relative to neutral via the
// steep sigmoid jump around the equivalence point (buffer plateau either side).
fn titrationWeight(eq: f32) -> f32 {
    return 1.0 / (1.0 + exp(-(eq - 0.5) * 14.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let minRes = min(resolution.x, resolution.y);
    let uv = (vec2<f32>(pixel) - resolution * 0.5) / minRes;
    let time = u.config.x;
    let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);
    let mouseNorm = (u.zoom_config.yz - 0.5) * resolution / minRes;

    var intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = max(u.zoom_params.z, 0.05);
    let colorShift = u.zoom_params.w;

    // Audio reactivity (plasmaBuffer only, clamped)
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    intensity = intensity * (1.0 + treble * 0.4);

    // pH oscillation: 0→14→0 cycle; bass nudges phase (no time×audio jitter)
    let phCycle = 7.0 + 7.0 * sin(time * 0.5 + bass * 1.2);

    // Critical-angle refraction distortion (water-air ~48.6°)
    let crit = criticalAngle(1.33, 1.0);
    let refractUV = uv * (1.0 + sin(crit) * 0.1 * bass);

    // ── IDEA 2: click titration fronts ──
    // Each click drops titrant; a neutralisation front diffuses outward.
    // Behind the front the solution approaches equivalence and the indicator
    // snaps toward neutral green through the steep titration-curve jump.
    var titrant = 0.0;
    var frontFlash = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 3.0) {
            let rpos = (rp.xy - 0.5) * resolution / minRes;
            let dist = length(refractUV - rpos);
            let front = 0.08 + sqrt(age) * 0.32;          // diffusive spread ∝ √t
            let decay = exp(-age * 0.9);
            let eq = smoothstep(front + 0.03, front - 0.08, dist) * 1.2 * decay;
            titrant = max(titrant, titrationWeight(eq) * smoothstep(0.0, 0.05, eq));
            frontFlash = max(frontFlash, exp(-pow((dist - front) * 45.0, 2.0)) * decay);
        }
    }

    var col = vec3<f32>(0.0);
    var coverage = 0.0;

    // Deep psychedelic background tinted by pH
    let bgNoise = fbm(refractUV * 2.0 * scale, time * 0.1 * speed);
    let bgHue = fract(bgNoise * 0.3 + time * 0.04 * speed + colorShift);
    let bgPH = mix(fract(bgHue * 14.0) * 14.0, 7.0, titrant);
    col += phToColor(bgPH) * bgNoise * 0.15;
    col += vec3<f32>(0.02, 0.0, 0.04);

    // Beat-like rhythm
    let beat = pow(abs(sin(time * 1.5 * speed)), 4.0);
    let pulse = (1.0 + beat * 0.4 * intensity) * (1.0 + bass * 0.3);

    // Grid of shape centers
    let gridCount = 4;
    for (var gx: i32 = -gridCount; gx <= gridCount; gx = gx + 1) {
        for (var gy: i32 = -gridCount; gy <= gridCount; gy = gy + 1) {
            let center = vec2<f32>(f32(gx), f32(gy)) * (0.18 / scale);
            let seed = hash2(vec2<f32>(f32(gx) + 50.0, f32(gy) + 100.0));
            let seed2 = hash1(f32(gx * 7 + gy * 13) + 200.0);

            // Local UV rotated and scaled
            let rotAngle = time * speed * (0.3 + seed * 0.7) + seed2 * TAU + beat * 0.5;
            let localUV = rot2(rotAngle) * (refractUV - center);

            // Scale pulsing
            let shapeScale = (0.04 + 0.03 * sin(time * 2.0 * speed + seed * 5.0) * intensity) * pulse;

            // Select shape type based on seed
            let shapeType = floor(seed * 3.0);
            var shapeDist: f32 = 1000.0;
            var siblingDist: f32 = 1000.0;
            let morphT = time * speed * 0.55 + bass * 0.6 + seed * TAU;
            let siblingOff = vec2<f32>(cos(morphT), sin(morphT)) * shapeScale * 0.55;

            if (shapeType < 1.0) {
                let melt = vec2<f32>(
                    vnoise(localUV * 8.0 + time * speed * 2.0 + mids * 1.5),
                    vnoise(localUV * 8.0 + time * speed * 2.0 + mids * 1.5 + 50.0)
                ) * 0.015 * intensity;
                shapeDist = sdTriangle(localUV + melt, shapeScale);
                siblingDist = sdTriangle(localUV + melt - siblingOff, shapeScale * 0.85);
            } else if (shapeType < 2.0) {
                let melt = vec2<f32>(
                    vnoise(localUV * 6.0 + time * speed * 1.5 + mids * 1.0),
                    vnoise(localUV * 6.0 + time * speed * 1.5 + mids * 1.0 + 30.0)
                ) * 0.012 * intensity;
                shapeDist = sdHexagon(localUV + melt, shapeScale * 1.2);
                siblingDist = sdHexagon(localUV + melt - siblingOff, shapeScale);
            } else {
                let wobble = vnoise(localUV * 10.0 + time * speed * 3.0) * 0.01 * intensity;
                shapeDist = sdCircle(localUV, shapeScale + wobble);
                siblingDist = sdCircle(localUV - siblingOff, shapeScale * 0.9 + wobble);
            }
            shapeDist = smin(shapeDist, siblingDist, 0.028);

            let rawPH = fract(seed + phCycle / 14.0 + colorShift + beat * 0.2) * 14.0;
            let shapePH = mix(rawPH, 7.0, titrant);
            let shapeCol = phToColor(shapePH);
            let geoFill = mix(vec3<f32>(0.07, 0.09, 0.12), shapeCol * 0.32, 0.4);

            // ── IDEA 1: positive-column striations along the neon rim ──
            // Arc coordinate around the tube; integer stria count keeps the
            // pattern seamless. Striae drift at a rate set by Speed; mids
            // (field strength) shift their phase; held mouse = higher current,
            // striae crowd together.
            let arc = atan2(localUV.y, localUV.x);
            let striaCount = floor(4.0 + seed * 4.0 + mouseDown * 3.0);
            let striaPhase = time * speed * (2.0 + seed * 2.0) + mids * 1.5 + seed2 * TAU;
            let stria = striation(arc * striaCount, striaPhase);

            let glow1 = sdfGlow(abs(shapeDist), 0.012 * intensity * pulse, 2.5) * stria;
            let glow2 = sdfGlow(abs(shapeDist), 0.035 * intensity * pulse, 0.8) * (0.7 + 0.3 * stria);
            let fill = smoothstep(0.005, -0.005, shapeDist) * 0.6;

            col += shapeCol * glow1 * intensity * 1.5;
            col += shapeCol * glow2 * intensity * 0.5;
            col += geoFill * fill * intensity * 0.8;
            coverage = max(coverage, clamp(glow1 * 0.4 + glow2 * 0.2 + fill * 0.9, 0.0, 1.0));

            // Mouse-reactive explosion at cursor with localized pH disturbance
            let toMouse = length(refractUV - mouseNorm);
            let mouseInfluence = smoothstep(0.3, 0.0, toMouse) * mouseDown;
            if (mouseInfluence > 0.01) {
                let mouseDist = length(localUV) * (1.0 + mouseInfluence * 3.0);
                let mouseGlow = exp(-mouseDist * mouseDist * 80.0) * mouseInfluence;
                // Mouse toggles between acid (pH 2) and base (pH 12) splashes
                let mousePH = select(2.0, 12.0, mouseDown > 0.5 && hash1(seed + time) > 0.5);
                col += phToColor(mousePH) * mouseGlow * intensity * 3.0;
                coverage = max(coverage, clamp(mouseGlow, 0.0, 1.0));
            }
        }
    }

    // Global overlay: morphing acid waves tinted by pH
    let wave1 = sin(refractUV.x * 8.0 * scale + time * 2.0 * speed) * cos(refractUV.y * 6.0 * scale - time * 1.5 * speed);
    let wave2 = sin(refractUV.x * 5.0 * scale - time * speed + refractUV.y * 7.0 * scale) * 0.5;
    let wave = (wave1 + wave2) * 0.5;
    let waveGlow = smoothstep(0.3, 0.8, abs(wave)) * 0.15 * intensity;
    col += phToColor(mix(fract(wave * 7.0 + phCycle * 0.5), 7.0, titrant)) * waveGlow;

    // Titration front: indicator flash at the equivalence boundary
    col += phToColor(7.0 + 2.0 * sin(time * 3.0)) * frontFlash * (0.6 + mids * 0.4) * (0.5 + intensity);

    // Treble-driven bubble sparkle
    let sparkle = hash2(vec2<f32>(floor(refractUV * 40.0)));
    let sparkleTrigger = step(1.0 - treble * 0.3, sparkle);
    col += phToColor(fract(sparkle * 14.0)) * sparkleTrigger * treble * 1.2;

    let maxC = vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1);
    let prev = textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), maxC), 0);
    col = mix(prev.rgb * 0.96, col, 0.25);

    let caStr = 0.003 * (1.0 + bass * 0.5);
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    let vig = 1.0 - dot(uv * 0.7, uv * 0.7);
    col *= clamp(vig, 0.0, 1.0) * 1.3;

    let mapped = acesToneMap(max(col, vec3<f32>(0.0)) * 1.1);
    // Alpha = neon-tube coverage (rim glow / fill / splash) + titration front
    // + sparkle, with a decaying trail memory from the previous frame.
    let alpha = clamp(max(coverage + frontFlash * 0.4 + sparkleTrigger * treble * 0.3, prev.a * 0.85), 0.06, 1.0);
    let out = vec4<f32>(mapped, alpha);
    textureStore(writeTexture, pixel, out);
    textureStore(dataTextureA, pixel, out);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(clamp(coverage * 0.6 + length(mapped) * 0.2, 0.0, 1.0), 0.0, 0.0, 0.0));
}
