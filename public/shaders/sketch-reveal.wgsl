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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Sobel Edge Detection
    let step = 1.0 / resolution;
    let tl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-step.x, -step.y), 0.0).rgb;
    let t  = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -step.y), 0.0).rgb;
    let tr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, -step.y), 0.0).rgb;
    let l  = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-step.x, 0.0), 0.0).rgb;
    let r  = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, 0.0), 0.0).rgb;
    let bl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-step.x, step.y), 0.0).rgb;
    let b  = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, step.y), 0.0).rgb;
    let br = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, step.y), 0.0).rgb;

    // Convert to grayscale for edge detection
    let lum = vec3<f32>(0.299, 0.587, 0.114);
    let gx = dot(-tl - 2.0*l - bl + tr + 2.0*r + br, lum);
    let gy = dot(-tl - 2.0*t - tr + bl + 2.0*b + br, lum);

    let edgeStrength = u.zoom_params.y * 3.0 + 0.5;
    let edge = sqrt(gx*gx + gy*gy) * edgeStrength;

    let contrast = u.zoom_params.z * 2.0 + 0.5;
    let sketchVal = 1.0 - pow(clamp(edge, 0.0, 1.0), contrast);

    // Create pencil sketch look (black lines on white/paper)
    // We can add a slight paper tint if we want, but white is fine.
    let sketchColor = vec4<f32>(vec3<f32>(sketchVal), 1.0);

    // Original Color
    let originalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Mouse Reveal
    let mousePos = u.zoom_config.yz;
    let aspectRatio = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspectRatio, 1.0);
    let dist = length(distVec);

    let brushSize = u.zoom_params.x * 0.4 + 0.05;
    let softness = u.zoom_params.w * 0.2 + 0.01;

    let revealMask = 1.0 - smoothstep(brushSize, brushSize + softness, dist);

    // Mix
    let finalColor = mix(sketchColor, originalColor, revealMask);

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
