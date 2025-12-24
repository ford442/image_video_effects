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

fn sobel(uv: vec2<f32>, step: vec2<f32>) -> f32 {
    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -step.y), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, step.y), 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-step.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, 0.0), 0.0).rgb;

    let tl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-step.x, -step.y), 0.0).rgb;
    let tr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, -step.y), 0.0).rgb;
    let bl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-step.x, step.y), 0.0).rgb;
    let br = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, step.y), 0.0).rgb;

    let gx = -tl + tr - 2.0 * l + 2.0 * r - bl + br;
    let gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;

    let mag = length(gx) + length(gy);
    return mag;
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    let uv = vec2<f32>(global_id.xy) / dims;
    let aspect = dims.x / dims.y;

    // Parameters
    let edgeStrength = u.zoom_params.x * 5.0; // 0.0 to 5.0
    let dragRadius = u.zoom_params.y;         // 0.0 to 1.0
    let glowIntensity = u.zoom_params.z * 2.0;// 0.0 to 2.0
    let colorShift = u.zoom_params.w;         // 0.0 to 1.0

    // Mouse interaction
    let mousePos = u.zoom_config.yz;
    let mouseActive = u.zoom_config.w; // 1.0 if down, but we can use position always for "mouse-driven"

    // Coordinate correction for distance
    let uv_c = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_c = vec2<f32>(mousePos.x * aspect, mousePos.y);

    let dist = distance(uv_c, mouse_c);

    // Drag/Warp effect based on distance
    // We warp the UV used for edge detection towards/away from mouse
    let warpAmount = smoothstep(dragRadius, 0.0, dist) * 0.2;
    let dir = normalize(uv_c - mouse_c);
    // Safety check for NaN
    let safeDir = select(vec2<f32>(0.0), dir, dist > 0.001);

    let warpUV = uv - safeDir * warpAmount;

    // Edge Detection
    let step = 1.0 / dims;
    let edge = sobel(warpUV, step);

    // Base Color
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    // Darken background to make neon pop
    color = color * 0.2;

    // Neon Glow Color
    // Cycle hue based on time and distance from mouse
    let hue = fract(u.config.x * 0.2 + dist * 2.0 + colorShift);
    let neonColor = hsv2rgb(vec3<f32>(hue, 0.8, 1.0));

    // Add glowing edges
    let glow = edge * edgeStrength * glowIntensity * smoothstep(1.0, 0.0, dist * 0.5); // Fade glow at distance

    color += neonColor * glow;

    // Extra: If mouse is close, invert the edge color for a "hot" core
    if (dist < 0.05) {
        color = mix(color, vec3<f32>(1.0) - color, 1.0 - dist/0.05);
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
