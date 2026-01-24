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
  config: vec4<f32>,       // x=Time, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Simple noise
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Hue to RGB
fn hue_to_rgb(h: f32) -> vec3<f32> {
    let r = abs(h * 6.0 - 3.0) - 1.0;
    let g = 2.0 - abs(h * 6.0 - 2.0);
    let b = 2.0 - abs(h * 6.0 - 4.0);
    return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    // Mouse interaction for light direction / foil tilt
    let mouse = u.zoom_config.yz;
    let tilt = (mouse - 0.5) * 2.0; // -1 to 1

    // Sample texture and calculate luminance
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));

    // Calculate normal from luminance gradient
    let offset = 1.0 / resolution;
    let lum_r = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lum_u = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, offset.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Normal vector (perturbed by luminance)
    let normal = normalize(vec3<f32>(lum - lum_r, lum - lum_u, 0.05)); // 0.05 controls height intensity

    // View vector is effectively perpendicular to screen + tilt
    let view = normalize(vec3<f32>(0.0, 0.0, 1.0));

    // Light vector driven by mouse/tilt
    let light = normalize(vec3<f32>(-tilt.x, -tilt.y, 0.5));

    // Specular reflection
    let half_vec = normalize(light + view);
    let NdotH = max(dot(normal, half_vec), 0.0);
    let specular = pow(NdotH, 10.0); // Sharpness of reflection

    // Prismatic color shift based on viewing angle and position
    // We add some noise to simulate the "sparkle" of the foil
    let sparkle = hash(uv * 100.0) * 0.2;
    let prism_val = specular + (uv.x + uv.y) * 0.5 + time * 0.1 + sparkle;
    let rainbow = hue_to_rgb(fract(prism_val));

    // Foil mask: brighter areas get more foil effect
    let foil_mask = smoothstep(0.2, 0.8, lum);

    // Combine
    // Base image + Rainbow Specular
    // We mix them: Dark areas stay dark (or maybe dark foil), bright areas are shiny
    var final_color = mix(color, rainbow, specular * foil_mask * 0.8);

    // Add a bit of the rainbow to the base color based on tilt to simulate ambient iridescence
    final_color += rainbow * 0.1 * foil_mask;

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(final_color, 1.0));
}
