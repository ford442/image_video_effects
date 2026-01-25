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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Petals, y=Complexity, z=Rotation, w=Thickness
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Aspect ratio correction for circular patterns
    let aspect = resolution.x / resolution.y;
    let center = mouse;
    let p = (uv - center) * vec2<f32>(aspect, 1.0);

    let r = length(p);
    let a = atan2(p.y, p.x);

    // Parameters
    let petals = 3.0 + floor(u.zoom_params.x * 12.0);
    let complexity = 1.0 + u.zoom_params.y * 10.0;
    let speed = u.zoom_params.z * 2.0;
    let thickness = 0.05 + u.zoom_params.w * 0.45; // Thickness of the "ink" lines

    // Guilloche / Spirograph Pattern
    // We create a field where values oscillate based on angle and radius
    let wave1 = sin(a * petals + time * speed);
    let wave2 = cos(a * petals * 2.0 - time * speed * 1.5);
    let wave3 = sin(r * 20.0 * complexity);

    // Complex interference pattern
    let val = sin(r * 30.0 + wave1 * 5.0 + wave2 * 2.0) + wave3 * 0.5;

    // Determine mask from pattern
    // We want thin lines. smoothstep around 0.
    // But "Reveal" implies we see the image THROUGH the lines.
    // Let's make the lines the "clear" part.

    // Normalize val roughly to -1.5 to 1.5
    // Let's take absolute value to make ridges
    let lineField = abs(val);

    // Invert so 0 is strong (center of line)
    // thickness controls how wide the "gap" is.
    let mask = 1.0 - smoothstep(0.0, thickness, lineField);

    // Sample Image
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Background style (Paper / Sketch)
    // Desaturate and tint
    let gray = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let paper = vec3<f32>(0.95, 0.9, 0.85) * (0.5 + 0.5 * gray); // Faded sepia version

    // Mix
    // mask = 1.0 -> Show original color (The Ink)
    // mask = 0.0 -> Show paper

    // Add a bit of distance fading so the effect is localized to mouse?
    // Let's keep it full screen centered on mouse, but maybe fade out the intensity of the effect far away?
    // Actually, spirographs are local.
    let fade = smoothstep(0.8, 0.3, r); // Fade out at edges of screen/radius

    let finalMask = mask * fade;

    // If mask is 0 (paper), we see paper. If mask is 1 (line), we see color.
    // Also, let's allow seeing the original image faintly in the background instead of pure paper?
    // let bg = mix(paper, color, 0.1);

    let outColor = mix(paper, color, finalMask);

    textureStore(writeTexture, global_id.xy, vec4<f32>(outColor, 1.0));
}
