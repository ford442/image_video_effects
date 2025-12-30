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
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=Aberration, w=Darkness
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Mouse inputs
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Parameters mapped from zoom_params
    // x: Grid Scale
    // y: Distortion Strength
    // z: Glow Intensity
    // w: Radius
    let gridScale = 10.0 + u.zoom_params.x * 50.0;
    let distortStrength = u.zoom_params.y;
    let glowIntensity = u.zoom_params.z * 2.0;
    let radius = u.zoom_params.w * 0.5;

    // Aspect corrected distance to mouse
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Calculate distortion
    // We want the grid to bend away from or around the mouse
    let distortion = smoothstep(radius, 0.0, dist) * distortStrength * sin(u.config.x * 5.0);
    let gridUV = uv + (uv - mousePos) * distortion;

    // Create grid lines
    let gridX = abs(fract(gridUV.x * gridScale) - 0.5);
    let gridY = abs(fract(gridUV.y * gridScale) - 0.5);
    let gridLine = min(gridX, gridY);

    let thickness = 0.05;
    let mouseInfluence = smoothstep(radius, 0.0, dist);
    let currentThickness = thickness + mouseInfluence * 0.1; // Thicker near mouse

    // 1.0 on line, 0.0 elsewhere (with antialiasing)
    let gridMask = 1.0 - smoothstep(currentThickness, currentThickness + 0.05, gridLine);

    // Sample base image
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Determine Glow Color
    var glowColor = vec3<f32>(0.0, 1.0, 1.0); // Cyan
    if (mouseDown > 0.5) {
        glowColor = vec3<f32>(1.0, 0.0, 1.0); // Magenta on click
    }

    // Composite: Mix base color with glow based on grid mask
    // Increase glow intensity near mouse
    let totalGlow = glowIntensity * (0.5 + 0.5 * mouseInfluence);
    let finalColor = mix(baseColor.rgb, glowColor, gridMask * totalGlow);

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
