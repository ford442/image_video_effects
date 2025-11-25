@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;

struct Uniforms {
  time: f32,
  resolutionX: f32,
  resolutionY: f32,
};

@group(0) @binding(3) var<uniform> u: Uniforms;



@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.resolutionX, u.resolutionY);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let rate = 0.5;
    let time = u.time * rate;
    let strength = 0.02;
    let frequency = 15.0;
    
    var d1 = sin(uv.x * frequency + time) * strength;
    var d2 = cos(uv.y * frequency * 0.7 + time) * strength;
    
    var displacedUV = uv + vec2<f32>(d1, d2);
    
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

    // This is the unique logic for this shader that makes it different.
    if (((color.r + color.g + color.b) / 3.0) > 0.75) {
        let bright_time = u.time * 0.65;
        d1 = sin(uv.x * frequency + bright_time) * strength;
        d2 = cos(uv.y * frequency * 0.7 + bright_time) * strength;
        let brightDisplacedUV = uv + vec2<f32>(d1, d2);
        color = mix(color, textureSampleLevel(readTexture, u_sampler, brightDisplacedUV, 0.0), 0.25);
    }

    if (((color.r + color.g + color.b) / 3.0) < 0.25) {
        let dark_time = u.time * 0.45;
        d1 = sin(uv.x * frequency + dark_time) * strength;
        d2 = cos(uv.y * frequency * 0.7 + dark_time) * strength;
        let darkDisplacedUV = uv + vec2<f32>(d1, d2);
        color = mix(color, textureSampleLevel(readTexture, u_sampler, darkDisplacedUV, 0.0), 0.75);
    }

    textureStore(writeTexture, global_id.xy, color);
}
