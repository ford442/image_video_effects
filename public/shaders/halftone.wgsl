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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=dotScale, y=contrast, z=colorMode 0=mono 1=CMYK, w=unused
  ripples: array<vec4<f32>, 50>,
};

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn circle(uv: vec2<f32>, center: vec2<f32>, radius: f32) -> f32 {
    let d = length(uv - center);
    return smoothstep(radius, radius - 0.01, d);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Grid size control
    let baseScale = mix(6.0, 64.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let grid = floor(uv * baseScale);
    let cellUv = (uv * baseScale) - grid;

    // Sample base color with slight jitter per-cell to avoid moire
    let jitter = (fract(sin(dot(grid, vec2<f32>(12.9898,78.233))) * 43758.5453) - 0.5) * 0.02;
    let sampleUv = (grid + vec2<f32>(0.5, 0.5) + jitter) / baseScale;
    let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUv, 0.0).rgb;

    // Determine dot radius by luminance (inverse: dark = big dot), adjust by contrast
    let lum = luminance(sampleColor);
    let contrast = mix(0.5, 1.5, clamp(u.zoom_params.y, 0.0, 1.0));
    let dotScale = clamp((1.0 - lum) * contrast, 0.0, 1.0);
    let radius = 0.5 * dotScale * 0.5; // relative to cell

    // Coordinates inside cell: centered at 0.5
    let center = vec2<f32>(0.5, 0.5);
    let c = circle(cellUv, center, radius);

    var outColor = vec3<f32>(0.0);

    if (u.zoom_params.z < 0.5) {
        // Monochrome halftone (black on white)
        outColor = mix(vec3<f32>(1.0), vec3<f32>(0.0), c);
    } else {
        // CMYK style - colorize each cell randomly across CMYK channels
        // We'll simulate by tinting with a palette depending on sampleColor hue
        let hue = sampleColor;
        // Convert luminance to one of CMY components roughly
        let c_c = 1.0 - sampleColor.r;
        let m = 1.0 - sampleColor.g;
        let y = 1.0 - sampleColor.b;
        let k = min(min(c_c, m), y);
        let c_col = vec3<f32>(1.0 - c_c, 1.0 - m, 1.0 - y);
        outColor = mix(vec3<f32>(1.0), c_col, c);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(outColor, 1.0));

    // Depth pass through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
