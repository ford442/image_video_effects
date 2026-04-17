// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>, // y,z is mouse
  zoom_params: vec4<f32>, // x: dissipation, y: brush size, z: force, w: audio reactivity
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w;

    let dissipation = 0.9 + u.zoom_params.x * 0.09;
    let brushSize = 0.05 + u.zoom_params.y * 0.2;
    let audioReact = u.zoom_params.w;
    let bass = plasmaBuffer[0].x;
    let force = u.zoom_params.z * 0.5 * (1.0 + bass * audioReact);

    // Sample previous velocity field from dataTextureC (Red/Green channels = Velocity X/Y)
    let prevData = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var velocity = prevData.xy;

    // Mouse Interaction: Add velocity
    if (mousePos.x >= 0.0) {
        let dVec = uv - mousePos;
        let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

        if (dist < brushSize) {
             let pushDir = normalize(dVec);
             let influence = smoothstep(brushSize, 0.0, dist);
             velocity += pushDir * force * influence;
        }
    }

    // Decouple velocity
    velocity *= dissipation;

    // Advect UVs
    let offsetUV = uv - velocity * 0.05;
    let sampledColor = textureSampleLevel(readTexture, u_sampler, offsetUV, 0.0);

    // Write to display
    textureStore(writeTexture, vec2<i32>(global_id.xy), sampledColor);

    // Store velocity for next frame
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(velocity, 0.0, 1.0));

    // Pass depth through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
