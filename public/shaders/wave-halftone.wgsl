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

// Wave Halftone
// Generates a halftone dot pattern where the grid itself is distorted by sine waves
// and influenced by the mouse.

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    // Params
    let dotSizeScale = 0.5 + u.zoom_params.x; // 0.5 to 1.5
    let gridDensity = 20.0 + u.zoom_params.y * 100.0; // 20 to 120
    let waveAmp = u.zoom_params.z * 0.1; // 0.0 to 0.1
    let waveSpeed = u.zoom_params.w * 5.0; // 0.0 to 5.0

    // Mouse Interaction
    let dToMouse = uv - mousePos;
    let mouseDist = length(dToMouse);

    // Mouse creates a "bulge" or lens effect by pushing the grid coordinates
    let mouseForce = smoothstep(0.3, 0.0, mouseDist) * 0.05;
    let mouseDir = normalize(dToMouse);
    // Safety for 0 length
    var safeDir = vec2<f32>(0.0);
    if (mouseDist > 0.001) { safeDir = mouseDir; }

    // Wave function
    let waveX = sin(uv.y * 10.0 + time * waveSpeed) * waveAmp;
    let waveY = cos(uv.x * 10.0 + time * waveSpeed * 0.8) * waveAmp;

    // Distort the UV used for grid calculation
    let distortedUV = uv + vec2<f32>(waveX, waveY) - (safeDir * mouseForce);

    // Grid Logic
    let gridUV = distortedUV * gridDensity;
    let gridIndex = floor(gridUV);
    let gridFract = fract(gridUV); // 0..1 inside cell

    // Center of the cell in UV space (for sampling color)
    let cellCenterUV = (gridIndex + 0.5) / gridDensity;

    // Sample the image at the center of the cell
    // Use clamp sampler implicitly via standard sampler
    let color = textureSampleLevel(readTexture, u_sampler, cellCenterUV, 0.0);
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Dot Rendering
    // Distance from center of cell
    let dist = length(gridFract - 0.5);

    // Radius depends on luma
    // Mouse also magnifies the dots locally
    let mag = 1.0 + smoothstep(0.2, 0.0, mouseDist) * 1.0;
    let radius = luma * 0.5 * dotSizeScale * mag;

    // Smooth circle
    let mask = smoothstep(radius, radius - 0.1, dist);

    var finalColor = color * mask;
    finalColor.a = 1.0;

    textureStore(writeTexture, global_id.xy, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
}
