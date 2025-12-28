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
    let strength = (u.zoom_params.x - 0.5) * 10.0; // Range -5.0 to 5.0
    let radius = u.zoom_params.y * 0.5 + 0.05;     // Range 0.05 to 0.55
    let twist = u.zoom_params.z * 10.0;            // Range 0.0 to 10.0

    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Center of effect is mouse position
    let center = mouse;

    // Vector from center to pixel, corrected for aspect
    let diff = uv - center;
    let diffAspect = diff * vec2<f32>(aspect, 1.0);
    let dist = length(diffAspect);

    var finalUV = uv;

    if (dist < radius) {
        // Calculate factor based on distance (1.0 at center, 0.0 at edge)
        let percent = (radius - dist) / radius;

        // Non-linear falloff for smoother look
        let weight = percent * percent;

        // Calculate rotation angle
        let theta = weight * strength;

        // Apply twist: radius dependent rotation
        let spiralAngle = twist * weight * dist;

        let totalAngle = theta + spiralAngle;

        let s = sin(totalAngle);
        let c = cos(totalAngle);

        // Rotate the offset vector
        // We rotate 'diff' but we need to handle aspect ratio carefully if we rotate
        // to ensure it doesn't squish.
        // Standard 2D rotation:
        // x' = x*c - y*s
        // y' = x*s + y*c
        // Ideally we rotate in a square space then convert back.

        let squareDiff = vec2<f32>(diff.x * aspect, diff.y);
        let rotatedSquareDiff = vec2<f32>(
            squareDiff.x * c - squareDiff.y * s,
            squareDiff.x * s + squareDiff.y * c
        );

        // Convert back to UV space
        let rotatedDiff = vec2<f32>(rotatedSquareDiff.x / aspect, rotatedSquareDiff.y);

        finalUV = center + rotatedDiff;
    }

    // Sample texture at distorted coordinates
    // Use clamp mode implicitly or mirror if possible?
    // u_sampler usually repeats. Let's clamp to edge to avoid seams if needed.
    // Actually repeat is fine for "Vortex" often, but let's see.

    let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
