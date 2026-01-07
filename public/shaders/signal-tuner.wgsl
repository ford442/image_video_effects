struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 20>,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var u_sampler: sampler;
@group(0) @binding(4) var readDepthTexture: texture_depth_2d;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);

    // Params
    // x: Frequency
    // y: Amplitude
    // z: Speed (Drift)
    // w: Noise

    let freq = mix(5.0, 100.0, u.zoom_params.x);
    let amp = u.zoom_params.y * 0.1; // Max 0.1 displacement
    let speed = u.zoom_params.z * 5.0;
    let noiseAmt = u.zoom_params.w;

    let time = u.config.x;

    // Mouse Influence
    let aspect = u.config.z / u.config.w;
    let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouse = u.zoom_config.yz;
    let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);

    // Distance from mouse Y (horizontal band) or just distance?
    // Let's make it radial falloff from mouse.

    let dist = distance(uv_corrected, mouse_corrected);
    let mouseInfluence = smoothstep(0.5, 0.0, dist);

    // Wave
    // Vertical wave displacing X
    let wave = sin(uv.y * freq + time * speed) * amp;

    // Modulate wave by mouse influence
    let displacement = vec2<f32>(wave * mouseInfluence, 0.0);

    // Add noise if requested
    var noiseVal = 0.0;
    if (noiseAmt > 0.01) {
        noiseVal = (hash(uv * time) - 0.5) * noiseAmt * mouseInfluence;
    }

    let finalUV = uv + displacement + vec2<f32>(noiseVal, noiseVal);

    // RGB Split (Chromatic Aberration) based on Amplitude
    let split = amp * mouseInfluence * 0.5;

    let r = textureSampleLevel(readTexture, u_sampler, finalUV + vec2<f32>(split, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, finalUV - vec2<f32>(split, 0.0), 0.0).b;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(r, g, b, 1.0));
}
