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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GlitchIntensity, y=ColorShift, z=NegativeStr, w=SplitAngle
  ripples: array<vec4<f32>, 50>,
};

// Split Dimension
// Param 1: Glitch Intensity
// Param 2: Color Shift
// Param 3: Negative Strength
// Param 4: Split Angle

fn get_mouse() -> vec2<f32> {
    var mouse = u.zoom_config.yz;
    if (mouse.x < 0.0) { return vec2<f32>(0.5, 0.5); }
    return mouse;
}

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = get_mouse();

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let glitch_amt = u.zoom_params.x * (1.0 + bass * 0.3 + treble * 0.15);
    let color_shift = u.zoom_params.y * (1.0 + mids * 0.1);
    let neg_str = u.zoom_params.z;
    let angle_param = u.zoom_params.w;

    let time = u.config.x;

    // Calculate Split Line
    let angle = angle_param * 3.14159 * 0.5;
    let normal = vec2<f32>(cos(angle), sin(angle));

    let p_vec = vec2<f32>((uv.x - mouse.x) * aspect, uv.y - mouse.y);
    let d = dot(p_vec, normal);

    // Normal side
    let normalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Glitch side
    let n = noise(vec2<f32>(uv.y * 50.0, time * 20.0));
    let glitchActive = select(0.0, 1.0, n > 0.8 && glitch_amt > 0.0);
    let glitchOffset = (n - 0.5) * glitch_amt * 0.2 * glitchActive;
    var glitch_uv = uv;
    glitch_uv.x = glitch_uv.x + glitchOffset;

    let shift = color_shift * 0.05;
    var col = vec3<f32>(0.0);
    col.r = textureSampleLevel(readTexture, u_sampler, glitch_uv + vec2<f32>(shift, 0.0), 0.0).r;
    col.g = textureSampleLevel(readTexture, u_sampler, glitch_uv, 0.0).g;
    col.b = textureSampleLevel(readTexture, u_sampler, glitch_uv - vec2<f32>(shift, 0.0), 0.0).b;
    col = mix(col, 1.0 - col, neg_str);

    var glitchColor = vec4<f32>(col, 1.0);

    // Add split line highlight
    let lineHighlight = select(vec4<f32>(0.5, 0.5, 0.5, 0.0), vec4<f32>(0.0), d >= 0.01);
    glitchColor = glitchColor + lineHighlight;

    let isNormal = select(0.0, 1.0, d < 0.0);
    let finalColor = mix(glitchColor, normalColor, isNormal);

    // Alpha: glitch dimension = effect intensity drives blend; normal dimension = source luma
    let luma = dot(finalColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let alphaNormal = clamp(luma * 0.7 + 0.2, 0.0, 1.0);
    let alphaGlitch = clamp(glitch_amt * 0.3 + luma * 0.5 + 0.15, 0.0, 1.0);
    let alpha = mix(alphaGlitch, alphaNormal, isNormal);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(finalColor.rgb, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor.rgb, alpha));
}
