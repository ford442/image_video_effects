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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let texel = 1.0 / vec2<f32>(resolution);

    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    // Params
    let edgeThreshold = u.zoom_params.x * 0.5;
    let glowIntensity = u.zoom_params.y * 3.0;
    let pulseSpeed = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    // Light falloff from mouse
    var light = 0.0;
    if (mouse.x >= 0.0) {
        light = 1.0 - smoothstep(0.0, 0.5, dist); // 0.5 radius light
    }

    // Sobel Edge Detection
    let gx = -1.0 * luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-1.0, -1.0) * texel, 0.0).rgb) +
             -2.0 * luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-1.0, 0.0) * texel, 0.0).rgb) +
             -1.0 * luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-1.0, 1.0) * texel, 0.0).rgb) +
              1.0 * luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(1.0, -1.0) * texel, 0.0).rgb) +
              2.0 * luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(1.0, 0.0) * texel, 0.0).rgb) +
              1.0 * luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(1.0, 1.0) * texel, 0.0).rgb);

    let gy = -1.0 * luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-1.0, -1.0) * texel, 0.0).rgb) +
             -2.0 * luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -1.0) * texel, 0.0).rgb) +
             -1.0 * luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(1.0, -1.0) * texel, 0.0).rgb) +
              1.0 * luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-1.0, 1.0) * texel, 0.0).rgb) +
              2.0 * luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, 1.0) * texel, 0.0).rgb) +
              1.0 * luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(1.0, 1.0) * texel, 0.0).rgb);

    let mag = sqrt(gx * gx + gy * gy);
    let isEdge = smoothstep(edgeThreshold, edgeThreshold + 0.1, mag);

    // Neon Color Calculation
    let time = u.config.x * (1.0 + pulseSpeed * 2.0);
    // Hue varies by distance to mouse + time
    let hue = fract(colorShift + dist * 0.5 - time * 0.1);
    let neonColor = hsv2rgb(vec3<f32>(hue, 1.0, 1.0));

    // Combine
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // We want the edges to glow, and the glow to be stronger near mouse
    let finalGlow = neonColor * isEdge * glowIntensity * (0.2 + 0.8 * light);

    // Mix with dark original
    let outColor = mix(original * 0.1, finalGlow, isEdge * (0.5 + 0.5 * light));

    textureStore(writeTexture, global_id.xy, vec4<f32>(outColor, 1.0));

    // Depth passthrough
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
