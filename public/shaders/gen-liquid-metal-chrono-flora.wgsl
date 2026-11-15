// ═══════════════════════════════════════════════════════════════════
//  Liquid-Metal Chrono-Flora
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: Fresnel-Schlick chrome; petal veins along the six-fold
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn floraPull(p: vec3<f32>) -> vec3<f32> {
    let held = select(0.0, 1.0, u.zoom_config.w > 0.0);
    let m = vec2<f32>(u.zoom_config.y, 1.0 - u.zoom_config.z) * 2.0 - 1.0;
    let dist = length(p.xy - m);
    let pull = exp(-dist * 2.0) * 0.5 * held;
    return p - vec3<f32>(m * pull, 0.0);
}

// Utility Functions
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn rot2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Map function
fn map(p: vec3<f32>) -> f32 {
    var pos = floraPull(p);

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mid = clamp(plasmaBuffer[0].y, 0.0, 1.0);

    // Params
    let bloomSpeed = u.zoom_params.y;
    let temporalDistortion = u.zoom_params.z;

    // Core geometry
    let time = u.config.x * 0.5 * bloomSpeed;

    // Temporal distortion waves causing time-reversed ripples
    let timeWave = sin(length(pos) * 2.0 - time * 3.0) * temporalDistortion;
    let effectiveTime = time + timeWave;

    // Domain distortion and SDF combination
    var d = 100.0;

    // Radial distortion
    let angle = atan2(pos.x, pos.z);
    let radius = length(pos.xz);

    let petals = 6.0;
    let petalAngle = angle * petals + effectiveTime;

    // Folding flower structure
    let q = vec3<f32>(
        radius * cos(petalAngle) - 1.0 - bass * 0.3,
        pos.y + sin(radius * 3.0 - effectiveTime * 2.0) * 0.5,
        radius * sin(petalAngle)
    );

    // Base Torus combined with sphere for petals
    let d1 = sdTorus(q, vec2<f32>(1.5, 0.2 + mid * 0.1));
    let d2 = length(pos) - (1.0 + bass * 0.2); // Core sphere

    d = smin(d1, d2, 0.8);

    return d * 0.5; // Scale down for safety
}

// Compute Normal
fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    let coords = vec2<f32>(id.xy);
    if (coords.x >= dims.x || coords.y >= dims.y) { return; }

    let uv = (coords - 0.5 * dims) / min(dims.x, dims.y);

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    for (var i = 0; i < 150; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d < 0.001 || t > 20.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    var out_depth = 1.0;
    var alpha = 0.04;

    let metallicShine = u.zoom_params.x;
    let chronoIntensity = u.zoom_params.w;

    if (t < 20.0) {
        let p = ro + rd * t;
        let n = get_normal(p);

        let viewDir = normalize(ro - p);
        let refl = reflect(-viewDir, n);

        // ── Idea 1: Fresnel-Schlick chrome (§12.2F) ─────────────────
        // Facing metal stays dark. The grazing rim carries the mirror.
        let ndv = clamp(dot(n, viewDir), 0.0, 1.0);
        let f0 = mix(0.55, 0.92, metallicShine);
        let fres = f0 + (1.0 - f0) * pow(1.0 - ndv, 5.0);
        let envCol = vec3<f32>(0.8, 0.9, 1.0) * max(0.0, refl.y * 0.5 + 0.5) * metallicShine * fres;

        let ao = clamp(map(p + n * 0.1) * 10.0, 0.0, 1.0);
        let energyCol = vec3<f32>(0.8, 0.1, 0.9) * (1.0 - ao) * chronoIntensity;

        col = envCol + energyCol;

        let spec = pow(max(dot(refl, normalize(vec3<f32>(1.0, 1.0, -1.0))), 0.0), 32.0);
        col += vec3<f32>(1.0) * spec * metallicShine;

        // ── Idea 2: petal veins along the existing six-fold ─────────
        let fp = floraPull(p);
        let petalR = length(fp.xz);
        let petalA = atan2(fp.x, fp.z);
        let vein = pow(1.0 - abs(sin(petalA * 6.0)), 10.0) * smoothstep(1.7, 0.2, petalR);
        col += vec3<f32>(0.78, 0.86, 0.95) * vein * fres * metallicShine * 0.4;

        out_depth = t / 20.0;
        alpha = clamp(0.2 + fres * 0.5 + (1.0 - ao) * chronoIntensity * 0.25 + vein * 0.15, 0.0, 1.0);
    }

    let coord = vec2<i32>(id.xy);
    let mapped = aces(max(col, vec3<f32>(0.0)));
    let outCol = vec4<f32>(mapped, alpha);
    textureStore(writeTexture, coord, outCol);
    textureStore(writeDepthTexture, coord, vec4<f32>(out_depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outCol);
}
