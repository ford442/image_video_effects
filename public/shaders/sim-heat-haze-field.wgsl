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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(gid.xy) / resolution;
    let pixel = 1.0 / resolution;
    let time = u.config.x;
    
    // Parameters
    let temperature = mix(0.2, 1.0, u.zoom_params.x);    // x: Temperature intensity
    let convectionSpeed = mix(0.5, 3.0, u.zoom_params.y); // y: Convection speed
    let distortion = mix(0.0, 0.05, u.zoom_params.z);     // z: Distortion strength
    let heatSources = mix(1.0, 5.0, u.zoom_params.w);     // w: Heat source count
    
    // Read previous temperature field
    let prevTemp = textureLoad(dataTextureC, gid.xy, 0).r;
    
    // Diffuse temperature
    var sum = 0.0;
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            sum += textureLoad(dataTextureC, gid.xy + vec2<u32>(u32(x), u32(y)), 0).r;
        }
    }
    let diffused = sum / 9.0;
    
    // Cool over time
    let cooled = diffused * 0.98;
    
    // Heat source at bottom (ground heating)
    let groundHeat = smoothstep(0.15, 0.0, uv.y) * temperature;
    
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
    let mouseDist = length(uv - mousePos);
    let mouseHeat = smoothstep(0.1, 0.0, mouseDist) * temperature * 0.3;
    
    // New temperature
    let newTemp = min(cooled + groundHeat + sourceHeat + mouseHeat, 1.0);
    
    // Store temperature
    textureStore(dataTextureA, gid.xy, vec4<f32>(newTemp, 0.0, 0.0, 1.0));
    
    // Calculate temperature gradient for refraction
    let tempRight = textureLoad(dataTextureC, gid.xy + vec2<u32>(1u, 0u), 0).r;
    let tempLeft = textureLoad(dataTextureC, gid.xy - vec2<u32>(1u, 0u), 0).r;
    let tempUp = textureLoad(dataTextureC, gid.xy + vec2<u32>(0u, 1u), 0).r;
    let tempDown = textureLoad(dataTextureC, gid.xy - vec2<u32>(0u, 1u), 0).r;
    
    let grad = vec2<f32>(tempRight - tempLeft, tempUp - tempDown);
    
    // Hot air rises (buoyancy creates upward displacement)
    let displacement = vec2<f32>(
        grad.x * distortion,
        -newTemp * distortion * convectionSpeed * 0.5
    );
    
    // Add shimmer noise
    let shimmer = hash12(uv * 50.0 + time * 5.0) * newTemp * distortion * 0.3;
    displacement += vec2<f32>(shimmer);
    
    // Sample image with displacement
    let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;
    
    // Heat tint (hot areas get slight red/yellow tint)
    let heatTint = vec3<f32>(1.0 + newTemp * 0.3, 1.0 + newTemp * 0.1, 1.0 - newTemp * 0.1);
    color *= heatTint;
    
    // Desaturate in hot areas (air shimmer effect)
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = mix(color, vec3<f32>(luma), newTemp * 0.3);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.9, 1.0, newTemp * 0.2);
    
    textureStore(writeTexture, gid.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
