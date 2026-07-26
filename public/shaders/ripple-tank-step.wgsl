// ═══ RIPPLE TANK — GRAPH NODE: WAVE STEP ═══════════════════════════════════
//  Tier C graph: discrete 2D wave equation, 5×5 Laplacian (repeat N×/frame).
//
//  State packing (dataTextureA / dataTextureC):
//    .r = height u(t), .g = velocity ∂u/∂t, .b = prev height, .a = phase
//
//  Reads dataTextureC (binding 9), writes dataTextureA (binding 7).
//  zoom_params: .x wave speed, .y damping, .z source (unused here), .w boundary

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

fn loadHeight(pixel: vec2<i32>, res: vec2<i32>) -> f32 {
    let p = clamp(pixel, vec2<i32>(0), res - vec2<i32>(1));
    return textureLoad(dataTextureC, p, 0).r;
}

fn laplacian5x5(pixel: vec2<i32>, res: vec2<i32>) -> f32 {
    var sum = -28.0 * loadHeight(pixel, res);
    sum += 4.0 * loadHeight(pixel + vec2<i32>( 1,  0), res);
    sum += 4.0 * loadHeight(pixel + vec2<i32>(-1,  0), res);
    sum += 4.0 * loadHeight(pixel + vec2<i32>( 0,  1), res);
    sum += 4.0 * loadHeight(pixel + vec2<i32>( 0, -1), res);
    sum += 2.0 * loadHeight(pixel + vec2<i32>( 1,  1), res);
    sum += 2.0 * loadHeight(pixel + vec2<i32>( 1, -1), res);
    sum += 2.0 * loadHeight(pixel + vec2<i32>(-1,  1), res);
    sum += 2.0 * loadHeight(pixel + vec2<i32>(-1, -1), res);
    sum += 1.0 * loadHeight(pixel + vec2<i32>( 2,  0), res);
    sum += 1.0 * loadHeight(pixel + vec2<i32>(-2,  0), res);
    sum += 1.0 * loadHeight(pixel + vec2<i32>( 0,  2), res);
    sum += 1.0 * loadHeight(pixel + vec2<i32>( 0, -2), res);
    return sum / 14.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let resI = vec2<i32>(res);
    let uv   = vec2<f32>(pixel) / res;

    let waveSpeed       = mix(0.08, 0.45, u.zoom_params.x);
    let damping         = mix(0.975, 0.9995, u.zoom_params.y);
    let boundaryReflect = u.zoom_params.w;

    let state = textureLoad(dataTextureC, pixel, 0);
    var height   = state.r;
    var velocity = state.g;
    let phase    = state.a;

    let lap = laplacian5x5(pixel, resI);
    velocity += waveSpeed * waveSpeed * lap;
    velocity *= damping;
    let prevHeight = height;
    height += velocity;

    let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let edgeFade = smoothstep(0.0, 0.06, edgeDist);
    let absorb = mix(edgeFade, 1.0, boundaryReflect);
    height   *= absorb;
    velocity *= absorb;

    height   = clamp(height, -1.5, 1.5);
    velocity = clamp(velocity, -0.8, 0.8);

    textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, prevHeight, phase));
}
