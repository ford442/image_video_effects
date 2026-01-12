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

fn hash(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let decayRate = u.zoom_params.x;
    let noiseScale = u.zoom_params.y * 50.0 + 10.0;
    let spread = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Mold grows where mouse is
    // Use noise to make edges irregular
    let n = noise(uv * noiseScale + time * 0.1);
    // Mask is 1.0 near mouse, fades out. Noise adds jagged edges.
    let mask = smoothstep(spread, max(0.0, spread - 0.2), dist + (n * 0.1 - 0.05));

    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    if (mask > 0.0) {
        // Apply mold effect
        // Greenish tint
        let moldColor = vec4<f32>(0.2, 0.8, 0.3, 1.0);

        // Decay/Pixelate
        let pixelSize = 10.0 / noiseScale; // Inverse scale for pixel size
        let pixelUV = floor(uv / pixelSize) * pixelSize;
        let pixelColor = textureSampleLevel(readTexture, u_sampler, pixelUV, 0.0);

        // Darken and shift
        let decayed = mix(pixelColor, moldColor, colorShift);

        // Apply based on mask intensity and decay rate
        color = mix(color, decayed, mask * decayRate);
    }

    textureStore(writeTexture, global_id.xy, color);
}
