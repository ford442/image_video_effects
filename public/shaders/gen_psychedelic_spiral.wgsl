@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// Psychedelic Spiral Warp
// Hypnotic spiral with intense rainbow colors, mouse warping, and feedback trails

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let px = vec2<i32>(global_id.xy);

    // Parameters
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let detail = u.zoom_params.w;
    let bass = plasmaBuffer[0].x;

    // ═══ SAMPLE INPUT FROM PREVIOUS LAYER ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Feedback trail from previous frame
    let history = textureLoad(dataTextureC, px, 0).rgb;

    // Center coordinates with aspect correction
    let aspect = resolution.x / resolution.y;
    var p = uv - 0.5;
    p.x *= aspect;

    // Spiral center follows mouse
    var mouse_offset = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) - 0.5);
    mouse_offset.x *= aspect;
    p = p - mouse_offset * 0.5;

    var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) - vec2<f32>(0.5);
    mouse.x *= aspect;
    let mouse_dist = length(p - mouse);
    let mouse_warp = u.zoom_config.w * 0.5;

    // Spiral pattern
    let dist = length(p);
    let angle = atan2(p.y, p.x);
    let audio_pulse = 1.0 + bass * 0.5;
    var spiral = sin(dist * (15.0 + scale * 20.0) * audio_pulse - angle * (8.0 + detail * 10.0) - time * (2.0 + speed * 4.0));

    // Mouse creates ripples in the spiral
    spiral += sin(mouse_dist * 20.0 - time * 3.0) * mouse_warp * 5.0;

    // Fractal recursion for infinite detail
    var value = spiral;
    var sc = 1.0;
    let loop_count = i32(clamp(detail * 4.0 + 1.0, 1.0, 5.0));
    for (var i = 0; i < loop_count; i++) {
        value += sin(dist * (30.0 * sc) * audio_pulse - angle * (12.0 * sc) + time * (2.5 + speed * 3.0)) / sc;
        sc *= 2.0;
    }

    // Smooth HSV hue rotation
    let hue = value * 0.5 + time * 0.5 * (1.0 + bass * 0.3);
    let spiralColor = hsv2rgb(vec3<f32>(fract(hue), 0.9, 1.0));

    // High contrast and brightness for psychedelic pop
    let generated_color = pow(spiralColor, vec3<f32>(0.7)) * 3.0 * (0.5 + intensity);

    // Alpha falloff at outer edges
    let edge_fade = 1.0 - smoothstep(0.25, 0.55, dist);
    let opacity = 0.8 * edge_fade;

    // Add feedback trail for motion blur effect
    let colored = generated_color + history * 0.9;

    // ═══ BLEND WITH INPUT ═══
    let final_color = mix(inputColor.rgb, colored, opacity);
    let final_alpha = max(inputColor.a, opacity);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, final_alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(final_color, final_alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
