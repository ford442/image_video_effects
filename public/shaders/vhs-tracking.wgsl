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

    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let tracking = u.zoom_params.x * 0.1; // Tracking error
    let noiseAmt = u.zoom_params.y * 0.05; // Static noise
    let colorDrift = u.zoom_params.z * 0.02; // RGB split
    let scanlineInt = u.zoom_params.w; // Scanline intensity

    // Mouse Interaction: Vertical position controls tracking frequency
    var trackingFreq = 5.0;
    var trackingPhase = 0.0;
    if (mouseDown > 0.5) {
       trackingFreq = 5.0 + mouse.y * 20.0;
       trackingPhase = mouse.x * 10.0;
    }

    // Tracking error (horizontal shear at specific y bands)
    let scanY = uv.y * 10.0 + time * trackingFreq + trackingPhase;
    let shiftX = sin(scanY) * tracking * step(0.95, sin(uv.y * 5.0 + time * 2.0)); // Occasional big shift

    // High frequency noise
    let noiseVal = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let noiseOffset = (noiseVal - 0.5) * noiseAmt;

    let distortedUV = uv + vec2<f32>(shiftX + noiseOffset, 0.0);

    // RGB Split
    let r = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(colorDrift, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, distortedUV - vec2<f32>(colorDrift, 0.0), 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Scanlines
    let scanline = sin(uv.y * resolution.y * 0.5) * 0.5 + 0.5;
    color = mix(color, color * scanline, scanlineInt * 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
