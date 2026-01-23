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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let texel = vec2<f32>(1.0) / resolution;

    // Params
    let steps = mix(5.0, 50.0, u.zoom_params.x); // Number of terraces
    let heightScale = mix(0.1, 5.0, u.zoom_params.y); // Height multiplier for normals
    let smoothness = u.zoom_params.z; // Mix between smooth and stepped normals
    let shadowStrength = u.zoom_params.w;

    // Mouse Light
    let mouse = u.zoom_config.yz;
    let lightPos = vec3<f32>(mouse * vec2<f32>(aspect, 1.0), 0.2); // Light is slightly above
    let pixelPos = vec3<f32>(uv * vec2<f32>(aspect, 1.0), 0.0);
    let lightDir = normalize(lightPos - pixelPos);

    // Height Map Function
    // We sample neighbors to get gradient
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(c.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Neighbors for gradient
    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0);
    let lumaT = dot(t.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lumaR = dot(r.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Gradients
    let dx = (lumaR - luma) * heightScale;
    let dy = (lumaT - luma) * heightScale; // Note: texture coord y is usually down, depends on convention.
    // Assuming Y down, then T is "up" visually but lower index.
    // Let's just use simple gradient.

    // Normal for Smooth Terrain
    let normalSmooth = normalize(vec3<f32>(-dx, -dy, 1.0));

    // Quantize Luma for Stepped Appearance
    let steppedLuma = floor(luma * steps) / steps;

    // If we want "Stepped Normals", we need gradient of stepped luma.
    // But sampling neighbors of stepped luma might be 0 most places and huge spikes at edges.
    // Let's stick to Smooth Normals for lighting, but use Stepped Luma for color.
    // This looks like painted terraces.

    // Alternatively: "Iso-Hills" usually implies the edges catch light.
    // Let's calculate the difference between quantized luma and neighbor quantized luma.
    let lumaT_step = floor(lumaT * steps) / steps;
    let lumaR_step = floor(lumaR * steps) / steps;

    let isEdge = abs(steppedLuma - lumaT_step) + abs(steppedLuma - lumaR_step);

    // Lighting
    let diffuse = max(dot(normalSmooth, lightDir), 0.0);

    // Color logic
    // Use the quantized luma to pick a color or darken the original color.
    // Let's keep original hue but quantize value.
    let hsvAdjust = c.rgb * (steppedLuma / max(luma, 0.001)); // Naive re-tint

    // Add shading
    var finalColor = hsvAdjust * (0.5 + 0.5 * diffuse);

    // Highlight edges?
    if (isEdge > 0.001) {
        finalColor = finalColor * 1.2; // Highlight
        // Or shadow?
        // finalColor = finalColor * 0.5;
    }

    // Apply mouse shadow/light strength
    finalColor = mix(finalColor, c.rgb, 1.0 - shadowStrength);

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
