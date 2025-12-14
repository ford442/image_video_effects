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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=Aberration, w=Darkness
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Mouse coords are in u.zoom_config.yz
    // The renderer maps them 0-1.
    let mousePos = u.zoom_config.yz;

    // Params
    let strength = u.zoom_params.x * 2.0;    // 0.0 to 2.0
    let radius = max(0.01, u.zoom_params.y * 0.5); // 0.01 to 0.5
    let aberration = u.zoom_params.z * 0.05; // 0.0 to 0.05
    let darkness = u.zoom_params.w;          // 0.0 to 1.0

    // Vector from UV to Mouse
    let toMouse = uv - mousePos;
    // Correct aspect ratio for distance calculation
    let aspect = resolution.x / resolution.y;
    let distVec = toMouse * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Gravity calculation
    // Force falls off with distance.
    // We want a warp that pulls pixels *away* from the mouse? No, a gravity well pulls space *towards* it.
    // If I look at pixel P, I want to know what light ray hits it.
    // If space is compressed towards the center, then a ray hitting P (near center) came from further out?
    // Let's implement a simple radial distortion.
    // NewUV = Mouse + (UV - Mouse) * DistortionFactor

    // If factor < 1.0, we zoom in (pull from closer to center).
    // If factor > 1.0, we zoom out (pull from further out).

    // Gravity pulls light towards it.
    // So if we look "near" the black hole, we see light from "behind" it being bent around.
    // Effectively, it magnifies the background.

    // Let's use a smooth falloff.
    // Distort = 1.0 - Strength * exp(-dist / Radius)
    let distortion = 1.0 - strength * exp(-dist / radius);

    // Apply separate distortion for RGB for chromatic aberration
    let offsetR = toMouse * (distortion - aberration);
    let offsetG = toMouse * distortion;
    let offsetB = toMouse * (distortion + aberration);

    let uvR = mousePos + offsetR;
    let uvG = mousePos + offsetG;
    let uvB = mousePos + offsetB;

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Darkness at the singularity (center)
    let core = smoothstep(radius * 0.2, radius * 0.5, dist);
    color = mix(vec3<f32>(0.0), color, mix(1.0, core, darkness));

    // Handle out of bounds (optional, sampler clamps or repeats usually)
    // If we want black edges:
    // if (any(uvR < vec2(0.0)) || any(uvR > vec2(1.0))) { r = 0.0; } etc.
    // But sampler is usually set to repeat or clamp. Renderer sets it to 'repeat'.

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    // Passthrough depth for now, or warp it too?
    // Warping depth might be more correct for compositing.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvG, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
