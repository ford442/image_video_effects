// ═══════════════════════════════════════════════════════════════════════════════
//  Wolfram Data Demo - Scientific constants and mathematical functions
//  Category: generative
//  Features: procedural, mathematical, scientific
//  Data Source: Wolfram Alpha API
// ═══════════════════════════════════════════════════════════════════════════════

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
fn phyllotaxis(uv: vec2<f32>, n: f32, scale: f32) -> f32 {
    var value: f32 = 0.0;
    for (var i: f32 = 1.0; i <= n; i = i + 1.0) {
        let r: f32 = scale * sqrt(i) * 0.01;
        let theta: f32 = i * GOLDEN_ANGLE;
        let pos = vec2<f32>(r * cos(theta), r * sin(theta));
        let dist = length(uv - pos + 0.5);
        value = value + smoothstep(0.05, 0.0, dist);
    }
    return value;
}

// Blackbody color temperature (Wolfram-derived polynomial)
fn blackbody(t: f32) -> vec3<f32> {
    let T = clamp(t, 1000.0, 40000.0);
    let T2 = T * T;
    let T3 = T2 * T;
    
    var r: f32;
    if (T < 6600.0) {
        r = 1.0;
    } else {
        r = 1.292936186062745 * pow(T/10000.0 - 0.6, 1.25);
    }
    
    var g: f32;
    if (T < 6600.0) {
        g = -4.59336e-11 * T3 + 6.3646e-7 * T2 + 0.0003198 * T - 0.02504;
    } else {
        g = -2.14574e-10 * T3 + 2.50735e-6 * T2 - 0.00950783 * T + 11.27;
    }
    
    var b: f32;
    if (T < 2000.0) {
        b = 0.0;
    } else if (T < 6600.0) {
        b = -2.3252e-14 * T3 + 4.64544e-10 * T2 - 3.15481e-5 * T + 0.5166;
    } else {
        b = 1.0;
    }
    
    return vec3<f32>(clamp(r, 0.0, 1.0), clamp(g, 0.0, 1.0), clamp(b, 0.0, 1.0));
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let currentTime = u.config.x;
    let params = u.zoom_params;
    
    // Sample input
    let input_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Mode selection based on param1
    let mode = i32(params.x * 4.0);
    
    var output_color = vec3<f32>(0.0);
    
    switch(mode) {
        case 0: {
            // Mode 0: Phyllotaxis pattern (golden angle)
            let scale = 1.0 + params.y * 2.0;
            let n = 50.0 + params.z * 200.0;
            let pattern = phyllotaxis(uv, n, scale);
            let temp = 3000.0 + params.w * 7000.0;
            output_color = blackbody(temp) * pattern;
        }
        case 1: {
            // Mode 1: Airy disk diffraction pattern
            let sun_pos = vec2<f32>(0.5 + sin(currentTime * 0.3) * 0.3, 0.5);
            let radius = 0.1 + params.y * 0.3;
            let airy = airy_disk(uv, sun_pos, radius);
            let temp = 4000.0 + params.z * 6000.0;
            output_color = blackbody(temp) * airy;
        }
        case 2: {
            // Mode 2: Fibonacci spiral
            output_color = vec3<f32>(fibonacci_spiral(uv, currentTime * 0.5));
            let temp = 2500.0 + params.y * 8000.0;
            output_color = output_color * blackbody(temp);
        }
        case 3: {
            // Mode 3: Atmospheric scattering
            let sun_pos = vec2<f32>(0.5 + sin(currentTime * 0.2) * 0.4, 0.3 + cos(currentTime * 0.15) * 0.2);
            output_color = atmospheric_scatter(uv, sun_pos);
            output_color = output_color + blackbody(5778.0) * 0.1; // Sun color
        }
        default: {
            output_color = input_color.rgb;
        }
    }
    
    // Blend with input
    let blend = params.w;
    let final_color = mix(input_color.rgb, output_color, blend);
    
    // Write output
    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
