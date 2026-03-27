// ═══════════════════════════════════════════════════════════════════
//  Bifurcation Diagram - Logistic map visualization
//  Category: generative
//  Features: procedural, logistic map, density coloring
//  Created: 2026-03-22
//  By: Agent 4A
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

// Logistic map: x_{n+1} = r * x_n * (1 - x_n)
fn logisticMap(r: f32, x0: f32, iterations: i32) -> f32 {
    var x = x0;
    for (var i: i32 = 0; i < iterations; i++) {
        x = r * x * (1.0 - x);
        if (x < 0.0 || x > 1.0) { break; }
    }
    return x;
}

// Multiple iterations to get attractor points
fn getAttractorPoints(r: f32, iterations: i32, skip: i32) -> vec4<f32> {
    var x = 0.5; // Initial condition
    
    // Skip transient
    for (var i: i32 = 0; i < skip; i++) {
        x = r * x * (1.0 - x);
    }
    
    // Collect attractor points
    var points = vec4<f32>(0.0);
    for (var i: i32 = 0; i < 4; i++) {
        x = r * x * (1.0 - x);
        points[i] = x;
    }
    
    return points;
}

// Color schemes
fn colorThermal(t: f32) -> vec3<f32> {
    // Black -> Red -> Yellow -> White
    if (t < 0.33) {
        return mix(vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), t / 0.33);
    } else if (t < 0.66) {
        return mix(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(1.0, 1.0, 0.0), (t - 0.33) / 0.33);
    } else {
        return mix(vec3<f32>(1.0, 1.0, 0.0), vec3<f32>(1.0, 1.0, 1.0), (t - 0.66) / 0.34);
    }
}

fn colorRainbow(t: f32) -> vec3<f32> {
    let hue = t;
    let sat = 0.8;
    let light = 0.5;
    
    let c = (1.0 - abs(2.0 * light - 1.0)) * sat;
    let x = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
    let m = light - c * 0.5;
    
    var r = 0.0; var g = 0.0; var b = 0.0;
    if (hue < 1.0/6.0) { r = c; g = x; }
    else if (hue < 2.0/6.0) { r = x; g = c; }
    else if (hue < 3.0/6.0) { g = c; b = x; }
    else if (hue < 4.0/6.0) { g = x; b = c; }
    else if (hue < 5.0/6.0) { r = x; b = c; }
    else { r = c; b = x; }
    
    return vec3<f32>(r + m, g + m, b + m);
}

fn colorOcean(t: f32) -> vec3<f32> {
    return mix(vec3<f32>(0.0, 0.05, 0.2), vec3<f32>(0.5, 0.8, 1.0), t);
}

fn colorFire(t: f32) -> vec3<f32> {
    return mix(vec3<f32>(0.2, 0.0, 0.0), vec3<f32>(1.0, 0.8, 0.2), pow(t, 0.5));
}

// Lyapunov exponent approximation
fn lyapunov(r: f32) -> f32 {
    var x = 0.5;
    var sum = 0.0;
    let n = 100;
    
    for (var i: i32 = 0; i < n; i++) {
        x = r * x * (1.0 - x);
        let derivative = abs(r * (1.0 - 2.0 * x));
        if (derivative > 0.0001) {
            sum += log(derivative);
        }
    }
    
    return sum / f32(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    
    // Parameters - safe randomization
    let rPosition = mix(2.8, 4.0, u.zoom_params.x);
    let zoomLevel = mix(1.0, 50.0, u.zoom_params.y * u.zoom_params.y);
    let iterationCount = i32(mix(50.0, 200.0, u.zoom_params.z));
    let colorScheme = i32(u.zoom_params.w * 3.99);
    
    // R range with zoom and pan
    let rCenter = rPosition;
    let rRange = 1.2 / zoomLevel;
    let rMin = max(2.8, rCenter - rRange * 0.5);
    let rMax = min(4.0, rCenter + rRange * 0.5);
    
    // Map x to r parameter
    let r = mix(rMin, rMax, uv.x);
    
    // Map y to x value (0-1)
    let targetX = uv.y;
    
    // Calculate attractor points
    let skip = 100;
    let points = getAttractorPoints(r, iterationCount, skip);
    
    // Check if any point matches our y coordinate
    var density = 0.0;
    let binSize = 0.5 / resolution.y;
    
    // Run more iterations for density
    var x = 0.5;
    for (var i: i32 = 0; i < skip; i++) {
        x = r * x * (1.0 - x);
    }
    
    for (var i: i32 = 0; i < iterationCount; i++) {
        x = r * x * (1.0 - x);
        let dist = abs(x - targetX);
        if (dist < binSize) {
            density += 1.0 - dist / binSize;
        }
    }
    
    // Normalize density
    density = min(density / 10.0, 1.0);
    
    // Calculate color
    var col = vec3<f32>(0.0);
    
    if (density > 0.01) {
        switch (colorScheme) {
            case 0: { col = colorThermal(density); }
            case 1: { col = colorRainbow(density); }
            case 2: { col = colorOcean(density); }
            case 3: { col = colorFire(density); }
            default: { col = colorThermal(density); }
        }
        
        // Add brightness boost for high density
        col = col * (0.7 + 0.6 * density);
    } else {
        // Background
        col = vec3<f32>(0.02, 0.02, 0.03);
    }
    
    // Highlight periodic windows
    let lyap = lyapunov(r);
    if (lyap < 0.0) {
        // Periodic region - subtle glow
        let periodGlow = smoothstep(0.0, -0.5, lyap) * 0.1;
        col = col + vec3<f32>(0.2, 0.3, 0.5) * periodGlow;
    } else {
        // Chaotic region - warm tint
        let chaosTint = smoothstep(0.0, 0.5, lyap) * 0.1;
        col = col + vec3<f32>(0.5, 0.2, 0.1) * chaosTint;
    }
    
    // Grid lines for reference
    let gridX = fract(uv.x * 10.0);
    let gridY = fract(uv.y * 10.0);
    if (gridX < 0.02 || gridY < 0.02) {
        col = col * 0.8 + vec3<f32>(0.1) * 0.2;
    }
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    col *= vignette;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(density, 0.0, 0.0, 0.0));
}
