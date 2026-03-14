// ═══════════════════════════════════════════════════════════════════════════════
//  Recursion Mirror Vortex
//  Category: EFFECT | Complexity: VERY_HIGH
//  Nested fractal-like mirrors that fold the image into itself at precise
//  points, creating "infinite hallway" moments. Self-referential without
//  becoming noisy—feedback-driven Droste effect with Möbius transform.
//  Mathematical approach: Complex-plane Möbius transformations, logarithmic
//  spiral mapping, multi-level feedback with decay, depth-aware recursion depth.
// ═══════════════════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=RecursionDepth, y=MouseX, z=MouseY, w=FeedbackMix
    zoom_params: vec4<f32>,  // x=SpiralTightness, y=MirrorCount, z=ZoomSpeed, w=ColorShift
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Complex number operations
// ─────────────────────────────────────────────────────────────────────────────
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let denom = dot(b, b) + 1e-10;
    return vec2<f32>(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / denom;
}

fn clog(z: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(log(length(z) + 1e-10), atan2(z.y, z.x));
}

fn cexp(z: vec2<f32>) -> vec2<f32> {
    return exp(z.x) * vec2<f32>(cos(z.y), sin(z.y));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Möbius transformation: f(z) = (az + b) / (cz + d)
//  Creates conformal maps that preserve angles—perfect for mirror recursion
// ─────────────────────────────────────────────────────────────────────────────
fn mobius(z: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>) -> vec2<f32> {
    let num = cmul(a, z) + b;
    let den = cmul(c, z) + d;
    return cdiv(num, den);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Logarithmic spiral mapping for Droste effect
//  Maps a ring [r1, r2] to itself via log-polar coordinates
// ─────────────────────────────────────────────────────────────────────────────
fn drosteMap(uv: vec2<f32>, center: vec2<f32>, time: f32, tightness: f32) -> vec2<f32> {
    let z = uv - center;
    var lz = clog(z);

    // Scale factor for the spiral
    let r1 = 0.1;
    let r2 = 1.0;
    let logScale = log(r2 / r1);
    let twoPi = 6.28318;

    // Rotate in log space → zoom in real space
    lz.y += time * tightness;
    lz.x = lz.x - logScale * floor(lz.x / logScale);

    let mapped = cexp(lz) * r1;
    return mapped + center;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Kaleidoscopic fold: reflect across N mirror planes
// ─────────────────────────────────────────────────────────────────────────────
fn kaleidoFold(p: vec2<f32>, mirrors: f32) -> vec2<f32> {
    var q = p;
    let angle = 6.28318 / mirrors;
    var theta = atan2(q.y, q.x);
    theta = abs(theta % angle - angle * 0.5);
    let r = length(q);
    return vec2<f32>(r * cos(theta), r * sin(theta));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hash
// ─────────────────────────────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// ─────────────────────────────────────────────────────────────────────────────
//  HSV to RGB
// ─────────────────────────────────────────────────────────────────────────────
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(h6 % 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let uv = fragCoord / dims;
    let time = u.config.x;

    // ─────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ─────────────────────────────────────────────────────────────────────────
    let spiralTight = u.zoom_params.x * 2.0 + 0.3;         // 0.3 – 2.3
    let mirrorCount = floor(u.zoom_params.y * 6.0 + 2.0);  // 2 – 8 mirrors
    let zoomSpeed = u.zoom_params.z * 0.8 + 0.1;           // 0.1 – 0.9
    let colorShift = u.zoom_params.w;                        // 0 – 1
    let recursionLevels = i32(u.zoom_config.x * 4.0 + 1.0); // 1 – 5
    let feedbackMix = u.zoom_config.w * 0.4 + 0.5;         // 0.5 – 0.9
    let mousePos = vec2<f32>(u.zoom_config.y / dims.x, u.zoom_config.z / dims.y);

    // ─────────────────────────────────────────────────────────────────────────
    //  Read depth for recursion-depth modulation
    // ─────────────────────────────────────────────────────────────────────────
    let depth = textureSampleLevel(readDepthTexture, u_sampler, uv, 0.0).r;

    // ─────────────────────────────────────────────────────────────────────────
    //  Recursive mirror folding
    // ─────────────────────────────────────────────────────────────────────────
    let center = mix(vec2<f32>(0.5), mousePos, 0.3);
    var p = uv;
    var accumulatedColor = vec3<f32>(0.0);
    var totalWeight = 0.0;

    for (var level = 0; level < 5; level++) {
        if (level >= recursionLevels) { break; }

        let weight = 1.0 / f32(level + 1);
        let levelDepth = depth * f32(level + 1) * 0.3;

        // Step 1: Droste spiral — self-similar zoom
        p = drosteMap(p, center, time * zoomSpeed * f32(level + 1) * 0.3, spiralTight);

        // Step 2: Kaleidoscopic fold — mirror symmetry
        let centered = p - center;
        let folded = kaleidoFold(centered, mirrorCount + f32(level));
        p = folded + center;

        // Step 3: Möbius warp — conformal twist at each level
        let phase = time * 0.2 + f32(level) * 1.3;
        let mobiusA = vec2<f32>(cos(phase), sin(phase));
        let mobiusB = vec2<f32>(0.1 * sin(time * 0.3), 0.0);
        let mobiusC = vec2<f32>(0.0, 0.05 * cos(time * 0.5));
        let mobiusD = vec2<f32>(1.0, 0.0);
        let zIn = (p - 0.5) * 2.0;
        let zOut = mobius(zIn, mobiusA, mobiusB, mobiusC, mobiusD);
        p = zOut * 0.5 + 0.5;

        // Wrap to [0,1]
        p = fract(p);

        // Sample at this recursion level
        let sampleCol = textureSampleLevel(readTexture, u_sampler, p, 0.0).rgb;

        // Color-shift each recursion deeper into the spectrum
        let hueShift = colorShift * f32(level) * 0.12;
        let tinted = hsv2rgb(fract(hueShift + f32(level) * 0.08), 0.15, 1.0);
        let levelColor = sampleCol * mix(vec3<f32>(1.0), tinted, 0.3);

        accumulatedColor += levelColor * weight;
        totalWeight += weight;
    }

    accumulatedColor /= max(totalWeight, 0.001);

    // ─────────────────────────────────────────────────────────────────────────
    //  Ripple interaction: local mirror distortion
    // ─────────────────────────────────────────────────────────────────────────
    let rippleCount = u32(u.config.y);
    var rippleGlow = 0.0;
    for (var i = 0u; i < rippleCount; i++) {
        let r = u.ripples[i];
        let dist = distance(uv, r.xy);
        let age = time - r.z;
        if (age > 0.0 && age < 3.0) {
            let ring = abs(sin(dist * 25.0 - age * 4.0)) * exp(-dist * 6.0) * exp(-age);
            rippleGlow += ring;
        }
    }
    let mirrorEdge = hsv2rgb(fract(time * 0.1), 0.6, 1.0);
    accumulatedColor += mirrorEdge * rippleGlow * 0.2;

    // ─────────────────────────────────────────────────────────────────────────
    //  Vignette frame: emphasize the infinite-hallway center
    // ─────────────────────────────────────────────────────────────────────────
    let vignette = 1.0 - 0.35 * pow(length(uv - center) * 1.5, 2.0);
    accumulatedColor *= max(vignette, 0.0);

    // ─────────────────────────────────────────────────────────────────────────
    //  Feedback: blend with history for temporal persistence
    // ─────────────────────────────────────────────────────────────────────────
    let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let finalColor = mix(accumulatedColor, history, feedbackMix);

    // ─────────────────────────────────────────────────────────────────────────
    //  Output
    // ─────────────────────────────────────────────────────────────────────────
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
