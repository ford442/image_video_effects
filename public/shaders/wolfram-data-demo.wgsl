// ═══════════════════════════════════════════════════════════════════════════════
//  Wolfram Data Demo - Scientific constants and mathematical functions
//  Category: generative
//  Features: procedural, mathematical, scientific, mouse-driven, audio-reactive, upgraded-rgba
//  Data Source: Wolfram Alpha API
//  Upgraded: 2026-11-08
//  Ideas: parastichy arms (Fibonacci 13/21 spiral families lit in phyllotaxis); Rayleigh
//         limit twin (second Airy source at the cursor, rings fuse at 1.22 r); golden
//         rectangle tiling (nested φ-rectangle edges behind the Fibonacci spiral)
//  Rescues: phyllotaxis centred at uv=-0.5 (off-screen, black); mode=1.0 fell to passthrough
//  A packing: display RGB (ACES), alpha = pattern coverage blended with input alpha
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══════════════════════════════════════════════════════════════════════════════
//  Wolfram Mathematical Constants
// ═══════════════════════════════════════════════════════════════════════════════

const PHI: f32 = 1.6180339887;           // Golden ratio
const INV_PHI: f32 = 0.6180339887;       // Inverse golden ratio
const SQRT_2: f32 = 1.4142135624;
const SQRT_3: f32 = 1.7320508076;
const E: f32 = 2.7182818285;
const PI: f32 = 3.1415926536;
const TAU: f32 = 6.2831853072;           // 2*PI

// Golden angle (radians) - 137.5 degrees - from Wolfram
const GOLDEN_ANGLE: f32 = 2.3999632297;

// Bessel J0 first zero - for Airy disk patterns
const BESSEL_J0_ZERO: f32 = 2.4048255577;

// ═══════════════════════════════════════════════════════════════════════════════
//  Wolfram Physical Constants
// ═══════════════════════════════════════════════════════════════════════════════

const G_ACCEL: f32 = 9.81;               // Gravitational acceleration
const C: f32 = 299792458.0;              // Speed of light
const PLANCK: f32 = 6.62607015e-34;      // Planck constant
const FINE_STRUCTURE: f32 = 0.0072973525693;

// Rayleigh scattering coefficients (Wolfram data for Earth atmosphere)
const RAYLEIGH_SCATTERING: vec3<f32> = vec3<f32>(
    5.804542996261093e-6,
    1.3562911419845635e-5,
    3.0265902468824876e-5
);

// ═══════════════════════════════════════════════════════════════════════════════
//  Prime numbers (from Wolfram) for hashing
// ═══════════════════════════════════════════════════════════════════════════════

const HASH_PRIME_1: i32 = 73856093;
const HASH_PRIME_2: i32 = 19349663;
const HASH_PRIME_3: i32 = 83492791;

// ═══════════════════════════════════════════════════════════════════════════════
//  Mathematical Functions using Wolfram-derived constants
// ═══════════════════════════════════════════════════════════════════════════════

// Bessel J0 function approximation (from Wolfram numerical recipes)
fn bessel_j0(x: f32) -> f32 {
    let ax = abs(x);
    var z: f32;
    var xx: f32;
    var y: f32;
    var ans: f32;
    var ans1: f32;
    var ans2: f32;
    
    if (ax < 8.0) {
        y = x * x;
        ans1 = 57568490574.0 + y * (-13362590354.0 + y * (651619640.7 + y * (-11214424.18 + y * (77392.33017 + y * (-184.9052456)))));
        ans2 = 57568490411.0 + y * (1029532985.0 + y * (9494680.718 + y * (59272.64853 + y * (267.8532712 + y * 1.0))));
        ans = ans1 / ans2;
    } else {
        z = 8.0 / ax;
        y = z * z;
        xx = ax - 0.785398164;
        ans1 = 1.0 + y * (-0.1098628627e-2 + y * (0.2734510407e-4 + y * (-0.2073370639e-5 + y * 0.2093887211e-6)));
        ans2 = -0.1562499995e-1 + y * (0.1430488765e-3 + y * (-0.6911147651e-5 + y * (0.7621095161e-6 - y * 0.934945152e-7)));
        ans = sqrt(0.636619772 / ax) * (cos(xx) * ans1 - z * sin(xx) * ans2);
    }
    return ans;
}

// Phyllotaxis pattern using golden angle from Wolfram
// Returns (seed coverage, parastichy-arm coverage).
fn phyllotaxis(uv: vec2<f32>, n: f32, scale: f32, seedR: f32, armPhase: f32) -> vec2<f32> {
    var value: f32 = 0.0;
    var arms: f32 = 0.0;
    for (var i: f32 = 1.0; i <= n; i = i + 1.0) {
        let r: f32 = scale * sqrt(i) * 0.01;
        let theta: f32 = i * GOLDEN_ANGLE;
        let pos = vec2<f32>(r * cos(theta), r * sin(theta));
        let dist = length(uv - pos);
        let seed = smoothstep(seedR, 0.0, dist);
        value = value + seed;
        // Idea 1: parastichy arms — seeds sharing i mod 21 (clockwise) or i mod 13
        // (counter-clockwise) form the visible Fibonacci spirals; one arm of each family
        // is lit and the lit arm rotates around the family over time.
        let a21 = f32(abs(i32(i) - i32(armPhase * 21.0)) % 21 == 0);
        let a13 = f32(abs(i32(i) - i32(armPhase * 13.0)) % 13 == 0);
        arms = arms + seed * max(a21, a13 * 0.6);
    }
    return vec2<f32>(value, arms);
}

// Blackbody color temperature (Tanner Helland fit to CIE 1964 blackbody data).
// Rescue: the old cubic fit returned g≈13 below 6600 K and g<0, r≈0 above it, so every
// temperature was either clamped yellow-white or pure blue.
fn blackbody(t: f32) -> vec3<f32> {
    let T = clamp(t, 1000.0, 40000.0) / 100.0;
    var r = 1.0;
    var g: f32;
    var b = 1.0;
    if (T <= 66.0) {
        g = (99.4708025861 * log(T) - 161.1195681661) / 255.0;
        if (T <= 19.0) { b = 0.0; } else { b = (138.5177312231 * log(T - 10.0) - 305.0447927307) / 255.0; }
    } else {
        r = 329.698727446 * pow(T - 60.0, -0.1332047592) / 255.0;
        g = 288.1221695283 * pow(T - 60.0, -0.0755148492) / 255.0;
    }
    return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Spherical harmonic Y(2,0) for planet/cloud detail
fn spherical_harmonic_20(theta: f32, phi: f32) -> f32 {
    return 0.3153915653 * (3.0 * cos(theta) * cos(theta) - 1.0);
}

// Airy disk pattern (diffraction) using Bessel J0
fn airy_disk(uv: vec2<f32>, center: vec2<f32>, radius: f32) -> f32 {
    let dist = length(uv - center);
    let x = BESSEL_J0_ZERO * dist / radius;
    if (x < 0.01) {
        return 1.0;
    }
    let j0 = bessel_j0(x);
    return j0 * j0;
}

// Idea 3: golden rectangle tiling — the classic construction behind the golden spiral:
// each step removes a square from a φ-rectangle, the remainder is the next φ-rectangle.
fn golden_tiling(p: vec2<f32>, lw: f32) -> f32 {
    var q = p;              // rectangle-local, size (PHI, 1) at origin corner
    var w = PHI; var h = 1.0;
    var line = 0.0;
    var k = 1.0;
    for (var i = 0; i < 9; i = i + 1) {
        if (q.x < 0.0 || q.y < 0.0 || q.x > w || q.y > h) { break; }
        // edge of the square cut at x = h
        line = max(line, smoothstep(lw * k, 0.0, abs(q.x - h)) * k);
        // remainder rectangle (w-h) x h, rotate 90° so it is again landscape
        q = vec2<f32>(h - q.y, q.x - h);
        let nw = h; h = w - h; w = nw;
        k = k * 0.85;
    }
    return line;
}

// Fibonacci spiral using Wolfram's golden ratio data
fn fibonacci_spiral(uv: vec2<f32>, time: f32) -> f32 {
    let centered = uv - 0.5;
    let angle = atan2(centered.y, centered.x);
    let radius = length(centered);
    
    // Logarithmic spiral: r = a * e^(b*theta)
    // where b = ln(phi) / (pi/2) for golden spiral
    let b = log(PHI) / (PI / 2.0);
    let spiral = log(radius + 0.001) / b - angle - time;
    let spiral_mod = fract(spiral / TAU);
    
    return smoothstep(0.1, 0.0, abs(spiral_mod - 0.5)) * smoothstep(0.5, 0.0, radius);
}

// Atmospheric scattering simulation using Wolfram Rayleigh data
fn atmospheric_scatter(uv: vec2<f32>, sun_pos: vec2<f32>) -> vec3<f32> {
    let dist = length(uv - sun_pos);
    let cos_theta = dot(normalize(uv - 0.5), normalize(sun_pos - 0.5));
    
    // Rayleigh phase function
    let phase = 0.0596831 * (1.0 + cos_theta * cos_theta);
    
    // Optical depth approximation
    let optical_depth = exp(-dist * 3.0);
    
    // Apply Rayleigh scattering coefficients
    return vec3<f32>(
        RAYLEIGH_SCATTERING.r * phase * optical_depth * 100000.0,
        RAYLEIGH_SCATTERING.g * phase * optical_depth * 100000.0,
        RAYLEIGH_SCATTERING.b * phase * optical_depth * 100000.0
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Main Shader
// ═══════════════════════════════════════════════════════════════════════════════

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let currentTime = u.config.x;
    let params = u.zoom_params;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    
    // Sample input
    let input_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Mode selection based on param1 (slider max 1.0 now stays on Atmosphere)
    let mode = min(i32(params.x * 4.0), 3);
    var coverage = 0.0;
    
    var output_color = vec3<f32>(0.0);
    
    switch(mode) {
        case 0: {
            // Mode 0: Phyllotaxis pattern (golden angle)
            let scale = 1.0 + params.y * 2.0;
            let n = 50.0 + params.z * 200.0;
            let uvA = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5);
            let ph = phyllotaxis(uvA, n, scale, 0.011 * scale * (1.0 + bass * 0.4), fract(currentTime * 0.08 * (1.0 + mids)));
            let temp = 3000.0 + params.w * 7000.0;
            // lit arms burn cooler (amber) and brighter than the seed head
            output_color = blackbody(temp) * (ph.x - ph.y) * 0.75 + blackbody(temp - 3500.0) * ph.y * 1.8;
            coverage = clamp(ph.x, 0.0, 1.0);
        }
        case 1: {
            // Mode 1: Airy disk diffraction pattern
            let sun_pos = vec2<f32>(0.5 + sin(currentTime * 0.3) * 0.3, 0.5);
            let radius = 0.1 + params.y * 0.3;
            let ax = vec2<f32>(aspect, 1.0);
            let airy = airy_disk(uv * ax, sun_pos * ax, radius);
            let temp = 4000.0 + params.z * 6000.0;
            // Idea 2: Rayleigh-limit twin — a second point source at the cursor. When the
            // pair is closer than the Rayleigh criterion (first dark ring, ~1.22 r here
            // with the J0 profile scaled to BESSEL_J0_ZERO) the two discs fuse into one blob.
            let twin = airy_disk(uv * ax, mouse * ax, radius) * (0.7 + bass * 0.5);
            let sep = length(mouse - sun_pos) / radius;
            let resolved = smoothstep(0.8, 1.22, sep);
            // unresolved: warmer merged glow; resolved: twin keeps a cooler temperature
            output_color = blackbody(temp) * airy * (1.0 + bass * 0.3)
                         + blackbody(mix(temp - 1500.0, temp + 3000.0, resolved)) * twin;
            coverage = clamp(airy + twin, 0.0, 1.0);
        }
        case 2: {
            // Mode 2: Fibonacci spiral
            let sp = fibonacci_spiral(uv, currentTime * 0.5 * (1.0 + mids * 0.5));
            let temp = 2500.0 + params.y * 8000.0;
            // golden tiling whose pole (1.1708, 0.2764) sits on the spiral's pole
            let tp = vec2<f32>((uv.x - 0.5) * aspect, 0.5 - uv.y) / 0.6 + vec2<f32>(1.1708, 0.2764);
            let tiles = golden_tiling(tp, 0.012 * (1.0 + bass * 0.5));
            output_color = sp * blackbody(temp) + tiles * blackbody(temp + 3000.0) * 0.45;
            coverage = clamp(sp + tiles * 0.5, 0.0, 1.0);
        }
        case 3: {
            // Mode 3: Atmospheric scattering
            let sun_pos = vec2<f32>(0.5 + sin(currentTime * 0.2) * 0.4, 0.3 + cos(currentTime * 0.15) * 0.2);
            output_color = atmospheric_scatter(uv, sun_pos);
            output_color = output_color * (1.0 + bass * 0.3) + blackbody(5778.0) * 0.1; // Sun color
            coverage = clamp(dot(output_color, vec3<f32>(0.33)), 0.0, 1.0);
        }
        default: {
            output_color = input_color.rgb;
            coverage = 1.0;
        }
    }
    
    // Blend with input
    let blend = params.w;
    let mapped = output_color * 1.25; // pre-exposure so ACES keeps 1.0 near white
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    let toned = clamp((mapped * (a * mapped + b)) / (mapped * (c * mapped + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
    let final_color = mix(input_color.rgb, toned, blend);
    let alpha = mix(input_color.a, max(coverage, 0.15), blend);
    
    // Write output
    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(final_color, alpha));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
