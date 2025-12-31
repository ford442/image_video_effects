// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // Params
    let density = u.zoom_params.x * 100.0 + 10.0;
    let glow = u.zoom_params.y;
    let force = u.zoom_params.z;
    let fray = u.zoom_params.w;

    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // Fiber strips calculations
    let stripIndex = floor(uv.y * density);
    let stripUV = fract(uv.y * density);
    let isOdd = (stripIndex % 2.0) >= 1.0;

    // Mouse Interaction
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Displacement logic
    // Base weaving motion
    var offsetX = 0.0;
    if (isOdd) {
        offsetX = sin(uv.y * 20.0 + time * 2.0) * 0.005 * fray;
    } else {
        offsetX = -sin(uv.y * 20.0 + time * 2.0) * 0.005 * fray;
    }

    // Mouse Repulsion / Distortion
    // We want the mouse to push the fibers apart horizontally or just disturb them?
    // Let's make the mouse push pixels away from it, but stronger along the fiber direction (horizontal)

    let repulsionRadius = 0.3;
    let repulsionStr = smoothstep(repulsionRadius, 0.0, dist) * force * 0.2;

    if (dist > 0.001) {
        let dir = normalize(distVec);
        offsetX += dir.x * repulsionStr;
    }

    // Apply offset
    let finalUV = vec2<f32>(uv.x + offsetX, uv.y);

    // Sample texture
    var col = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // Add Fiber Glow
    // Glow at the edges of the strips to simulate individual fibers
    let edge = abs(stripUV - 0.5) * 2.0; // 0 at center, 1 at edge
    let glowFactor = smoothstep(0.7, 1.0, edge) * glow;

    // Enhance brightness based on original image luminance
    let lum = dot(col.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Add a cyan/blue tint to the glow
    let glowColor = vec4<f32>(0.2, 0.8, 1.0, 0.0) * glowFactor * lum;

    col = col + glowColor;

    textureStore(writeTexture, global_id.xy, col);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
