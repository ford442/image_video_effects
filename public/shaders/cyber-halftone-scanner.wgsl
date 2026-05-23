// ═══════════════════════════════════════════════════════════════════
//  Cyber Halftone Scanner
//  Category: image
//  Features: rotated screens, scanline, audio-reactive, plasma-tint, upgraded-rgba
//  Complexity: Medium
//  Phase B / Algorithmist
// ═══════════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,  // x=DotScale, y=ScanSpeed, z=Separation, w=Brightness
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;

fn grid(uv: vec2<f32>, angle: f32, scale: f32) -> f32 {
    let s = sin(angle);
    let c = cos(angle);
    let rot = mat2x2<f32>(c, -s, s, c);
    let st = (rot * uv) * scale;
    return (sin(st.x) * sin(st.y)) * 0.5 + 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params — bass amplifies dot density and scan speed, treble boosts brightness
    let dotScale   = mix(50.0, 400.0, u.zoom_params.x) * (1.0 + bass * 0.2);
    let scanSpeed  = u.zoom_params.y * 2.0 * (1.0 + bass * 0.4);
    let sep        = u.zoom_params.z * 0.05;
    let brightness = u.zoom_params.w * 2.0 * (1.0 + treble * 0.2);

    // Scanline
    let scanY = fract(time * scanSpeed * 0.5);
    let scanDist = abs(uv.y - scanY);
    let scanIntensity = exp(-scanDist * scanDist * 90.0);

    // Sample texture with chromatic separation
    let texR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( sep,  sep), 0.0).r;
    let texG = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let texB = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>( sep,  sep), 0.0).b;

    // Canonical CMYK screen angles
    let patR = grid(uv, 15.0  * PI / 180.0, dotScale);
    let patG = grid(uv, 75.0  * PI / 180.0, dotScale);
    let patB = grid(uv,  0.0,                dotScale);
    let patK = grid(uv, 45.0  * PI / 180.0, dotScale * 1.05);

    let boost = scanIntensity * 0.4;
    let r = step(patR, texR * brightness + boost);
    let g = step(patG, texG * brightness + boost);
    let b = step(patB, texB * brightness + boost);
    let k = step(patK, dot(vec3<f32>(texR, texG, texB), vec3<f32>(0.299, 0.587, 0.114)) * brightness + boost);

    // Cyber-tinted
    let cyan    = vec3<f32>(0.0, 0.85, 1.0) * r;
    let magenta = vec3<f32>(1.0, 0.0, 0.7)  * g;
    let yellow  = vec3<f32>(1.0, 0.85, 0.0) * b;
    let halftone = (cyan + magenta + yellow) * (1.0 - k * 0.4);

    // Plasma palette tint along scan stripe
    let palIdx = u32(clamp((scanY + time * 0.05) * 255.0, 0.0, 255.0));
    let scanTint = plasmaBuffer[palIdx % 256u].rgb;
    let finalColor = halftone + scanTint * scanIntensity * 0.4;

    // Semantic alpha
    let coverage = (r + g + b) / 3.0;
    let alpha = clamp(coverage * 0.6 + scanIntensity * 0.3 + 0.1, 0.0, 1.0);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, alpha));
}
