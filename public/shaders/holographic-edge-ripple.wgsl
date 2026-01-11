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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=WaveSpeed, y=Frequency, z=Aberration, w=EdgeThreshold
  ripples: array<vec4<f32>, 50>,
};

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let texel = 1.0 / resolution;

    // Parameters
    let waveSpeed = u.zoom_params.x; // e.g. 2.0
    let frequency = u.zoom_params.y; // e.g. 20.0
    let aberration = u.zoom_params.z; // e.g. 0.02
    let edgeThreshold = u.zoom_params.w; // e.g. 0.2

    // Mouse Interaction
    let mousePos = u.zoom_config.yz; // Mouse coordinates (0-1)

    // Calculate aspect-corrected distance to mouse
    let aspect = resolution.x / resolution.y;
    let aspect_uv = vec2<f32>(uv.x * aspect, uv.y);
    let aspect_mouse = vec2<f32>(mousePos.x * aspect, mousePos.y);
    let dist = distance(aspect_uv, aspect_mouse);

    // Sobel Edge Detection
    let c00 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, -1.0), 0.0).rgb;
    let c10 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(0.0, -1.0), 0.0).rgb;
    let c20 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(1.0, -1.0), 0.0).rgb;
    let c01 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, 0.0), 0.0).rgb;
    let c21 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(1.0, 0.0), 0.0).rgb;
    let c02 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, 1.0), 0.0).rgb;
    let c12 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(0.0, 1.0), 0.0).rgb;
    let c22 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(1.0, 1.0), 0.0).rgb;

    let gx = -luminance(c00) - 2.0 * luminance(c10) - luminance(c20) + luminance(c02) + 2.0 * luminance(c12) + luminance(c22);
    let gy = -luminance(c00) - 2.0 * luminance(c01) - luminance(c02) + luminance(c20) + 2.0 * luminance(c21) + luminance(c22);
    let edgeVal = length(vec2<f32>(gx, gy));

    // Create edge mask
    let isEdge = smoothstep(edgeThreshold * 0.5, edgeThreshold, edgeVal);

    // Calculate Ripple
    let time = u.config.x * waveSpeed;
    let wave = sin(dist * frequency - time);

    // Apply Aberration (Shift RGB channels based on wave)
    // Stronger aberration closer to mouse
    let localAberration = aberration * (1.0 + isEdge * 2.0) * (1.0 / (dist + 0.1));

    let offsetR = vec2<f32>(localAberration * wave, 0.0);
    let offsetG = vec2<f32>(0.0, localAberration * wave);
    let offsetB = vec2<f32>(-localAberration * wave, -localAberration * wave);

    let colorR = textureSampleLevel(readTexture, u_sampler, uv + offsetR, 0.0).r;
    let colorG = textureSampleLevel(readTexture, u_sampler, uv + offsetG, 0.0).g;
    let colorB = textureSampleLevel(readTexture, u_sampler, uv + offsetB, 0.0).b;

    var finalColor = vec3<f32>(colorR, colorG, colorB);

    // Enhance edges with a glowing color
    let glowColor = vec3<f32>(0.5 + 0.5 * sin(time), 0.5 + 0.5 * cos(time * 0.7), 1.0);
    finalColor = mix(finalColor, glowColor, isEdge * 0.8 * abs(wave));

    // Output
    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
