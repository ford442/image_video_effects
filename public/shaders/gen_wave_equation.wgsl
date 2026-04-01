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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let px = vec2<i32>(global_id.xy);

    // ═══ SAMPLE INPUT FROM PREVIOUS LAYER ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Wave physics parameters
    let damping = 0.995;
    let wave_speed = 0.5;
    let tension = 0.01;

    // Read height (R) and velocity (G)
    let current = textureLoad(dataTextureC, px, 0).rg;
    var height = current.r;
    var velocity = current.g;

    // Initialize flat surface
    if (abs(height) < 0.001 && abs(velocity) < 0.001) {
        height = 0.0;
        velocity = 0.0;
    }

    // Sample neighbors for Laplacian
    let n = textureLoad(dataTextureC, px + vec2<i32>(0, 1), 0).r;
    let s = textureLoad(dataTextureC, px + vec2<i32>(0, -1), 0).r;
    let e = textureLoad(dataTextureC, px + vec2<i32>(1, 0), 0).r;
    let w = textureLoad(dataTextureC, px + vec2<i32>(-1, 0), 0).r;

    let laplacian = (n + s + e + w - 4.0 * height) * 0.25;

    // Mouse creates wave pulses
    var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // FIX: Inverted smoothstep for safety
    // Original: smoothstep(0.15, 0.0, distance)
    // New: 1.0 - smoothstep(0.0, 0.15, distance)
    let mouse_impact = (1.0 - smoothstep(0.0, 0.15, distance(uv, mouse))) * u.zoom_config.w * 2.0;

    // Wave equation integration
    let acceleration = laplacian * wave_speed * wave_speed - height * tension;
    velocity = velocity * damping + acceleration;
    height = height + velocity + mouse_impact;

    // Visualize: deep water to foamy crests
    let t = height * 0.5 + 0.5;
    let waterColor = mix(
        vec3<f32>(0.05, 0.15, 0.3),
        vec3<f32>(0.9, 0.95, 1.0),
        smoothstep(0.0, 1.0, t)
    );
    let generatedColor = waterColor + vec3<f32>(0.3, 0.6, 1.0) * smoothstep(0.05, 0.15, abs(velocity)) * 0.5;

    // ═══ BLEND WITH INPUT ═══
    let opacity = 0.85;  // Wave overlay opacity
    let finalColor = mix(inputColor.rgb, generatedColor, opacity);
    let finalAlpha = max(inputColor.a, opacity);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(height, velocity, 0.0, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
