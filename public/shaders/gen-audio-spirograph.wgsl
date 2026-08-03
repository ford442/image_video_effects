// ═══════════════════════════════════════════════════════════════════
//  Audio Spirograph
//  Category: generative
//  Features: audio-reactive, procedural, epitrochoid curves
//  Complexity: Medium
//  Upgraded: 2026-08-03 (Batch 34)
//  upgraded-rgba
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Hash function
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Epitrochoid calculation (spirograph curve)
fn epitrochoid(t: f32, R: f32, r: f32, d: f32) -> vec2<f32> {
    let k = R / r;
    let x = (R + r) * cos(t) - d * cos((k + 1.0) * t);
    let y = (R + r) * sin(t) - d * sin((k + 1.0) * t);
    return vec2<f32>(x, y);
}

// Hypotrochoid calculation (inner spirograph)
fn hypotrochoid(t: f32, R: f32, r: f32, d: f32) -> vec2<f32> {
    let k = R / r;
    let x = (R - r) * cos(t) + d * cos((k - 1.0) * t);
    let y = (R - r) * sin(t) - d * sin((k - 1.0) * t);
    return vec2<f32>(x, y);
}

// Distance to line segment
fn distToSegment(uv: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = uv - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
    return length(pa - ba * h);
}

// HSL to RGB
fn hsl2rgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    let x = c * (1.0 - abs(fract(h * 6.0) * 2.0 - 1.0));
    let m = l - c * 0.5;
    
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    
    if (h < 1.0/6.0) { r = c; g = x; }
    else if (h < 2.0/6.0) { r = x; g = c; }
    else if (h < 3.0/6.0) { g = c; b = x; }
    else if (h < 4.0/6.0) { g = x; b = c; }
    else if (h < 5.0/6.0) { r = x; b = c; }
    else { r = c; b = x; }
    
    return vec3<f32>(r + m, g + m, b + m);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }
    let resolution = vec2<f32>(dims);
    var uv = (vec2<f32>(global_id.xy) + vec2<f32>(0.5) - resolution * 0.5) / min(resolution.x, resolution.y);
    let t = u.config.x;
    
    // Parameters - safe randomization
    let baseFreq = mix(0.5, 3.0, u.zoom_params.x);
    let audioReactivity = u.zoom_params.y; // 0 to 1
    let trailLength = mix(0.3, 0.95, u.zoom_params.z);
    let lineThickness = mix(0.001, 0.01, u.zoom_params.w);
    
    let audio = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioMod = 1.0 + audio * audioReactivity * 2.0;

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouseUv = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { mouseUv = rawMouse; mouseVelocity = vec2<f32>(0.0); }
    let springDt = select(0.016, clamp(t - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let springOmega = 8.0;
    mouseVelocity += ((rawMouse - mouseUv) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
    mouseUv += mouseVelocity * springDt;
    if (global_id.x == 0u && global_id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = mouseUv.x; extraBuffer[134] = mouseUv.y;
        extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = t;
    }
    let mouse = (mouseUv - vec2<f32>(0.5)) * vec2<f32>(resolution.x / resolution.y, 1.0);
    let mouseDelta = uv - mouse;
    let mouseLens = exp(-dot(mouseDelta, mouseDelta) * 18.0) * mix(0.04, 0.18, select(0.0, 1.0, u.zoom_config.w > 0.5));
    uv -= mouseDelta * mouseLens;
    
    // Background accumulation for trails
    let prevCol = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
    
    // Multiple harmonics - musical ratios
    let ratios = array<f32, 5>(1.0, 3.0/2.0, 4.0/3.0, 5.0/4.0, 5.0/3.0);
    let harmonics = array<f32, 5>(1.0, 2.0, 3.0, 4.0, 5.0);
    
    var minDist = 1000.0;
    var curveColor = vec3<f32>(0.0);
    var totalIntensity = 0.0;
    
    // Generate multiple spirograph curves
    for (var i: i32 = 0; i < 5; i++) {
        let ratio = ratios[i];
        let harmonic = harmonics[i];
        
        // Spirograph parameters
        let R = 0.3 * (1.0 + f32(i) * 0.1);
        let r = R / (ratio * harmonic * baseFreq);
        let d = r * 0.8 * audioMod;
        
        // Animation speed varies by harmonic
        let speed = 0.5 + f32(i) * 0.1;
        let time = t * speed;
        let sweep = 6.28318 * mix(0.2, 1.0, trailLength);
        var prevPos = rot(t * 0.08 + f32(i) * 0.16) * epitrochoid(time, R, r, d);
        var dist = 1000.0;
        var segmentFade = 1.0;
        for (var j: i32 = 1; j <= 12; j = j + 1) {
            let jf = f32(j) / 12.0;
            let pos = rot(t * 0.08 + f32(i) * 0.16) * epitrochoid(time - sweep * jf, R, r, d);
            let segDist = distToSegment(uv, prevPos, pos);
            if (segDist < dist) { dist = segDist; segmentFade = 1.0 - jf * 0.65; }
            prevPos = pos;
        }
        
        // Color based on harmonic
        let hue = fract(f32(i) * 0.2 + t * 0.05);
        let sat = 0.7 + audio * 0.3;
        let light = 0.5 + audio * 0.3;
        let col = hsl2rgb(hue, sat, light);
        
        // Accumulate minimum distance with intensity
        let intensity = 1.0 / (1.0 + f32(i) * 0.5);
        if (dist < minDist) {
            minDist = dist;
            curveColor = col * intensity * segmentFade;
            totalIntensity = intensity * segmentFade;
        }
    }
    
    // Add secondary harmonics (hypotrochoids)
    for (var i: i32 = 0; i < 3; i++) {
        let ratio = ratios[i + 2];
        let R = 0.25 * audioMod;
        let r = R / ratio;
        let d = r * 0.6;
        
        let time = -t * (0.3 + f32(i) * 0.1);
        let sweep = 6.28318 * mix(0.2, 0.9, trailLength);
        var prevPos = rot(-t * 0.06) * hypotrochoid(time, R, r, d);
        var dist = 1000.0;
        var segmentFade = 1.0;
        for (var j: i32 = 1; j <= 10; j = j + 1) {
            let jf = f32(j) / 10.0;
            let pos = rot(-t * 0.06) * hypotrochoid(time - sweep * jf, R, r, d);
            let segDist = distToSegment(uv, prevPos, pos);
            if (segDist < dist) { dist = segDist; segmentFade = 1.0 - jf * 0.6; }
            prevPos = pos;
        }
        let hue = fract(0.5 + f32(i) * 0.15 - t * 0.03);
        let col = hsl2rgb(hue, 0.8, 0.6);
        
        if (dist < minDist) {
            minDist = dist;
            curveColor = col * 0.7 * segmentFade;
            totalIntensity = 0.7 * segmentFade;
        }
    }
    
    // Create glow effect
    let glow = smoothstep(lineThickness * 5.0, lineThickness, minDist);
    let core = smoothstep(lineThickness * 2.0, 0.0, minDist);
    
    // Final color
    var col = curveColor * glow * (1.0 + mids * 0.35) + vec3<f32>(1.0) * core * (0.45 + treble * 0.35);

    let uv01 = (vec2<f32>(global_id.xy) + vec2<f32>(0.5)) / resolution;
    var clickChime = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = t - ripple.z;
        if (age >= 0.0 && age < 1.7) {
            let delta = (uv01 - ripple.xy) * vec2<f32>(resolution.x / resolution.y, 1.0);
            let shell = exp(-abs(length(delta) - age * 0.27) * 74.0) * exp(-age * 1.8);
            clickChime = max(clickChime, shell);
        }
    }
    col += vec3<f32>(0.35, 0.75, 1.2) * clickChime * (0.65 + treble * 0.3);
    
    // Add trail accumulation
    col = col + clamp(prevCol, vec3<f32>(0.0), vec3<f32>(1.2)) * trailLength * 0.78;
    
    // Vignette
    let vignette = clamp(1.0 - length(uv) * 0.8, 0.0, 1.0);
    col = col * vignette;
    
    let coord = vec2<i32>(global_id.xy);
    let history = clamp(max(col, vec3<f32>(0.0)) * 0.94, vec3<f32>(0.0), vec3<f32>(1.25));
    let coverage = clamp(glow * totalIntensity + core * 0.55 + clickChime * 0.2, 0.0, 1.0);
    textureStore(dataTextureA, coord, vec4<f32>(history, coverage));
    let display = acesToneMap(history * 1.08);
    let alpha = clamp(coverage, 0.0, 0.96);
    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(coverage, 0.0, 0.0, 0.0));
}
