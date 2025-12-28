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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Params
    let edgeThreshold = u.zoom_params.x; // 0.0 to 1.0
    let pulseSpeed = u.zoom_params.y * 5.0;
    let glowIntensity = u.zoom_params.z * 5.0;
    let colorShift = u.zoom_params.w;

    // Mouse
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Sobel Kernels
    let stepX = 1.0 / resolution.x;
    let stepY = 1.0 / resolution.y;

    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -stepY), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, stepY), 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, 0.0), 0.0).rgb;

    let gradX = r - l;
    let gradY = b - t;

    let edge = sqrt(gradX * gradX + gradY * gradY);
    let edgeMag = length(edge); // Simple magnitude

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Pulse
    let pulse = (sin(time * pulseSpeed - dist * 10.0) + 1.0) * 0.5;

    // Mix
    var finalColor = original.rgb;

    // Only apply neon if edge is strong enough
    if (edgeMag > edgeThreshold * 0.2) { // Scale threshold
        // Neon color generation
        let hue = fract(time * 0.1 + colorShift + dist * 0.5);
        let neon = vec3<f32>(
            0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
            0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
            0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
        );

        // Intensity increases near mouse (flashlight)
        let mouseFactor = 1.0 / (dist * 5.0 + 0.2);

        finalColor = mix(finalColor, neon, clamp(edgeMag * glowIntensity * pulse * mouseFactor, 0.0, 1.0));
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
