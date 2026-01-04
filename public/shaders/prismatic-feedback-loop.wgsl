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
  config: vec4<f32>;       // x=Time, y=PassNumber, z=ResX, w=ResY
  zoom_config: vec4<f32>;  // x=clickIntensity, y=mouseX, z=mouseY, w=aberration
  zoom_params: vec4<f32>;  // x=feedbackAmount, y=blurRadius, z=glowIntensity, w=chromaticSpread
  ripples: array<vec4<f32>, 50>;
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = vec2<f32>(u.zoom_config.y / resolution.x, u.zoom_config.z / resolution.y);
    let aberration = u.zoom_config.w;

    // Sample displacement strength from Pass 1
    let displacementStrength = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Create displacement vector from mouse and displacement field
    let mouseDir = normalize(uv - mousePos);
    let displacedUV = uv + mouseDir * displacementStrength * 0.1;

    // Temporal feedback: sample previous frame with displacement
    let feedbackColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // Chromatic aberration: split RGB channels
    let spread = u.zoom_params.w * aberration;
    let r = textureSampleLevel(readTexture, u_sampler, displacedUV + vec2<f32>(spread, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, displacedUV - vec2<f32>(spread, 0.0), 0.0).b;
    let aberrantColor = vec3<f32>(r, g, b);

    // Multi-sample blur for glow
    let blurRadius = u.zoom_params.y;
    var glow = vec3<f32>(0.0);
    var count = 0.0;
    for (var i: i32 = -2; i <= 2; i = i + 1) {
        for (var j: i32 = -2; j <= 2; j = j + 1) {
            let offset = vec2<f32>(f32(i), f32(j)) * blurRadius * 0.01;
            let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let w = 1.0 / (length(vec2<f32>(f32(i), f32(j))) + 1.0);
            glow = glow + textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb * w;
            count = count + w;
        }
    }
    glow = glow / max(count, 1.0);

    // Mix feedback, aberration, and glow
    let base = mix(aberrantColor, feedbackColor, u.zoom_params.x);
    let finalColor = base + glow * u.zoom_params.z * displacementStrength;

    // Store final output and clear depth
    textureStore(writeTexture, vec2<u32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 0.0));
}