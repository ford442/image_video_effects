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

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Sobel kernels
    let stepX = 1.0 / resolution.x;
    let stepY = 1.0 / resolution.y;

    let t_l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, -stepY), 0.0).rgb;
    let t_c = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -stepY), 0.0).rgb;
    let t_r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, -stepY), 0.0).rgb;
    let m_l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, 0.0), 0.0).rgb;
    let m_r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, 0.0), 0.0).rgb;
    let b_l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, stepY), 0.0).rgb;
    let b_c = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, stepY), 0.0).rgb;
    let b_r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, stepY), 0.0).rgb;

    // Use luminance for edge detection
    let gx = -1.0 * getLuminance(t_l) - 2.0 * getLuminance(m_l) - 1.0 * getLuminance(b_l) +
              1.0 * getLuminance(t_r) + 2.0 * getLuminance(m_r) + 1.0 * getLuminance(b_r);

    let gy = -1.0 * getLuminance(t_l) - 2.0 * getLuminance(t_c) - 1.0 * getLuminance(t_r) +
              1.0 * getLuminance(b_l) + 2.0 * getLuminance(b_c) + 1.0 * getLuminance(b_r);

    let edgeStrength = sqrt(gx * gx + gy * gy);

    // Mouse interaction: "Flashlight"
    let mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let aspect = resolution.x / resolution.y;

    // Correct distance for aspect ratio
    let distToMouse = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mousePos.x * aspect, mousePos.y));

    // Reveal radius
    let revealRadius = 0.3;
    let revealFalloff = 1.0 - smoothstep(0.0, revealRadius, distToMouse);

    // Base color is dark
    var finalColor = vec3<f32>(0.05, 0.05, 0.08); // Near black background

    // Neon color cycling
    let neonColor1 = vec3<f32>(1.0, 0.0, 0.8); // Magenta
    let neonColor2 = vec3<f32>(0.0, 1.0, 1.0); // Cyan
    let mixFactor = 0.5 + 0.5 * sin(time * 2.0 + uv.x * 3.0);
    let neonColor = mix(neonColor1, neonColor2, mixFactor);

    if (edgeStrength > 0.1) {
        // Boost edge
        let edge = smoothstep(0.1, 0.5, edgeStrength);

        // Intensity depends on mouse proximity
        // Near mouse: High intensity, full color
        // Far mouse: Low intensity or hidden

        // Let's make it always visible but glowing "hotter" near mouse
        let glow = 0.2 + 2.0 * revealFalloff;

        finalColor = mix(finalColor, neonColor * glow, edge);
    }

    // Blend a bit of original image near mouse so we can see what we are looking at
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    finalColor = mix(finalColor, original, revealFalloff * 0.5); // 50% opacity of original near mouse

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
