// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Pseudo-random hash
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let dotScale = mix(1.0, 4.0, u.zoom_params.x); // Noise frequency
    let contrast = mix(0.5, 2.0, u.zoom_params.y);
    let mouseRadius = mix(0.1, 0.5, u.zoom_params.z);
    let detailMix = u.zoom_params.w; // Blend original color

    // Mouse
    let mouse = u.zoom_config.yz;
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let mouseFactor = smoothstep(mouseRadius, 0.0, dist);

    // Source Color
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Dynamic Density: Higher density near mouse
    // We achieve this by scaling the UV fed into the hash function
    // High scale = smaller dots (conceptually, though here we are doing probability stippling)

    // Actually, "Stippling" is often: is rand() > luma? then black dot.
    // To make it look like dots, we compare against noise.

    // Near mouse: Fine grain (high frequency noise)
    // Far from mouse: Coarse grain (low frequency noise)
    let localScale = mix(resolution.y * 0.5, resolution.y * 2.0, mouseFactor * 0.8 + 0.2) * dotScale;

    let noise = hash21(floor(uv * localScale));

    // Adjust luma contrast
    let adjustedLuma = (luma - 0.5) * contrast + 0.5;

    // Stipple Logic
    // If noise < adjustedLuma, pixel is white (paper). Else black (ink).
    // Or: Ink density = 1.0 - luma. If rand < density -> draw dot.
    let inkDensity = 1.0 - clamp(adjustedLuma, 0.0, 1.0);

    var outColor = vec3<f32>(1.0); // Paper white
    if (noise < inkDensity) {
        outColor = vec3<f32>(0.05, 0.05, 0.1); // Ink dark blue/black
    }

    // Mix with original color based on mouse?
    // Let's mix in a bit of original color near mouse to "reveal" detail
    let finalColor = mix(vec4<f32>(outColor, 1.0), color, mouseFactor * detailMix);

    textureStore(writeTexture, global_id.xy, finalColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
