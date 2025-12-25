
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Helper for hue rotation
fn hueShift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(shift * 6.28318);
    return vec3<f32>(color * cosAngle + cross(k, color) * sin(shift * 6.28318) + k * dot(k, color) * (1.0 - cosAngle));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let decay = u.zoom_params.x; // Trail Decay
    let threshold = u.zoom_params.y; // Edge Sense
    let hueParam = u.zoom_params.z; // Color Shift Base
    let echoMix = u.zoom_params.w; // Mix Strength

    // Current Frame
    let currentColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // History Frame (Previous state)
    let historyColor = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

    // Calculate Luminance/Edge
    let luma = dot(currentColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Simple neighbor sampling for edge detection (Sobel-ish approximation)
    let offset = 1.0 / resolution;
    let left = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-offset.x, 0.0), 0.0);
    let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset.x, 0.0), 0.0);
    let up = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -offset.y), 0.0);
    let down = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, offset.y), 0.0);

    let edgeX = length(right.rgb - left.rgb);
    let edgeY = length(down.rgb - up.rgb);
    let edgeStrength = sqrt(edgeX * edgeX + edgeY * edgeY);

    // Determine if we should spawn a new "echo" pixel
    var newEcho = vec3<f32>(0.0);

    if (edgeStrength > threshold) {
        // Calculate dynamic color based on Mouse Pos and Time
        let mouseX = u.zoom_config.y;
        let mouseY = u.zoom_config.z;
        let distToMouse = distance(uv, vec2<f32>(mouseX, mouseY));

        // Base color can be the input pixel, or a synthesized neon color
        let baseHue = hueParam + u.config.x * 0.1 + distToMouse; // Cycle over time and space

        // Create a vibrant color from hue
        // Simple HSV-like generation or just tinting the original
        let tint = hueShift(vec3<f32>(1.0, 0.0, 0.0), baseHue);

        newEcho = currentColor.rgb * tint * 2.0; // Boost brightness
    }

    // Combine history with decay
    // Fade out old history
    let fadedHistory = historyColor.rgb * (1.0 - decay * 0.1);

    // Add new echo
    let resultRGB = max(fadedHistory, newEcho * echoMix); // Use max to keep bright trails

    let finalColor = vec4<f32>(resultRGB, 1.0);

    // Write to history buffer for next frame
    textureStore(dataTextureA, global_id.xy, finalColor);

    // Write to display
    // Blend with original video? Or replace?
    // Let's blend: Original video + Trails
    // But if we want strong effect, maybe just trails over black?
    // Let's do: Original Video + Trails (Screen Blend)

    let displayColor = 1.0 - (1.0 - currentColor.rgb) * (1.0 - resultRGB);

    textureStore(writeTexture, global_id.xy, vec4<f32>(displayColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
