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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let cellSize = mix(10.0, 100.0, u.zoom_params.x); // Cells
    let spread = u.zoom_params.y * 2.0;
    let aberration = u.zoom_params.z * 0.1;
    let tint = u.zoom_params.w;

    // Grid coordinates
    let gridUV = floor(uv * cellSize) / cellSize;
    let cellCenter = gridUV + (0.5 / cellSize);

    let mouse = u.zoom_config.yz;

    // Vector from mouse to cell (Projector light direction)
    // Correct for aspect
    let vecToCell = (cellCenter - mouse) * vec2(aspect, 1.0);
    let dist = length(vecToCell);
    let dir = normalize(vecToCell);

    // Calculate sample offset based on light direction (Shadow casting logic)
    // Actually, let's just use the direction to shift RGB channels

    // Sample texture at cell center (Mosaic effect)
    // Add offset based on direction * spread
    let baseOffset = dir * dist * spread * 0.1;

    // Chromatic Aberration
    let rOffset = baseOffset + (dir * aberration);
    let gOffset = baseOffset;
    let bOffset = baseOffset - (dir * aberration);

    let r = textureSampleLevel(readTexture, u_sampler, cellCenter + rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, cellCenter + gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, cellCenter + bOffset, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Vignette per cell
    let cellUV = fract(uv * cellSize); // 0-1 within cell
    let cellDist = distance(cellUV, vec2(0.5));
    // Soft circle
    let shape = smoothstep(0.5, 0.4, cellDist);

    color = color * shape;

    // Tint based on mouse distance (light falloff)
    let lightFalloff = 1.0 / (1.0 + dist * 2.0);
    color = color * lightFalloff;

    textureStore(writeTexture, global_id.xy, vec4(color, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
