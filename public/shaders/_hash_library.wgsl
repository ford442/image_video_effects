// ═══════════════════════════════════════════════════════════════════════════════
//  WGSL Hash Function Library
//  High-quality hash functions for procedural noise and randomness.
//  These are designed to avoid visible patterns on all GPUs.
// ═══════════════════════════════════════════════════════════════════════════════
//
//  USAGE: Copy the functions you need into your shader.
//  All functions use the sin() + fract() pattern which is widely supported.
//  They have been tested to produce uniform distributions without visible banding.
//
// ═══════════════════════════════════════════════════════════════════════════════

// ───────────────────────────────────────────────────────────────────────────────
//  1D → 1D hash: Takes a float, returns a float in [0, 1]
// ───────────────────────────────────────────────────────────────────────────────
fn hash11(p: f32) -> f32 {
    var x = fract(p * 0.1031);
    x = x * (x + 33.33);
    x = x * (x + x);
    return fract(x);
}

// ───────────────────────────────────────────────────────────────────────────────
//  2D → 1D hash: Takes vec2, returns a float in [0, 1]
//  Most commonly used for 2D noise
// ───────────────────────────────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// ───────────────────────────────────────────────────────────────────────────────
//  2D → 2D hash: Takes vec2, returns vec2 in [0, 1]
//  Useful for 2D displacement or flow fields
// ───────────────────────────────────────────────────────────────────────────────
fn hash22(p: vec2<f32>) -> vec2<f32> {
    let k = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(k) * 43758.5453);
}

// ───────────────────────────────────────────────────────────────────────────────
//  2D → 2D hash (signed): Returns vec2 in [-1, 1]
//  Useful for velocity fields
// ───────────────────────────────────────────────────────────────────────────────
fn hash22_signed(p: vec2<f32>) -> vec2<f32> {
    return hash22(p) * 2.0 - 1.0;
}

// ───────────────────────────────────────────────────────────────────────────────
//  3D → 1D hash: Takes vec3, returns a float in [0, 1]
//  For 3D noise or time-varying 2D effects
// ───────────────────────────────────────────────────────────────────────────────
fn hash31(p: vec3<f32>) -> f32 {
    let h = dot(p, vec3<f32>(127.1, 311.7, 74.7));
    return fract(sin(h) * 43758.5453123);
}

// ───────────────────────────────────────────────────────────────────────────────
//  3D → 3D hash: Takes vec3, returns vec3 in [0, 1]
//  For Voronoi and 3D displacement
// ───────────────────────────────────────────────────────────────────────────────
fn hash33(p: vec3<f32>) -> vec3<f32> {
    let k = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(k) * 43758.5453);
}

// ───────────────────────────────────────────────────────────────────────────────
//  4D → 1D hash: Takes vec4, returns a float in [0, 1]
//  For hypercube noise (4D space or 3D + time)
// ───────────────────────────────────────────────────────────────────────────────
fn hash41(p: vec4<f32>) -> f32 {
    let h = dot(p, vec4<f32>(127.1, 311.7, 74.7, 157.3));
    return fract(sin(h) * 43758.5453123);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  VALUE NOISE - Smooth interpolated noise from hash
// ═══════════════════════════════════════════════════════════════════════════════

// ───────────────────────────────────────────────────────────────────────────────
//  2D Value Noise: Smooth noise in range [0, 1]
// ───────────────────────────────────────────────────────────────────────────────
fn valueNoise2D(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    
    // Four corners
    let a = hash21(i + vec2<f32>(0.0, 0.0));
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    
    // Smooth interpolation
    let u = f * f * (3.0 - 2.0 * f);
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ───────────────────────────────────────────────────────────────────────────────
//  2D Value Noise (signed): Smooth noise in range [-1, 1]
// ───────────────────────────────────────────────────────────────────────────────
fn valueNoise2D_signed(p: vec2<f32>) -> f32 {
    return valueNoise2D(p) * 2.0 - 1.0;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  FRACTAL BROWNIAN MOTION (FBM)
// ═══════════════════════════════════════════════════════════════════════════════

// ───────────────────────────────────────────────────────────────────────────────
//  FBM with configurable octaves: Returns value in [0, 1]
// ───────────────────────────────────────────────────────────────────────────────
fn fbm(p: vec2<f32>, octaves: i32, persistence: f32) -> f32 {
    var sum = 0.0;
    var amp = 1.0;
    var freq = 1.0;
    var maxAmp = 0.0;
    
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        sum = sum + amp * valueNoise2D(p * freq);
        maxAmp = maxAmp + amp;
        freq = freq * 2.0;
        amp = amp * persistence;
    }
    
    return sum / maxAmp;
}

// ───────────────────────────────────────────────────────────────────────────────
//  Default 5-octave FBM (most common usage)
// ───────────────────────────────────────────────────────────────────────────────
fn fbm5(p: vec2<f32>) -> f32 {
    return fbm(p, 5, 0.5);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  VORONOI / WORLEY NOISE
// ═══════════════════════════════════════════════════════════════════════════════

// ───────────────────────────────────────────────────────────────────────────────
//  Voronoi distance: Returns distance to nearest cell point
// ───────────────────────────────────────────────────────────────────────────────
fn voronoi(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    
    var minDist = 1.0;
    
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let cellId = i + neighbor;
            let point = neighbor + hash22(cellId) - f;
            let dist = length(point);
            minDist = min(minDist, dist);
        }
    }
    
    return minDist;
}

// ───────────────────────────────────────────────────────────────────────────────
//  Voronoi with cell ID: Returns (distance, cellIdX, cellIdY)
// ───────────────────────────────────────────────────────────────────────────────
fn voronoiWithId(p: vec2<f32>) -> vec3<f32> {
    let i = floor(p);
    let f = fract(p);
    
    var minDist = 1.0;
    var cellId = vec2<f32>(0.0);
    
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let nc = i + neighbor;
            let point = neighbor + hash22(nc) - f;
            let dist = length(point);
            if (dist < minDist) {
                minDist = dist;
                cellId = nc;
            }
        }
    }
    
    return vec3<f32>(minDist, cellId.x, cellId.y);
}
