// ═══════════════════════════════════════════════════════════════════
//  astral-kaleidoscope-grokcf1
//  Category: psychedelic
//  Features: upgraded-rgba, depth-aware, mouse-driven, audio-reactive
//  Upgraded: 2026-09-11, 2026-11-01
//  Ideas: bass/mids-driven spin (rotation + spiral); held-pointer spiral grab toward cursor angle; second counter-rotating object chamber; log-spiral twist term
//  A packing: display RGBA feedback trail (unchanged)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=segments, y=rotationSpeed, z=spiralStrength, w=trails

// ---------------------------------------------------------------
//  Constants and Math Utilities
// ---------------------------------------------------------------
const PI: f32 = 3.14159265359;

fn fmod(x: f32, y: f32) -> f32 {
    if (y == 0.0) { return x; }
    return x - y * floor(x / y);
}

fn rotate(v: vec2<f32>, a: f32) -> vec2<f32> {
    var s = sin(a);
    let c = cos(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

// Fold an angle into one mirrored wedge (same operation as the main fold, reused for chamber 2).
fn foldAngle(angle: f32, segAngle: f32) -> f32 {
    var f = fmod(angle, segAngle);
    if (f < 0.0) { f += segAngle; }
    if (f > segAngle * 0.5) { f = segAngle - f; }
    return f;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Pseudo-random number generator
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// 2D Noise function
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(rand(i), rand(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(rand(i + vec2<f32>(0.0, 1.0)), rand(i + vec2<f32>(1.0, 1.0)), u.x),
               u.y);
}

fn rgb2hsl(c: vec3<f32>) -> vec3<f32> {
    let minVal = min(min(c.r, c.g), c.b);
    let maxVal = max(max(c.r, c.g), c.b);
    let delta = maxVal - minVal;
    
    var h = 0.0;
    var s = 0.0;
    var l = (maxVal + minVal) / 2.0;
    
    if (delta > 0.0) {
        s = delta / (1.0 - abs(2.0 * l - 1.0));
        if (maxVal == c.r) {
            h = fmod((c.g - c.b) / delta, 6.0);
        } else if (maxVal == c.g) {
            h = (c.b - c.r) / delta + 2.0;
        } else {
            h = (c.r - c.g) / delta + 4.0;
        }
        h = h / 6.0;
    }
    return vec3<f32>(h, s, l);
}

fn hue2rgb(p: f32, q: f32, t: f32) -> f32 {
    var t2 = t;
    if (t2 < 0.0) { t2 += 1.0; }
    if (t2 > 1.0) { t2 -= 1.0; }
    if (t2 < 1.0/6.0) { return p + (q - p) * 6.0 * t2; }
    if (t2 < 1.0/2.0) { return q; }
    if (t2 < 2.0/3.0) { return p + (q - p) * (2.0/3.0 - t2) * 6.0; }
    return p;
}

fn hsl2rgb(c: vec3<f32>) -> vec3<f32> {
    var h = c.x;
    var s = c.y;
    var l = c.z;
    if (s == 0.0) { return vec3<f32>(l); }
    let q = select(l * (1.0 + s), l + s - l * s, l < 0.5);
    var p = 2.0 * l - q;
    return vec3<f32>(
        hue2rgb(p, q, h + 1.0/3.0),
        hue2rgb(p, q, h),
        hue2rgb(p, q, h - 1.0/3.0)
    );
}

// ---------------------------------------------------------------
//  Main Compute
// ---------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }
    var uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // -----------------------------------------------------------------
    //  1️⃣  Parameters
    // -----------------------------------------------------------------
    // A mirror fan only closes for an integer count (a fractional count left a seam at the atan2 cut).
    let segments    = max(2.0, round(u.zoom_params.x * 14.0 + 2.0));
    // grokcf1 UPGRADE: bass/mids torque the rotation and spiral engine
    // directly (instead of the warp channel gemini uses), so beats visibly
    // spin the mirror.
    let rotSpeed    = (u.zoom_params.y * 0.4 - 0.2) * (1.0 + bass * 0.8); // Allows reverse rotation
    let spiralStr   = u.zoom_params.z * 3.0 * (1.0 + mids * 0.5);
    let trails      = u.zoom_params.w;
    let hueShift    = 1.0;
    let aberration  = 0.015;
    let centerOsc   = 0.2;
    let warpPower   = 0.4;
    let pointerUV   = u.zoom_config.yz;
    let pointerHeld = clamp(u.zoom_config.w, 0.0, 1.0);

    var center = vec2<f32>(0.5, 0.5) + vec2<f32>(sin(time * 0.3), cos(time * 0.4)) * centerOsc;
    
    // -----------------------------------------------------------------
    //  2️⃣  Depth-Aware & Warped Coordinates
    // -----------------------------------------------------------------
    let staticDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = 1.0 + (1.0 - staticDepth) * 2.5;
    
    let toPixel = uv - center;
    var r = length(toPixel);
    var a = atan2(toPixel.y, toPixel.x);

    // ✨ grokcf1 UPGRADE: Add a time-based warping field
    let warpAngle = time * 0.15;
    let warpVec = vec2<f32>(cos(warpAngle), sin(warpAngle));
    let warp = noise(uv * 4.0 + warpVec * time * 0.2) * warpPower * r;
    r = r + warp * 0.5;
    a = a + warp;

    // -----------------------------------------------------------------
    //  3️⃣  Enhanced Kaleidoscope Logic
    // -----------------------------------------------------------------
    // ✨ grokcf1 UPGRADE: More organic spiral and rotation
    let spiral = r * spiralStr * (sin(time * 0.2 + r * 5.0) * 0.5 + 0.5);
    let rotation = time * rotSpeed * depthFactor;

    // Held-pointer spiral grab: holding the pointer biases the spiral's
    // direction/rate toward the cursor's own angle from the fold center, a
    // "grab and twist" distinct from gemini's warp-epicenter pull.
    let pointerAngle = atan2(pointerUV.y - center.y, pointerUV.x - center.x);
    let grabSpiral = pointerHeld * sin(pointerAngle - a) * 1.4;

    // 2026-11 Idea 2: log-spiral twist. HEAD's spiral is linear in r (Archimedean); a logarithmic term
    // makes the arms self-similar toward the centre.
    let logSpiral = 0.12 * spiralStr * log(r + 0.05) * sin(time * 0.2 + 1.0);
    // 2026-11 Idea 1: the second object chamber starts from the same angle but turns the other way.
    let chamberAngle = a - 0.7 * (rotation + spiral) + 1.3;

    a = a + rotation + spiral + grabSpiral + logSpiral;
    
    let segmentAngle = 2.0 * PI / segments;
    a = fmod(a, segmentAngle);
    if (a < 0.0) { a += segmentAngle; }
    if (a > segmentAngle * 0.5) {
        a = segmentAngle - a;
    }
    
    // ✨ grokcf1 UPGRADE: Pulsing zoom effect with more character
    let pulse = sin(time * 1.2 + r * 10.0) * 0.1;
    let r_pulse = r - log(r + 0.1) * (0.4 + pulse) * sin(time * 0.8);
    let sampleUV = center + vec2<f32>(cos(a), sin(a)) * r_pulse;

    // -----------------------------------------------------------------
    //  4️⃣  Chromatic Separation
    // -----------------------------------------------------------------
    let chromaOffset = aberration * (1.0 + spiralStr * 0.5);
    let uvR = rotate(sampleUV - center, chromaOffset * (1.0 + sin(time * 0.5) * 0.2)) + center;
    let uvG = sampleUV;
    let uvB = rotate(sampleUV - center, -chromaOffset * (1.0 + cos(time * 0.5) * 0.2)) + center;
    
    let colR = textureSampleLevel(readTexture, u_sampler, clamp(uvR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, clamp(uvG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, clamp(uvB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    var color = vec3<f32>(colR, colG, colB);

    // 2026-11 Idea 1: second object chamber. A real scope's loose objects tumble in a chamber that
    // turns independently of the mirrors; a second tap through the same fold with a counter-rotating
    // angle is screen-blended in at 50 %.
    let segAngle2 = 2.0 * PI / segments;
    let a2 = foldAngle(chamberAngle, segAngle2);
    let chamberUV = center + vec2<f32>(cos(a2), sin(a2)) * r_pulse;
    let chamber2 = textureSampleLevel(readTexture, u_sampler, clamp(chamberUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    color = vec3<f32>(1.0) - (vec3<f32>(1.0) - color) * (vec3<f32>(1.0) - chamber2 * 0.5);
    
    // -----------------------------------------------------------------
    //  5️⃣  Evolved Psychedelic Color Grading
    // -----------------------------------------------------------------
    var hsl = rgb2hsl(color);
    // ✨ grokcf1 UPGRADE: Time-driven hue evolution + radius shift
    let timeHue = sin(time * 0.05) * 0.5;
    hsl.x = fract(hsl.x + timeHue + r * hueShift);
    hsl.y = min(hsl.y * 1.3, 1.0); // Slightly more saturation boost
    color = hsl2rgb(hsl);
    
    // -----------------------------------------------------------------
    //  6️⃣  Enhanced Feedback Trails
    // -----------------------------------------------------------------
    let prev = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0).rgb;
    let decay = 0.88 + (trails * 0.11); // Map 0..1 to 0.88..0.99
    
    // ✨ grokcf1 UPGRADE: Mix in a subtle noise shimmer into the feedback
    let shimmer = noise(uv * 10.0 + time) * 0.05;
    let feedback = max(color, prev * decay + shimmer);
    
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(feedback, 1.0));
    
    // -----------------------------------------------------------------
    //  7️⃣  Final Output
    // ---------------------------------------------------------------
    let finalCol = mix(color, feedback, 0.6); // Slightly more feedback visibility
    
    // Calculate luminance-based alpha
    let luma = dot(finalCol, vec3<f32>(0.299, 0.587, 0.114));
    // clamped: luma of the unbounded feedback can exceed 1, which pushed alpha above 1 at HEAD
    let alpha = clamp(mix(0.7, 1.0, luma), 0.0, 1.0);
    let finalAlpha = mix(alpha * 0.8, alpha, staticDepth);
    
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(acesToneMap(finalCol), finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(staticDepth, 0.0, 0.0, 0.0));
}
