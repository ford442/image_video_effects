// ---------------------------------------------------------------
//  Astral Kaleidoscope - A depth-aware, spiraling tunnel of light.
//  Uses depth to separate rotation speeds and creates trippy
//  chromatic trails with feedback loop effects.
// ---------------------------------------------------------------

@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

// Using the persistence buffer for "light trails"
@group(0) @binding(7) var historyBuf: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var unusedBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var historyTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_params: vec4<f32>,       // x=segments, y=rotationSpeed, z=spiralStrength, w=trailPersistence
  zoom_config: vec4<f32>,       // x=colorShift, y=aberration, z=centerOsc, w=pulsePower
  ripples:     array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Constants and Math Utilities
// ---------------------------------------------------------------
const PI: f32 = 3.14159265359;

// Float modulo function
fn fmod(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

// Rotate a vector by an angle
fn rotate(v: vec2<f32>, a: f32) -> vec2<f32> {
    let s = sin(a);
    let c = cos(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

// Convert RGB to HSL for color shifting
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
            var offset = 0.0;
            if (c.g < c.b) { offset = 6.0; }
            h = (c.g - c.b) / delta + offset;
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
    if (t2 < 0.0) { t2 = t2 + 1.0; }
    if (t2 > 1.0) { t2 = t2 - 1.0; }
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
    
    var q = l + s - l * s;
    if (l < 0.5) { q = l * (1.0 + s); }
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
    let dimsI = textureDimensions(videoTex);
    let dims = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) {
        return;
    }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    
    // -----------------------------------------------------------------
    //  1️⃣  Parameters
    // -----------------------------------------------------------------
    let segments    = max(3.0, u.zoom_params.x * 12.0 + 3.0);  // 3 to 15 mirrors
    let rotSpeed    = u.zoom_params.y * 0.5;
    let spiralStr   = u.zoom_params.z * 2.0;
    let trails      = u.zoom_params.w;                         // 0.0 to 1.0
    let hueShift    = u.zoom_config.x;
    let aberration  = u.zoom_config.y * 0.02;                  // 0 to 0.02
    let centerOsc   = u.zoom_config.z * 0.15;                  // center oscillation
    let pulsePower  = u.zoom_config.w * 0.5 + 0.5;            // 0.5 to 1.0
    
    // Dynamic Center point (oscillates over time)
    let center = vec2<f32>(0.5, 0.5) + vec2<f32>(sin(time * 0.3), cos(time * 0.4)) * centerOsc;
    
    // -----------------------------------------------------------------
    //  2️⃣  Depth-Aware Coordinates
    // -----------------------------------------------------------------
    let staticDepth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    
    // Create parallax effect: Foreground spins faster than background
    let depthFactor = 1.0 + (1.0 - staticDepth) * 2.0; 
    
    // Convert to Polar
    let toPixel = uv - center;
    var r = length(toPixel);
    var a = atan2(toPixel.y, toPixel.x);
    
    // -----------------------------------------------------------------
    //  3️⃣  Kaleidoscope Logic
    // -----------------------------------------------------------------
    // Add rotation based on time, radius (spiral), and depth
    let spiral = r * spiralStr * sin(time * 0.2);
    let rotation = time * rotSpeed * depthFactor;
    a = a + rotation + spiral;
    
    // Divide into segments using modulo
    let segmentAngle = 2.0 * PI / segments;
    a = fmod(a, segmentAngle);
    
    // Make sure angle is positive
    if (a < 0.0) { a = a + segmentAngle; }
    
    // Mirror effect: if we are in the second half of the segment, flip back
    if (a > segmentAngle * 0.5) {
        a = segmentAngle - a;
    }
    
    // Convert back to Cartesian with pulsing zoom effect
    let r_pulse = r - log(r + 0.1) * (pulsePower * sin(time));
    let sampleUV = center + vec2<f32>(cos(a), sin(a)) * r_pulse;

    // -----------------------------------------------------------------
    //  4️⃣  Chromatic Separation (The "Trippy" Part)
    // -----------------------------------------------------------------
    // Sample RGB at slightly different spatial offsets based on spiral intensity
    let chromaOffset = aberration * (1.0 + spiralStr);
    
    // Rotate sample coordinates slightly for each channel
    let uvR = rotate(sampleUV - center, chromaOffset) + center;
    let uvG = sampleUV;
    let uvB = rotate(sampleUV - center, -chromaOffset) + center;
    
    let colR = textureSampleLevel(videoTex, videoSampler, clamp(uvR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let colG = textureSampleLevel(videoTex, videoSampler, clamp(uvG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let colB = textureSampleLevel(videoTex, videoSampler, clamp(uvB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    
    var color = vec3<f32>(colR, colG, colB);
    
    // -----------------------------------------------------------------
    //  5️⃣  Psychedelic Color Grading
    // -----------------------------------------------------------------
    // Convert to HSL, shift Hue based on radius and time
    var hsl = rgb2hsl(color);
    hsl.x = fract(hsl.x + time * 0.1 + r * hueShift); // Rainbow ripple
    hsl.y = min(hsl.y * 1.2, 1.0); // Boost saturation
    color = hsl2rgb(hsl);
    
    // -----------------------------------------------------------------
    //  6️⃣  Trails / Feedback
    // -----------------------------------------------------------------
    let prev = textureSampleLevel(historyTex, depthSampler, uv, 0.0).rgb;
    
    // Create a feedback loop with configurable decay
    let decay = 0.9 + (trails * 0.09); // Map 0..1 to 0.90..0.99
    let feedback = max(color, prev * decay);
    
    // Store feedback in history buffer for next frame
    textureStore(historyBuf, gid.xy, vec4<f32>(feedback, 1.0));
    
    // -----------------------------------------------------------------
    //  7️⃣  Final Output
    // -----------------------------------------------------------------
    // Mix the feedback into the visual output for "smeared light" look
    let finalCol = mix(color, feedback, 0.5);
    
    textureStore(outTex, gid.xy, vec4<f32>(finalCol, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(staticDepth, 0.0, 0.0, 0.0));
}
