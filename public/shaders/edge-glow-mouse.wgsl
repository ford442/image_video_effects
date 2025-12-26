// --- EDGE GLOW MOUSE ---
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

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn sobel(uv: vec2<f32>, step: vec2<f32>) -> f32 {
    let t = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -step.y), 0.0).rgb);
    let b = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, step.y), 0.0).rgb);
    let l = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-step.x, 0.0), 0.0).rgb);
    let r = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, 0.0), 0.0).rgb);

    let gx = -l + r;
    let gy = -t + b;

    return sqrt(gx*gx + gy*gy);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let step = 1.0 / resolution;

    // Params
    let threshold = u.zoom_params.x;      // Edge threshold
    let glowRadius = u.zoom_params.y;     // Mouse influence
    let intensity = u.zoom_params.z * 5.0;// Glow Intensity
    let colorSpeed = u.zoom_params.w;     // Color cycle

    // Mouse
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let dist = distance(uv * aspectVec, mouse * aspectVec);

    // Original Color
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Edge Detection
    let edgeVal = sobel(uv, step);
    let edge = smoothstep(threshold, threshold + 0.1, edgeVal);

    // Mouse Influence Mask
    // 1.0 at mouse, 0.0 at radius
    let mask = smoothstep(glowRadius, 0.0, dist);

    // Glow Color
    let hue = fract(u.config.x * colorSpeed + dist);
    let glowColor = hsv2rgb(vec3<f32>(hue, 1.0, 1.0));

    // Combine
    // If edge detected AND near mouse, we add glow.
    // If not near mouse, we might just show original or slight edge.

    // Make background darker near mouse to make glow pop
    let darkness = 1.0 - (mask * 0.8);
    var finalColor = baseColor.rgb * darkness;

    // Add Glow
    finalColor += glowColor * edge * intensity * mask;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, baseColor.a));

    // Passthrough Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
