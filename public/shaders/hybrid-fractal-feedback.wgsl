// ═══════════════════════════════════════════════════════════════════════════════
//  Hybrid Fractal Feedback - Advanced Alpha with Accumulative
//  Category: feedback/temporal
//  Alpha Mode: Accumulative Alpha + Effect Intensity
//  Features: advanced-alpha, fractal, feedback, hybrid
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

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 3: Accumulative Alpha
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.08) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    return vec4<f32>(color, totalAlpha);
}

// Complex multiplication
fn complexMul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    
    let accumulationRate = u.zoom_params.x;
    let fractalIter = i32(u.zoom_params.y * 50.0 + 10.0);
    let zoom = u.zoom_params.z * 2.0 + 1.0;
    let feedback = u.zoom_params.w;
    
    let current = textureLoad(readTexture, coord, 0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Julia fractal
    let c = vec2<f32>(cos(time * 0.2) * 0.7, sin(time * 0.3) * 0.3);
    let z = (uv - 0.5) * zoom * 2.0;
    
    var iter = 0;
    var zCurrent = z;
    for (var i: i32 = 0; i < fractalIter; i++) {
        zCurrent = complexMul(zCurrent, zCurrent) + c;
        if (dot(zCurrent, zCurrent) > 4.0) {
            iter = i;
            break;
        }
        iter = i;
    }
    
    let fractalValue = f32(iter) / f32(fractalIter);
    let fractalColor = vec3<f32>(
        fractalValue * (0.5 + 0.5 * sin(time)),
        fractalValue * (0.5 + 0.5 * sin(time + 2.0)),
        fractalValue * (0.5 + 0.5 * sin(time + 4.0))
    );
    
    let blended = mix(prev.rgb, fractalColor, feedback);
    let newAlpha = fractalValue;
    
    let accumulated = accumulativeAlpha(blended, newAlpha, prev.rgb, prev.a, accumulationRate);
    
    textureStore(dataTextureA, coord, accumulated);
    textureStore(writeTexture, global_id.xy, accumulated);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
