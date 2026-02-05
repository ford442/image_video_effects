// --- CONCENTRIC SPIN ---
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let ringDensity = mix(5.0, 50.0, u.zoom_params.x);
    let speedMult = mix(0.0, 5.0, u.zoom_params.y);
    let smoothness = u.zoom_params.z * 0.1; // Smooth transition between rings

    // Mouse is the center of rotation
    let center = u.zoom_config.yz;
    let centerVec = center * vec2<f32>(aspect, 1.0);

    // UV to Polar (relative to center)
    let p = uv * vec2<f32>(aspect, 1.0) - centerVec;
    let r = length(p);
    var a = atan2(p.y, p.x);

    // Ring Index
    let ringVal = r * ringDensity;
    let ringIdx = floor(ringVal);

    // Determine rotation for this ring
    // Alternating direction: (ringIdx % 2) -> -1 or 1
    // WGSL mod is f32 based usually.
    let direction = (ringIdx % 2.0) * 2.0 - 1.0; // 0->-1, 1->1 ? No.
    // ringIdx % 2.0 is 0 or 1.
    // if 0: 0*2-1 = -1. if 1: 1*2-1 = 1. Correct.

    let rotation = u.config.x * speedMult * direction; // Time based

    // Smooth transition?
    // If we want the boundary to not shear, we can't easily.
    // The rings must shear.

    // Apply rotation
    a += rotation;

    // Convert back to Cartesian
    let newP = vec2<f32>(cos(a), sin(a)) * r;

    // Map back to UV space
    let finalUV = (newP + centerVec) / vec2<f32>(aspect, 1.0);

    // Sample
    // Handle wrapping? Sampler does it.
    let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
