# Wolfram Data for WGSL Shaders

This document catalogs mathematical and scientific data from Wolfram Alpha that can be used to enhance WGSL shader realism and variety.

## Overview

The Wolfram Alpha API provides access to:
- High-precision mathematical constants
- Physical constants for realistic simulations
- Special functions (Bessel, spherical harmonics, etc.)
- Color science data (blackbody radiation, color temperatures)
- Numerical sequences (primes, Fibonacci)
- Atmospheric and optical physics data

## Data Categories for Shaders

### 1. Mathematical Constants

| Constant | Value | WGSL Usage |
|----------|-------|------------|
| Golden Ratio (φ) | 1.6180339887 | Spiral patterns, organic growth |
| Inverse φ | 0.6180339887 | Aspect ratios, timing |
| √2 | 1.4142135624 | Diagonal scaling |
| √3 | 1.7320508076 | Hexagonal patterns |
| e | 2.7182818285 | Exponential growth |
| Golden Angle | 2.3999632297 rad (137.5°) | Phyllotaxis patterns |

**Shader Example:**
```wgsl
// Phyllotaxis pattern using golden angle
fn phyllotaxis(uv: vec2<f32>, i: f32) -> vec2<f32> {
    let r = sqrt(i) * 0.01;
    let theta = i * 2.3999632297; // Golden angle
    return vec2<f32>(r * cos(theta), r * sin(theta));
}
```

### 2. Physical Constants

| Constant | Value | Use Case |
|----------|-------|----------|
| Speed of Light (c) | 299792458 m/s | Relativistic effects |
| Planck Constant | 6.626×10⁻³⁴ J⋅s | Quantum visualizations |
| Gravitational (G) | 6.674×10⁻¹¹ m³/(kg⋅s²) | Gravity simulations |
| Fine Structure | 0.0072973525693 | Quantum field visuals |
| g (Earth) | 9.81 m/s² | Water wave physics |

### 3. Atmospheric Scattering Data

From Wolfram's atmospheric physics calculations:

```wgsl
// Rayleigh scattering coefficients for Earth-like atmosphere
const RAYLEIGH_SCATTERING: vec3<f32> = vec3<f32>(
    5.804542996261093e-6,  // Red
    1.3562911419845635e-5,  // Green
    3.0265902468824876e-5   // Blue
);

// Scale heights
const RAYLEIGH_HEIGHT: f32 = 8500.0;  // meters
const MIE_HEIGHT: f32 = 1200.0;       // meters
const MIE_G: f32 = 0.758;             // Mie scattering direction
```

### 4. Color Temperature (Blackbody Radiation)

Wolfram can calculate RGB values for any color temperature:

| Temperature (K) | Color | Use Case |
|-----------------|-------|----------|
| 1000 | Deep red | Candle flames |
| 2700 | Warm white | Incandescent bulbs |
| 5500 | Daylight | Sun at noon |
| 6500 | Cool white | Overcast sky |
| 10000 | Blue-white | Clear sky |

```wgsl
fn blackbody(t: f32) -> vec3<f32> {
    // Polynomial approximation from Wolfram data
    let T = clamp(t, 1000.0, 40000.0);
    // ... color calculation
}
```

### 5. Bessel Functions

For diffraction patterns (Airy disks), radial waves:

```wgsl
// First zero of J0 - defines Airy disk radius
const BESSEL_J0_ZERO: f32 = 2.4048255577;

fn bessel_j0(x: f32) -> f32 {
    // Numerical approximation
    // ... implementation
}
```

### 6. Prime Numbers for Hashing

```wgsl
// Large primes for spatial hashing
const HASH_PRIME_1: i32 = 73856093;
const HASH_PRIME_2: i32 = 19349663;
const HASH_PRIME_3: i32 = 83492791;

fn spatial_hash(x: i32, y: i32, z: i32) -> i32 {
    return (x * HASH_PRIME_1) ^ (y * HASH_PRIME_2) ^ (z * HASH_PRIME_3);
}
```

### 7. Spherical Harmonics

For planet/cloud lighting without textures:

```wgsl
// Y(l,m) basis functions
fn Y00() -> f32 { return 0.2820947918; }
fn Y10(theta: f32) -> f32 { return 0.4886025119 * cos(theta); }
fn Y20(theta: f32) -> f32 { 
    return 0.3153915653 * (3.0 * cos(theta) * cos(theta) - 1.0); 
}
```

### 8. Noise Octave Weights

For fBm (Fractal Brownian Motion):

```wgsl
const OCTAVE_WEIGHTS: array<f32, 8> = array<f32, 8>(
    0.5000,   // 1/2
    0.2500,   // 1/4
    0.1250,   // 1/8
    0.0625,   // 1/16
    0.03125,  // 1/32
    0.015625, // 1/64
    0.0078125,// 1/128
    0.00390625// 1/256
);
```

## Practical Shader Examples

### Atmospheric Scattering Shader
```wgsl
fn atmospheric_scatter(uv: vec2<f32>, sun_pos: vec2<f32>) -> vec3<f32> {
    let cos_theta = dot(normalize(uv - 0.5), normalize(sun_pos - 0.5));
    let phase = 0.0596831 * (1.0 + cos_theta * cos_theta); // Rayleigh phase
    let optical_depth = exp(-length(uv - sun_pos) * 3.0);
    return RAYLEIGH_SCATTERING * phase * optical_depth * 100000.0;
}
```

### Golden Spiral
```wgsl
fn fibonacci_spiral(uv: vec2<f32>, time: f32) -> f32 {
    let centered = uv - 0.5;
    let angle = atan2(centered.y, centered.x);
    let radius = length(centered);
    let b = log(PHI) / (PI / 2.0);
    let spiral = log(radius + 0.001) / b - angle - time;
    return smoothstep(0.1, 0.0, abs(fract(spiral / TAU) - 0.5));
}
```

## Querying Wolfram for Shader Data

Example API calls for shader development:

```bash
# Mathematical constants
curl "https://api.wolframalpha.com/v2/query?input=golden+ratio+to+10+decimal&appid=YOUR_APPID"

# Physical constants
curl "https://api.wolframalpha.com/v2/query?input=Planck+constant&appid=YOUR_APPID"

# Color temperature
curl "https://api.wolframalpha.com/v2/query?input=RGB+for+6500K+blackbody&appid=YOUR_APPID"

# Bessel function values
curl "https://api.wolframalpha.com/v2/query?input=BesselJ(0,2.4048)&appid=YOUR_APPID"
```

## Integration with Pixelocity

The shader `wolfram-data-demo.wgsl` demonstrates:
- Phyllotaxis patterns using golden angle
- Airy disk diffraction using Bessel J0
- Fibonacci spirals
- Atmospheric scattering with Rayleigh data

Use **Param1** to switch between modes.

## Future Enhancements

Potential Wolfram data to integrate:
- Fresnel equations for realistic reflections
- Electromagnetic spectrum data
- Planetary orbital mechanics
- Fluid dynamics equations
- Acoustic wave propagation
- Biological growth patterns (L-systems)

## References

- [Wolfram Alpha API](https://products.wolframalpha.com/api/)
- [Rayleigh Scattering](https://en.wikipedia.org/wiki/Rayleigh_scattering)
- [Black-body Radiation](https://en.wikipedia.org/wiki/Black-body_radiation)
- [Spherical Harmonics](https://en.wikipedia.org/wiki/Spherical_harmonics)
- [Bessel Functions](https://en.wikipedia.org/wiki/Bessel_function)
- [Phyllotaxis](https://en.wikipedia.org/wiki/Phyllotaxis)
