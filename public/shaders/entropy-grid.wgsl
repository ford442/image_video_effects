@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_depth_2d;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 20>,
};

// Hash function for randomness
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);

    // Correct UV aspect ratio for distance calculations
    let aspect = u.config.z / u.config.w;
    let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouse = u.zoom_config.yz;
    let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);

    let dist = distance(uv_corrected, mouse_corrected);

    // Parameters
    // x: Grid Size (10.0 to 100.0)
    // y: Chaos Amount (0.0 to 1.0)
    // z: Radius (0.0 to 1.0)
    // w: Invert (0.0 or 1.0)

    let gridSize = mix(10.0, 100.0, u.zoom_params.x);
    let chaos = u.zoom_params.y;
    let radius = u.zoom_params.z;
    let invert = u.zoom_params.w > 0.5;

    // Calculate Grid ID
    let gridUV = floor(uv * gridSize);

    // Random offset for this grid cell
    let randX = hash(gridUV);
    let randY = hash(gridUV + vec2<f32>(1.0, 1.0));
    let randomOffset = (vec2<f32>(randX, randY) - 0.5) * chaos * 0.5;

    // Calculate influence
    var influence = smoothstep(radius, radius * 0.5, dist);

    if (invert) {
        influence = 1.0 - influence;
    }

    // Apply offset based on influence
    // If influence is high, we apply the chaos offset.
    // If influence is low, we stick to original UV (offset = 0).

    let finalOffset = randomOffset * influence;

    let sampleUV = uv + finalOffset;

    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
}
