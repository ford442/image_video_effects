@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // time, mouseX, mouseY, mouseDown
  zoom_params: vec4<f32>,         // param1, param2, param3, param4
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let strength = u.zoom_params.x;      // Distortion Strength
    let radius = u.zoom_params.y;        // Effect Radius
    let aberration = u.zoom_params.z;    // Chromatic Aberration
    let softness = u.zoom_params.w;      // Edge Softness

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Interactive Liquid Distortion
    var displacement = vec2<f32>(0.0);
    var chromAb = vec2<f32>(0.0);

    if (radius > 0.001) {
        // Create a bulge/pinch effect
        // If mouseDown, we pull (pinch), otherwise we push (bulge) slightly or just distort
        var force = strength;
        if (mouseDown > 0.5) {
            force *= -1.5; // Invert and strengthen on click
        }

        let normalizedDist = dist / radius;
        if (normalizedDist < 1.0) {
            // Smooth falloff curve
            let falloff = pow(1.0 - normalizedDist, 1.0 + softness * 4.0);

            // Vector pointing away from mouse
            let dir = normalize(distVec);

            // Calculate displacement
            displacement = dir * force * falloff * 0.2; // 0.2 scaling factor to keep it controllable

            // Chromatic aberration increases with displacement
            chromAb = dir * aberration * falloff * 0.05;
        }
    }

    // Apply displacement
    let distortedUV = uv - displacement;

    // Sample with Chromatic Aberration
    let r = textureSampleLevel(readTexture, u_sampler, distortedUV + chromAb, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, distortedUV - chromAb, 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));
}
