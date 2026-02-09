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
    let uv = (vec2&lt;f32&gt;(global_id.xy) / resolution - 0.5) * 2.5;
    let time = u.config.x * 0.02;
    let mouse = vec2&lt;f32&gt;(u.zoom_config.y * 2.0 - 1.0, (1.0 - u.zoom_config.z) * 2.0 - 1.0);

    let aspect = resolution.x / resolution.y;
    var c = vec2&lt;f32&gt;(uv.x * aspect - 0.7, uv.y);
    c *= exp(-time * 0.3); // Slow zoom
    c += mouse * 0.3 + vec2&lt;f32&gt;(sin(time * 0.5) * 0.1, cos(time * 0.7) * 0.05); // Animate center

    var z = vec2&lt;f32&gt;(0.0);
    var iter: u32 = 0u;
    loop {
        z = vec2&lt;f32&gt;(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        if (dot(z, z) &gt; 4.0 || iter &gt; 128u) {
            break;
        }
        iter++;
        continuing;
    }

    let i = f32(iter);
    let smooth = i + 1.0 - log2(log2(dot(z, z) + 1e-5) + 1e-5);

    // Color based on iteration
    let hue = fract(smooth / 128.0 + time * 0.1);
    let sat = 0.8 + 0.2 * sin(time);
    let val = 1.0 - smooth / 128.0;

    // Simple HSV to RGB approximation
    let h6 = hue * 6.0;
    let col_r = clamp(abs(h6 - 3.0) - 1.0, 0.0, 1.0);
    let col_g = clamp(2.0 * abs(h6 - 2.0) - 1.0, 0.0, 1.0);
    let col_b = clamp(1.0 - abs(h6 - 1.0) * 2.0, 0.0, 1.0);
    var color = 0.5 + 0.5 * vec3&lt;f32&gt;(col_r, col_g, col_b) * sat * val;

    // Dark background
    color = mix(vec3&lt;f32&gt;(0.0), color, smooth / 128.0);

    textureStore(writeTexture, global_id.xy, vec4&lt;f32&gt;(color, 1.0));
}
