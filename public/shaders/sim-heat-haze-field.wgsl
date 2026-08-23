// ═══════════════════════════════════════════════════════════════════
//  Sim: Heat Haze Field
//  Category: distortion
//  Features: simulation, temperature-field, convection, refraction
//  Complexity: High
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Temperature field simulation + convection currents
//  Desert mirage effect with rising heat patterns
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn stateAt(p: vec2<i32>, res: vec2<f32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(gid.xy) / resolution;
    let pixel = 1.0 / resolution;
    let time = u.config.x;
    let coord = vec2<i32>(gid.xy);
    let aspect = resolution.x / resolution.y;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    
    // Parameters
    let temperature = mix(0.2, 1.0, u.zoom_params.x);    // x: Temperature intensity
    let convectionSpeed = mix(0.5, 3.0, u.zoom_params.y); // y: Convection speed
    let distortion = mix(0.0, 0.05, u.zoom_params.z);     // z: Distortion strength
    let heatSources = mix(1.0, 5.0, u.zoom_params.w);     // w: Heat source count
    
    // Read previous temperature field
    let prevState = stateAt(coord, resolution);
    let prevTemp = prevState.r;
    
    // Diffuse temperature
    var sum = 0.0;
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            sum += stateAt(coord + vec2<i32>(x, y), resolution).r;
        }
    }
    let diffused = sum / 9.0;
    
    // Cool over time
    let cooled = mix(prevTemp, diffused, 0.18 + mids * 0.08) * mix(0.965, 0.992, u.zoom_params.x);
    
    // Heat source at bottom (ground heating)
    let groundHeat = smoothstep(0.72, 1.0, uv.y) * temperature * (0.025 + bass * 0.02);
    
    // Multiple heat sources (simulated)
    var sourceHeat = 0.0;
    for (var i: i32 = 0; i < i32(heatSources); i++) {
        let fi = f32(i);
        let sourceX = 0.1 + (hash12(vec2<f32>(fi, 0.0)) * 0.8);
        let sourceY = 0.1 + (hash12(vec2<f32>(fi, 1.0)) * 0.3);
        let sourcePos = vec2<f32>(sourceX, sourceY);
        let dist = length(uv - sourcePos);
        sourceHeat += smoothstep(0.1, 0.0, dist) * temperature * 0.5;
    }
    
    // Mouse heat source
    let mousePos = u.zoom_config.yz;
    let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
    let mouseField = smoothstep(0.12, 0.0, mouseDist);
    let mouseHeat = mouseField * temperature * (0.025 + u.zoom_config.w * 0.24) * (1.0 + bass * 0.5);

    var clickHeat = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let age = time - r.z;
        if (age >= 0.0 && age < 2.2) {
            let ring = abs(length((uv - r.xy) * vec2<f32>(aspect, 1.0)) - age * (0.16 + bass * 0.06));
            clickHeat += (1.0 - smoothstep(0.0, 0.03, ring)) * (1.0 - age / 2.2);
        }
    }
    
    // New temperature
    let newTemp = clamp(cooled + groundHeat + sourceHeat * 0.035 + mouseHeat + clickHeat * 0.12, 0.0, 1.5);
    
    // Store temperature
    // Calculate temperature gradient for refraction
    let tempRight = stateAt(coord + vec2<i32>(1, 0), resolution).r;
    let tempLeft = stateAt(coord + vec2<i32>(-1, 0), resolution).r;
    let tempUp = stateAt(coord + vec2<i32>(0, -1), resolution).r;
    let tempDown = stateAt(coord + vec2<i32>(0, 1), resolution).r;
    
    let grad = vec2<f32>(tempRight - tempLeft, tempUp - tempDown);
    
    // Hot air rises (buoyancy creates upward displacement)
    var displacement = vec2<f32>(
        grad.x * distortion,
        -newTemp * distortion * convectionSpeed * 0.5
    );
    
    // Add shimmer noise
    let shimmer = hash12(uv * 50.0 + time * 5.0) * newTemp * distortion * 0.3;
    displacement += vec2<f32>(shimmer * (1.0 + treble), -mids * newTemp * 0.002);
    textureStore(dataTextureA, coord, vec4<f32>(newTemp, grad, clamp(length(displacement) * 20.0, 0.0, 1.0)));
    
    // Sample image with displacement
    let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;
    
    // Heat tint (hot areas get slight red/yellow tint)
    let heatTint = vec3<f32>(1.0 + newTemp * 0.3, 1.0 + newTemp * 0.1, 1.0 - newTemp * 0.1);
    color *= heatTint;
    color += vec3<f32>(1.0, 0.35 + mids * 0.25, 0.08 + treble * 0.2) * pow(newTemp, 2.0) * 0.12;
    
    // Desaturate in hot areas (air shimmer effect)
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = mix(color, vec3<f32>(luma), newTemp * 0.3);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    color = acesToneMap(color);
    let sourceAlpha = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).a;
    let alpha = clamp(sourceAlpha * 0.75 + newTemp * 0.22 + clickHeat * 0.12, 0.0, 1.0);
    
    textureStore(writeTexture, gid.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
