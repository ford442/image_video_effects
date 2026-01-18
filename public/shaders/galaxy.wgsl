// Uniforms: time, zoom, panX, panY
// Sampler for the texture
@group(0) @binding(0) var u_sampler: sampler;

// Input texture from a video or image
@group(0) @binding(2) var inputTexture: texture_2d<f32>;
@group(0) @binding(3) var<uniform> uniforms : vec4<f32>;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) fragUV: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> VertexOutput {
    var output: VertexOutput;
    // Create a full-screen quad
    let x = f32(in_vertex_index / 2u) * 4.0 - 1.0;
    let y = f32(in_vertex_index % 2u) * 4.0 - 1.0;
    output.position = vec4<f32>(x, -y, 0.0, 1.0);

    // Create base UV coordinates (0.0 to 1.0)
    var uv = vec2<f32>((x + 1.0) * 0.5, (y + 1.0) * 0.5);

    // Apply zoom and pan from uniforms
    // uniforms.y = zoom, uniforms.z = panX, uniforms.w = panY
    uv = (uv - 0.5) / uniforms.y; // Zoom
    uv += vec2<f32>(uniforms.z - 0.5, uniforms.w - 0.5); // Pan

    output.fragUV = uv;
    return output;
}

@fragment
fn fs_main(@location(0) fragUV: vec2<f32>) -> @location(0) vec4<f32> {
    let time = uniforms.x;

    // Create a simple animated color pattern
    let color1 = vec3<f32>(sin(fragUV.x * 20.0 + time), cos(fragUV.y * 20.0 + time), 0.5);
    let color2 = vec3<f32>(0.1, 0.2, 0.4);
    let pattern = mix(color1, color2, smoothstep(0.4, 0.6, sin(length(fragUV - 0.5) * 15.0 + time)));

    // Sample the input texture
    let textureColor = textureSample(inputTexture, u_sampler, fragUV);

    // Mix the generated pattern with the input texture
    let finalColor = mix(pattern, textureColor.rgb, 0.6);

    return vec4<f32>(finalColor, 1.0);
}
