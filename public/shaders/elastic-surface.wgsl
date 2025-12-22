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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Elastic Surface
// Param1: Stiffness (Spring force)
// Param2: Damping (Friction)
// Param3: Mouse Force
// Param4: Radius

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Parameters
    let stiffness = u.zoom_params.x * 0.5 + 0.01;
    let damping = 0.9 + u.zoom_params.y * 0.09; // 0.9 to 0.99
    let forceStrength = u.zoom_params.z * 2.0;
    let radius = u.zoom_params.w * 0.3 + 0.01;

    // Read previous state (displacement and velocity) from dataTextureC
    // R = offset X, G = offset Y, B = vel X, A = vel Y
    let prevState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var displacement = prevState.rg;
    var velocity = prevState.ba;

    // Spring force (Hooke's law): F = -k * x
    let springForce = -displacement * stiffness;

    // Apply forces
    var acceleration = springForce;

    // Mouse Interaction
    if (mousePos.x >= 0.0) {
        let dVec = uv - mousePos;
        let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

        if (dist < radius) {
            // Repulsion force
            // Correct direction back to UV space
            var forceDirUV = dVec;
            if (length(dVec) > 0.0001) {
                forceDirUV = normalize(dVec);
            }

            // Smooth falloff: 1.0 at center, 0.0 at radius
            let influence = 1.0 - smoothstep(0.0, radius, dist);

            // Push or Pull?
            // Let's push away.
            acceleration += forceDirUV * influence * forceStrength * 0.01;
        }
    }

    // Verlet integration / Euler
    velocity = (velocity + acceleration) * damping;
    displacement += velocity;

    // Write new state to dataTextureA (for next frame)
    // Cast to i32 for textureStore
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(displacement, velocity));

    // Sample image with displacement
    // Use clamp to avoid wrapping artifacts at edges if displacement is large
    let distortedUV = clamp(uv - displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Add some lighting based on displacement gradient (fake normal)
    // Simple way: if displacement is large, darken/lighten
    // Let's just visualize the stress slightly
    let stress = length(displacement) * 10.0;
    let finalColor = color + vec4<f32>(stress * 0.2); // Add highlight on stretched areas

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
}
