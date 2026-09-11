// ═══════════════════════════════════════════════════════════════════
//  astral-kaleidoscope-gemini
//  Category: psychedelic
//  Features: upgraded-rgba, depth-aware, mouse-driven, audio-reactive
//  Upgraded: 2026-09-11
//  Ideas: bass/treble-driven warp swell; held-pointer becomes a second warp epicenter
//  A packing: display RGBA feedback trail (unchanged)
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture:   texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,       // x=time, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,       // x=segments, y=rotationSpeed, z=spiralStrength, w=trails
  ripples:     array<vec4<f32>, 50>,
};

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
    var sat = c.y;
    var l = c.z;
    if (sat == 0.0) { return vec3<f32>(l); }
    let q = select(l * (1.0 + sat), l + sat - l * sat, l < 0.5);
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
    let segments    = max(2.0, u.zoom_params.x * 14.0 + 2.0);
    let rotSpeed    = u.zoom_params.y * 0.4 - 0.2; // Allows reverse rotation
    let spiralStr   = u.zoom_params.z * 3.0;
    let trails      = u.zoom_params.w;
    let hueShift    = 1.0;
    let aberration  = 0.015;
    let centerOsc   = 0.2;
    let pointerUV   = u.zoom_config.yz;
    let pointerHeld = clamp(u.zoom_config.w, 0.0, 1.0);
    // GEMINI parameter: warp field strength now genuinely breathes with the
    // track (bass swells it, treble speeds the scroll below) instead of the
    // silent mouse_down bit it read before the binding-layout fix.
    let warpPower   = 0.35 + bass * 0.75;

    var center = vec2<f32>(0.5, 0.5) + vec2<f32>(sin(time * 0.3), cos(time * 0.4)) * centerOsc;
    
    // -----------------------------------------------------------------
    //  2️⃣  Depth-Aware & Warped Coordinates
    // -----------------------------------------------------------------
    let staticDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = 1.0 + (1.0 - staticDepth) * 2.5;
    
    let toPixel = uv - center;
    var r = length(toPixel);
    var a = atan2(toPixel.y, toPixel.x);

    // ✨ GEMINI UPGRADE: Add a time-based warping field, sped up by treble
    let warpAngle = time * 0.15;
    let warpVec = vec2<f32>(cos(warpAngle), sin(warpAngle));
    let ambientWarp = noise(uv * 4.0 + warpVec * time * (0.2 + treble * 0.5)) * warpPower;

    // Pointer warp epicenter: a held pointer becomes a second, stronger warp
    // origin, pulling the noise field toward the cursor instead of only the
    // ambient time-driven swirl above.
    let toPointer = uv - pointerUV;
    let pointerWarp = noise(uv * 6.0 + toPointer * 12.0 + time * 0.6) * pointerHeld * (0.5 + warpPower);

    let warp = (ambientWarp + pointerWarp) * r;
    r = r + warp * 0.5;
    a = a + warp;

    // -----------------------------------------------------------------
    //  3️⃣  Enhanced Kaleidoscope Logic
    // -----------------------------------------------------------------
    // ✨ GEMINI UPGRADE: More organic spiral and rotation
    let spiral = r * spiralStr * (sin(time * 0.2 + r * 5.0) * 0.5 + 0.5);
    let rotation = time * rotSpeed * depthFactor;
    a = a + rotation + spiral;
    
    let segmentAngle = 2.0 * PI / segments;
    a = fmod(a, segmentAngle);
    if (a < 0.0) { a += segmentAngle; }
    if (a > segmentAngle * 0.5) {
        a = segmentAngle - a;
    }
    
    // ✨ GEMINI UPGRADE: Pulsing zoom effect with more character
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
    
    // -----------------------------------------------------------------
    //  5️⃣  Evolved Psychedelic Color Grading
    // -----------------------------------------------------------------
    var hsl = rgb2hsl(color);
    // ✨ GEMINI UPGRADE: Time-driven hue evolution + radius shift
    let timeHue = sin(time * 0.05) * 0.5;
    hsl.x = fract(hsl.x + timeHue + r * hueShift);
    hsl.y = min(hsl.y * 1.3, 1.0); // Slightly more saturation boost
    color = hsl2rgb(hsl);
    
    // -----------------------------------------------------------------
    //  6️⃣  Enhanced Feedback Trails
    // -----------------------------------------------------------------
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;
    let decay = 0.88 + (trails * 0.11); // Map 0..1 to 0.88..0.99
    
    // ✨ GEMINI UPGRADE: Mix in a subtle noise shimmer into the feedback
    let shimmer = noise(uv * 10.0 + time) * 0.05;
    let feedback = max(color, prev * decay + shimmer);
    
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(feedback, 1.0));
    
    // -----------------------------------------------------------------
    //  7️⃣  Final Output
    // ---------------------------------------------------------------
    let finalCol = mix(color, feedback, 0.6); // Slightly more feedback visibility
    
    // Calculate luminance-based alpha
    let luma = dot(finalCol, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.7, 1.0, luma);
    let finalAlpha = mix(alpha * 0.8, alpha, staticDepth);
    
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(acesToneMap(finalCol), finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(staticDepth, 0.0, 0.0, 0.0));
}
