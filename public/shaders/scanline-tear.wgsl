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
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let mousePos = u.zoom_config.yz;

    // Params
    let tearWidth = u.zoom_params.x * 0.2 + 0.01; // Height of the horizontal band
    let tearStrength = u.zoom_params.y; // Horizontal displacement amount
    let jitter = u.zoom_params.z;
    let recovery = u.zoom_params.w;

    // Logic
    // Scanlines are horizontal lines.
    // If the scanline Y is close to Mouse Y, displace X.

    let distY = abs(uv.y - mousePos.y);

    // Gaussian falloff for the tear band
    let tearMask = exp(-pow(distY / tearWidth, 2.0));

    // Direction: Pull towards mouse X? Or just jitter?
    // Let's pull towards mouse X, but with noise.

    // Noise
    let noise = fract(sin(dot(vec2<f32>(uv.y, time), vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let jitterOffset = (noise - 0.5) * jitter * tearMask;

    // Drag offset
    // If mouse is to the right of center, drag right.
    // But relative to pixel?
    // Let's create a "tear" where the image shifts to align with mouse X at that row.
    let drag = (mousePos.x - 0.5) * tearStrength * tearMask;

    let totalOffset = drag + jitterOffset;

    // Sample
    let sampleUV = vec2<f32>(uv.x - totalOffset, uv.y);

    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Add some chromatic aberration in the tear
    if (tearMask > 0.1) {
        let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(0.01 * tearStrength, 0.0), 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(0.01 * tearStrength, 0.0), 0.0).b;
        color = vec4<f32>(r, color.g, b, 1.0);

        // brighten the tear line
        color = color + vec4<f32>(0.1, 0.1, 0.1, 0.0) * tearMask;
    }

    textureStore(writeTexture, global_id.xy, color);

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
