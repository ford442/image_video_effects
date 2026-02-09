struct Uniforms {
  config: vec4&lt;f32&gt;,
  zoom_config: vec4&lt;f32&gt;,
  zoom_params: vec4&lt;f32&gt;,
  ripples: array&lt;vec4&lt;f32&gt;, 50&gt;,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d&lt;f32&gt;;
@group(0) @binding(2) var writeTexture: texture_storage_2d&lt;rgba32float, write&gt;;
@group(0) @binding(3) var&lt;uniform&gt; u: Uniforms;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3&lt;u32&gt;) {
    let resolution = u.config.zw;
    let uv = vec2&lt;f32&gt;(global_id.xy) / resolution;
    let time = u.config.x * 0.1;
    let mouse = vec2&lt;f32&gt;(u.zoom_config.y, 1.0 - u.zoom_config.z); // Flip Y for typical coord

    // Multiple sine waves for plasma
    var plasma = 0.0;
    plasma += sin(uv.x * 3.14159 * 3.0 + time) * sin(uv.y * 3.14159 * 3.0 + time * 1.23);
    plasma += sin(uv.x * 3.14159 * 5.0 + time * 0.8) * sin(uv.y * 3.14159 * 5.0 + time * 1.5) * 0.5;
    plasma += sin(uv.x * 3.14159 * 8.0 + time * 1.7) * sin(uv.y * 3.14159 * 8.0 + time * 2.3) * 0.25;
    plasma /= 1.75;

    // Mouse distortion
    let dist = distance(uv, mouse);
    let warp = 0.1 * exp(-dist * 8.0);
    let warped_uv = uv + vec2(plasma * warp, plasma * warp * 0.7);

    // Color cycle
    let r = sin(warped_uv.x * 12.0 + time * 1.1) * 0.5 + 0.5;
    let g = sin(warped_uv.y * 12.0 + time * 1.37) * 0.5 + 0.5;
    let b = sin((warped_uv.x + warped_uv.y) * 8.0 + time * 1.5) * 0.5 + 0.5;

    var color = vec3&lt;f32&gt;(r, g, b) * (0.8 + plasma * 0.4);

    // Glow towards center/mouse
    color += 0.3 / (1.0 + dist * 10.0);

    textureStore(writeTexture, global_id.xy, vec4&lt;f32&gt;(color, 1.0));
}
