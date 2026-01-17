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

    // Mouse controls the direction and strength of the stretch
    // Default to a slight vertical drift if mouse not active
    var mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // If mouse is at 0,0 (often initialization state), center it
    if (mousePos.x == 0.0 && mousePos.y == 0.0) {
        mousePos = vec2<f32>(0.5, 0.5);
    }

    // Direction vector from center to mouse
    let direction = mousePos - vec2<f32>(0.5, 0.5);
    let dist = length(direction);

    // Sample original color to get luminance
    let originalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = getLuminance(originalColor);

    // Threshold: only stretch bright pixels
    let threshold = 0.3;
    var displacement = vec2<f32>(0.0);

    if (luma > threshold) {
        // The brighter the pixel, the more it gets pulled along the mouse direction
        // Multiply by a factor to exaggerate the effect
        displacement = direction * (luma - threshold) * 2.0;

        // Add some noise/glitchiness based on time and y-coord
        let noise = sin(uv.y * 100.0 + time * 5.0) * 0.005;
        displacement.x = displacement.x + noise;
    }

    let sourceUV = uv - displacement;

    // Bounds check not strictly needed as samplers usually clamp/repeat, but good practice
    // However, textureSampleLevel handles it.

    var finalColor = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);

    // Add a slight chromatic aberration at the edges of the stretch
    if (length(displacement) > 0.01) {
        let r = textureSampleLevel(readTexture, u_sampler, sourceUV + displacement * 0.1, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, sourceUV - displacement * 0.1, 0.0).b;
        finalColor = vec4<f32>(r, finalColor.g, b, finalColor.a);
    }

    textureStore(writeTexture, global_id.xy, finalColor);
}
