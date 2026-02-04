// ═══════════════════════════════════════════════════════════════
//  Rorschach Inkblot
//  Creates a symmetrical, ink-like fluid effect reminiscent of psychological tests.
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Unused
  zoom_params: vec4<f32>,  // x=Threshold, y=Distortion, z=Smoothness, w=Invert
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pp = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(pp);
        pp = rot * pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Parameters
    let threshold = u.zoom_params.x;     // 0.0 to 1.0
    let distStr = u.zoom_params.y * 0.5; // Distortion strength
    let smoothness = u.zoom_params.z * 0.2; // Edge softness
    let invert = u.zoom_params.w;        // > 0.5 means White on Black instead of Black on White

    // Calculate Symmetry
    // Use Mouse X to define the axis of symmetry. Default to center if mouse is at 0,0 (start)
    var center = mouse.x;
    if (center == 0.0) { center = 0.5; }

    // Mirror UVs
    // We want to mirror the "active" side (usually the larger side or just left) to the other.
    // Let's mirror the Left side onto the Right side relative to the axis.
    // If uv.x > center, we sample from center - (uv.x - center) = 2*center - uv.x

    var sym_uv = uv;
    // Simple absolute symmetry around center
    sym_uv.x = center - abs(uv.x - center);

    // Apply Fluid Distortion (FBM)
    // Animate the domain to make the ink flow
    let noise_uv = sym_uv * 3.0 + vec2<f32>(0.0, time * 0.2);
    let n = fbm(noise_uv);

    // Displace the sampling UV
    // Use noise gradient or just noise value for offset
    let displace = (n - 0.5) * distStr;
    let sample_uv = sym_uv + vec2<f32>(displace);

    // Sample texture
    let color = textureSampleLevel(readTexture, u_sampler, clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // Convert to Grayscale / Luminance
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Thresholding to create Ink look
    // Smoothstep creates the blurry ink edge
    // "Ink" is dark. So if luma < threshold, it's ink.
    // We want 1.0 where it is PAPER (light), 0.0 where it is INK (dark).

    var paper = smoothstep(threshold - smoothness, threshold + smoothness, luma);

    // Add paper texture/grain?
    let grain = hash(uv * 100.0 + time) * 0.05;
    paper = clamp(paper - grain, 0.0, 1.0);

    var finalColor = vec3<f32>(paper); // White paper, Black ink

    // Invert option (Glowing Ink on Dark)
    if (invert > 0.5) {
        finalColor = 1.0 - finalColor;
        // Maybe tint the glowing ink?
        finalColor *= vec3<f32>(0.8, 0.9, 1.0); // Blueish tint
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
