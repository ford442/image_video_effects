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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let radius = u.zoom_params.x * 0.2;
    let strength = u.zoom_params.y * 0.1;
    let decay = 0.9 + u.zoom_params.z * 0.09; // 0.9 to 0.99
    let swirl = u.zoom_params.w * 10.0; // Viscosity/Swirl factor

    // Mouse Interaction
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Read previous velocity field from dataTextureC (stores offset X, offset Y, 0, 0)
    let prevData = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    var velocity = prevData.xy;

    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    if (isMouseDown && dist < radius) {
        // Add velocity away from mouse (push)
        let pushDir = normalize(distVec + vec2<f32>(0.0001, 0.0)); // Avoid NaN
        let force = (1.0 - dist / radius) * strength;

        // Add some swirl based on distance
        let swirlDir = vec2<f32>(-pushDir.y, pushDir.x);

        velocity = velocity + pushDir * force + swirlDir * force * (swirl * 0.1);
    }

    // Decay velocity
    velocity = velocity * decay;

    // Apply velocity to UV for sampling the image
    let distortedUV = uv - velocity;

    let color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Store velocity for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(velocity, 0.0, 1.0));

    // Output color
    textureStore(writeTexture, global_id.xy, color);
}
