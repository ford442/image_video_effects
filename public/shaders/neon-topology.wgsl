// ═══════════════════════════════════════════════════════════════════════════════
//  Neon Topology - Advanced Alpha with Edge-Preserve
//  Category: edge-detection
//  Alpha Mode: Edge-Preserve Alpha + Luminance Key
//  Features: advanced-alpha, topology, neon, contours
// ═══════════════════════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,  // x=ContourLevels, y=EdgeThreshold, z=Intensity, w=ColorShift
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 2: Edge-Preserve Alpha
fn edgePreserveAlpha(uv: vec2<f32>, pixelSize: vec2<f32>, edgeThreshold: f32) -> f32 {
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold, depthEdge);
    return mix(0.2, 1.0, edgeMask);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    let audioBass = plasmaBuffer[0].x;

    // Bass adds extra contour density (more rings on beat)
    let contourLevels = u.zoom_params.x * 10.0 + 3.0 + audioBass * 4.0;
    let edgeThreshold = u.zoom_params.y * 0.1 + 0.02;
    let intensity = u.zoom_params.z * 2.0 * (1.0 + audioBass * 0.3);
    let colorShift = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Branchless contour lines — pre-multiplied phase saves ALU
    let contourPhase = depth * contourLevels;
    let contour = fract(contourPhase);
    let line = smoothstep(0.05, 0.0, contour);
    // Major every 5 contours (highlighted)
    let major = step(0.95, fract(contourPhase * 0.2));
    let lineWithMajor = line * (1.0 + major * 0.6);

    // Neon color — single phase, branchless vec3 sin
    let phase = depth * 10.0 + colorShift * TAU + time;
    let neonColor = 0.5 + 0.5 * sin(vec3<f32>(phase, phase + 2.094, phase + 4.188));

    // Composite onto desaturated background image (preserve photo context)
    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let bgGray = vec3<f32>(dot(bg, vec3<f32>(0.299, 0.587, 0.114))) * 0.4;
    let emission = neonColor * lineWithMajor * intensity;
    let final_color = bgGray + emission;

    let alpha = clamp(edgePreserveAlpha(uv, pixelSize, edgeThreshold) * lineWithMajor
                      + dot(emission, vec3<f32>(0.299, 0.587, 0.114)) * 0.3, 0.0, 1.0);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
