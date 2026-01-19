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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=Width, w=Height
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // Params
  ripples: array<vec4<f32>, 50>,
};

// Chromatic Swirl
// Swirls the image around the mouse, separating RGB channels.

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.zoom_config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Params
    let swirlStrength = 5.0 + u.zoom_params.x * 10.0;
    let radius = 0.3 + u.zoom_params.y * 0.5;
    let aberration = 0.02 + u.zoom_params.z * 0.05;
    let animate = u.zoom_params.w; // If > 0, swirl rotates automatically

    let aspect = resolution.x / resolution.y;
    let center = mouse;
    if (mouse.x < 0.0) {
        // Fallback if no mouse
        center = vec2<f32>(0.5, 0.5);
    }

    let dVec = uv - center;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    // Calculate Swirl Angle
    // Falloff: strong at center, 0 at radius
    var angle = 0.0;
    if (dist < radius) {
        let percent = (radius - dist) / radius;
        angle = percent * percent * swirlStrength;
        if (animate > 0.5) {
            angle += sin(time) * 2.0 * percent;
        }
        if (mouseDown > 0.5) {
            angle *= 2.0; // Intensify on click
        }
    }

    // Function to rotate UV
    let sinA = sin(angle);
    let cosA = cos(angle);
    let offset = uv - center;
    // Standard 2D rotation matrix:
    // x' = x cos A - y sin A
    // y' = x sin A + y cos A
    // But we need to account for aspect ratio to rotate physically circular
    let x_corr = offset.x * aspect;
    let y_corr = offset.y;

    let rotatedX = x_corr * cosA - y_corr * sinA;
    let rotatedY = x_corr * sinA + y_corr * cosA;

    let finalUV_center = vec2<f32>(rotatedX / aspect, rotatedY) + center;

    // Chromatic Aberration: Sample R, G, B at slightly different angles or scales
    // We'll just offset the rotation angle slightly for each channel implies recomputing rotation?
    // Easier: just offset the final UV slightly along the radius.

    let dir = normalize(finalUV_center - center);

    let uvR = finalUV_center + dir * aberration * dist;
    let uvG = finalUV_center;
    let uvB = finalUV_center - dir * aberration * dist;

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // Check bounds to avoid streaking if desired, or let clamp handle it (sampler defaults usually clamp or repeat)
    // Renderer uses 'repeat' for filteringSampler.

    // Create a mask to show the effect only within radius?
    // Actually swirl logic creates 0 angle outside radius, so it smoothly transitions to normal UV.
    // However, the chromatic aberration offset might extend slightly outside.

    textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));
}
