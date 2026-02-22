// ---------------------------------------------------------------
//  Astral Kaleidoscope Gemini - An enhanced, multi-layered,
//  depth-aware, spiraling tunnel of light.
// ---------------------------------------------------------------

@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var historyBuf: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var unusedBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var historyTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_params: vec4<f32>,
  zoom_config: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Constants and Math Utilities
// ---------------------------------------------------------------
const PI: f32 = 3.14159265359;

fn fmod(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

fn rotate(v: vec2<f32>, a: f32) -> vec2<f32> {
    let s = sin(a);
    let c = cos(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
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
    let l = (maxVal + minVal) / 2.0;
    
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
    let h = c.x;
    let s = c.y;
    let l = c.z;
    if (s == 0.0) { return vec3<f32>(l); }
    let q = select(l * (1.0 + s), l + s - l * s, l < 0.5);
    let p = 2.0 * l - q;
    return vec3<f32>(
        hue2rgb(p, q, h + 1.0/3.0),
        hue2rgb(p, q, h),
        hue2rgb(p, q, h - 1.0/3.0)
    );
}

// ---------------------------------------------------------------
//  Main Compute
// ---------------------------------------------------------------
@compute @workgroup_size(8,8,1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    
    // -----------------------------------------------------------------
    //  1️⃣  Parameters
    // -----------------------------------------------------------------
    let segments    = max(2.0, u.zoom_params.x * 14.0 + 2.0);
    let rotSpeed    = u.zoom_params.y * 0.4 - 0.2; // Allows reverse rotation
    let spiralStr   = u.zoom_params.z * 3.0;
    let trails      = u.zoom_params.w;
    let hueShift    = u.zoom_config.x * 2.0;
    let aberration  = u.zoom_config.y * 0.03;
    let centerOsc   = u.zoom_config.z * 0.2;
    let warpPower   = u.zoom_config.w * 0.8; // New GEMINI parameter

    let center = vec2<f32>(0.5, 0.5) + vec2<f32>(sin(time * 0.3), cos(time * 0.4)) * centerOsc;
    
    // -----------------------------------------------------------------
    //  2️⃣  Depth-Aware & Warped Coordinates
    // -----------------------------------------------------------------
    let staticDepth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    let depthFactor = 1.0 + (1.0 - staticDepth) * 2.5;
    
    let toPixel = uv - center;
    var r = length(toPixel);
    var a = atan2(toPixel.y, toPixel.x);

    // ✨ GEMINI UPGRADE: Add a time-based warping field
    let warpAngle = time * 0.15;
    let warpVec = vec2<f32>(cos(warpAngle), sin(warpAngle));
    let warp = noise(uv * 4.0 + warpVec * time * 0.2) * warpPower * r;
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
    
    let colR = textureSampleLevel(videoTex, videoSampler, clamp(uvR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let colG = textureSampleLevel(videoTex, videoSampler, clamp(uvG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let colB = textureSampleLevel(videoTex, videoSampler, clamp(uvB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    var color = vec3<f32>(colR, colG, colB);
    
    // -----------------------------------------------------------------
    //  5️⃣  Evolved Psychedelic Color Grading
    // -----------------------------------------------------------------
    var hsl = rgb2hsl(color);
    // ✨ GEMINI UPGRADE: Time-driven hue evolution + radius shift
    let timeHue = sin(time * 0.05) * 0.5;
    hsl.x = fract(hsl.x + timeHue + r * hueShift);
    hsl.s = min(hsl.s * 1.3, 1.0); // Slightly more saturation boost
    color = hsl2rgb(hsl);
    
    // -----------------------------------------------------------------
    //  6️⃣  Enhanced Feedback Trails
    // -----------------------------------------------------------------
    let prev = textureSampleLevel(historyTex, depthSampler, uv, 0.0).rgb;
    let decay = 0.88 + (trails * 0.11); // Map 0..1 to 0.88..0.99
    
    // ✨ GEMINI UPGRADE: Mix in a subtle noise shimmer into the feedback
    let shimmer = noise(uv * 10.0 + time) * 0.05;
    let feedback = max(color, prev * decay + shimmer);
    
    textureStore(historyBuf, vec2<i32>(gid.xy), vec4<f32>(feedback, 1.0));
    
    // -----------------------------------------------------------------
    //  7️⃣  Final Output
    // ---------------------------------------------------------------
    let finalCol = mix(color, feedback, 0.6); // Slightly more feedback visibility
    
    textureStore(outTex, vec2<i32>(gid.xy), vec4<f32>(finalCol, 1.0));
    textureStore(outDepth, vec2<i32>(gid.xy), vec4<f32>(staticDepth, 0.0, 0.0, 0.0));
}
