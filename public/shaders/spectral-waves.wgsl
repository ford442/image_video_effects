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
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    let uv = vec2<f32>(global_id.xy) / dims;
    let aspect = dims.x / dims.y;
    let time = u.config.x;

    // Parameters
    let frequency = 10.0 + u.zoom_params.x * 90.0; // 10 to 100
    let speed = u.zoom_params.y * 5.0;            // 0 to 5
    let maxAmplitude = u.zoom_params.z * 0.1;     // 0 to 0.1 (strong displacement)
    let aberration = u.zoom_params.w * 0.05;      // 0 to 0.05

    let mousePos = u.zoom_config.yz;

    // Correct aspect for distance calculation
    let uv_c = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_c = vec2<f32>(mousePos.x * aspect, mousePos.y);
    let dist = distance(uv_c, mouse_c);

    // Sample luminance at current point to modulate wave
    let centerColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = getLuminance(centerColor);

    // Wave function: expanding rings
    // Amplitude is modulated by image luminance (bright areas = stronger waves)
    let wave = sin(dist * frequency - time * speed);
    let displacement = wave * maxAmplitude * luma;

    // Direction away from mouse
    let dir = normalize(uv_c - mouse_c);
    let safeDir = select(vec2<f32>(0.0), dir, dist > 0.001);

    // Calculate new UVs with chromatic aberration
    // Red channel displaced positively, Blue negatively along the wave normal
    let uv_r = uv - safeDir * displacement * (1.0 + aberration);
    let uv_g = uv - safeDir * displacement;
    let uv_b = uv - safeDir * displacement * (1.0 - aberration);

    let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    var finalColor = vec3<f32>(r, g, b);

    // Add a highlight/specular on the wave peaks
    let highlight = smoothstep(0.8, 1.0, wave) * luma * 0.5;
    finalColor += vec3<f32>(highlight);

    // Vignette based on distance from mouse? No, keep it clean.

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
