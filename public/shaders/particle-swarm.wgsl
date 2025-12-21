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

// Particle Swarm
// Param1: Spring Stiffness (0.01 - 0.2)
// Param2: Mouse Force (0.1 - 2.0)
// Param3: Damping (0.8 - 0.99)
// Param4: Interaction Radius (0.01 - 0.5)

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let stiffness = mix(0.01, 0.2, u.zoom_params.x);
    let forceInput = u.zoom_params.y - 0.5; // -0.5 to 0.5
    let forceMult = forceInput * 0.1;
    let damping = mix(0.80, 0.98, u.zoom_params.z);
    let radius = mix(0.05, 0.4, u.zoom_params.w);

    // Read previous state from dataTextureC
    // r=offsetX, g=offsetY, b=velX, a=velY
    let state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var offset = state.xy;
    var vel = state.zw;

    // Current position of the "particle" (pixel source)
    let currentPos = uv + offset;

    // Mouse interaction
    let mousePos = u.zoom_config.yz;
    // Check if mouse is active/valid (simple check)
    var interaction = vec2<f32>(0.0);

    // Check distance
    let dVec = mousePos - currentPos;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y)); // Correct aspect for circle

    if (dist < radius && dist > 0.001) {
        let t = 1.0 - (dist / radius);
        let dir = normalize(dVec);
        interaction = dir * t * forceMult;
    }

    // Spring force (return to origin 0,0)
    let spring = -offset * stiffness;

    // Physics Update
    vel = (vel + interaction + spring) * damping;
    offset = offset + vel;

    // Write new state
    textureStore(dataTextureA, global_id.xy, vec4<f32>(offset, vel));

    // Sample Image
    // We sample the image at the OFFSET position.
    // If offset is (0,0), we sample at uv.
    // If offset moves, we sample elsewhere, making it look like the pixel moved.
    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Output
    textureStore(writeTexture, global_id.xy, color);
}
