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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Noise, y=DistortionFreq, z=ColorBleed, w=Scanlines
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)),
                   hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)),
                   hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv_raw = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Params
    let noise_amt = u.zoom_params.x;
    let dist_freq = u.zoom_params.y * 50.0 + 1.0;
    let bleed_amt = u.zoom_params.z * 0.02;
    let scanline_intensity = u.zoom_params.w;

    // Mouse Inputs
    let mouse_x = u.zoom_config.y; // 0.0 to 1.0
    let mouse_y = u.zoom_config.z; // 0.0 to 1.0

    // Jog Wheel: Mouse X controls horizontal tear/distortion intensity
    let distortion_strength = pow(abs(mouse_x - 0.5) * 2.0, 2.0) * 0.5; // Stronger at edges
    let direction = sign(mouse_x - 0.5);

    // Tracking: Mouse Y controls vertical offset
    let vertical_tracking = (mouse_y - 0.5) * 0.2;

    // Apply Vertical Tracking (looping)
    var uv = uv_raw;
    uv.y = fract(uv.y + vertical_tracking + time * 0.05 * distortion_strength * direction);

    // Horizontal Distortion (Jitter)
    // Create 'bands' of distortion based on Y and Time
    let dist_wave = noise(vec2<f32>(uv.y * dist_freq, time * 20.0));
    // Threshold the wave to make it look like digital tearing
    let tear = smoothstep(0.4, 0.6, dist_wave) * distortion_strength;

    uv.x += (dist_wave - 0.5) * tear * 0.2;

    // Color Bleed (Chromatic Aberration)
    // R, G, B sampled at different X offsets
    let r_offset = bleed_amt * (1.0 + distortion_strength * 5.0);
    let b_offset = -bleed_amt * (1.0 + distortion_strength * 5.0);

    let r = textureSampleLevel(readTexture, u_sampler, fract(uv + vec2<f32>(r_offset, 0.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, fract(uv), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, fract(uv + vec2<f32>(b_offset, 0.0)), 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Static Noise
    let static_noise = hash12(uv * resolution + time);
    color += (static_noise - 0.5) * noise_amt;

    // Scanlines
    let scanline = sin(uv.y * resolution.y * 0.5 * 3.14159);
    color *= 1.0 - (scanline * scanline_intensity * 0.5);

    // Vignette / Tube curve (optional, keep it subtle)
    let d = distance(uv_raw, vec2<f32>(0.5));
    color *= 1.0 - d * 0.3;

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv_raw, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
