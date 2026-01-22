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

fn getLuma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    let strength = u.zoom_params.x * 0.1; // Streak length (0.0 to 0.1)
    let samples = 30;
    let center = u.zoom_config.yz; // Mouse position

    // Aspect ratio correction for vector calculation
    let aspect = resolution.x / resolution.y;
    let center_aspect = vec2<f32>(center.x * aspect, center.y);
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);

    let dir = uv_aspect - center_aspect;
    let dist = length(dir);
    let dir_norm = normalize(dir);
    // Back to UV space direction
    let dir_uv = (uv - center);

    // Random jitter for "speed" effect
    let noise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233)) + time) * 43758.5453);

    var color_acc = vec4<f32>(0.0);
    var weight_acc = 0.0;

    let decay = 0.95; // Light decay per sample

    // Radial Blur Loop
    for (var i = 0; i < samples; i++) {
        let f = f32(i);
        // Sample position moves towards center
        let offset = dir_uv * (f / f32(samples)) * strength * dist * 10.0;
        let sample_uv = uv - offset;

        // Jitter sampling slightly
        let jitter_offset = offset * (noise - 0.5) * 0.1;

        // Check bounds
        if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
            continue;
        }

        let s_color = textureSampleLevel(readTexture, u_sampler, sample_uv + jitter_offset, 0.0);

        // Chromatic Aberration on the streaks (Blue shift at edges)
        let r = textureSampleLevel(readTexture, u_sampler, sample_uv + jitter_offset + dir_uv * 0.005 * f, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, sample_uv + jitter_offset - dir_uv * 0.005 * f, 0.0).b;
        let sample_color = vec4<f32>(r, s_color.g, b, s_color.a);

        // Weight features that are bright more heavily (Star streak effect)
        let luma = getLuma(sample_color.rgb);
        let bright_weight = smoothstep(0.5, 1.0, luma); // Only streak bright parts
        let weight = pow(decay, f) * (0.1 + bright_weight * 2.0);

        color_acc = color_acc + sample_color * weight;
        weight_acc = weight_acc + weight;
    }

    let final_color = color_acc / weight_acc;

    // Add a vignette/tunnel darkening at edges to emphasize the center
    let vignette = 1.0 - smoothstep(0.5, 1.5, dist);
    let output = mix(vec3<f32>(0.0), final_color.rgb, vignette);

    textureStore(writeTexture, global_id.xy, vec4<f32>(output, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
