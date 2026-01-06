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
  config: vec4<f32>,       // x=Time, y=Ripples, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // Params
  ripples: array<vec4<f32>, 50>,
};

// Simple hash for noise
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let scope_size = u.zoom_params.x; // Size of the clear area
    let grain_amt = u.zoom_params.y;  // Noise intensity outside scope
    let brightness = u.zoom_params.z; // Brightness boost inside scope
    let scanline_str = u.zoom_params.w; // Scanline intensity

    // Mouse Interaction
    let mouse = u.zoom_config.yz;

    // Correct distance for aspect ratio
    let d_vec = uv - mouse;
    let d_aspect = vec2<f32>(d_vec.x * aspect, d_vec.y);
    let dist = length(d_aspect);

    // Scope Mask
    // radius mapped from parameter 0-1 to reasonable screen size
    let radius = 0.1 + scope_size * 0.4;
    // Smooth edge for the scope
    let scope_mask = 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);

    // Image Sample
    // Maybe zoom in inside the scope?
    // Lens distortion effect:
    let distortion_str = -0.2 * scope_mask; // Slight bulge
    let distorted_uv = uv + d_vec * distortion_str;

    var color = textureSampleLevel(readTexture, u_sampler, distorted_uv, 0.0).rgb;

    // Night Vision Green Processing
    let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let nv_color = vec3<f32>(0.0, 1.0, 0.0) * lum * (1.5 + brightness);

    // Noise/Grain
    let noise = hash12(uv * 100.0 + vec2<f32>(u.config.x * 10.0, u.config.x * 20.0));

    // Scanlines
    let scanline = sin(uv.y * 800.0 + u.config.x * 10.0) * 0.5 + 0.5;

    // Outside scope styling (Darker, noisier, heavy scanlines)
    let outside_color = nv_color * 0.3 * (0.8 + 0.4 * noise) * (0.8 + 0.2 * scanline);

    // Inside scope styling (Brighter, clearer, less noise)
    let inside_color = nv_color * (0.9 + 0.1 * noise) * (0.95 + 0.05 * scanline);

    // Mix based on scope mask
    var final_color = mix(outside_color, inside_color, scope_mask);

    // Add vignette to the very edges of screen
    let vign = 1.0 - length((uv - 0.5) * vec2<f32>(aspect, 1.0)) * 0.8;
    final_color = final_color * clamp(vign, 0.0, 1.0);

    // Apply Grain intensity param
    final_color = mix(final_color, vec3<f32>(noise), grain_amt * 0.2);

    // Scanline parameter application
    final_color = final_color * (1.0 - scanline_str * (1.0 - scanline) * 0.5);

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
