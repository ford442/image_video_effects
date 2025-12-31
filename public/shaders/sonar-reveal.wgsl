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
    let mousePos = u.zoom_config.yz;

    // Parameters
    // x: Scan Width / Size
    // y: Intensity / Brightness
    // z: Softness
    // w: Color Mode
    let size = u.zoom_params.x * 0.4 + 0.05;
    let intensity = u.zoom_params.y * 2.0;
    let softness = u.zoom_params.z * 0.2;
    let colorMode = u.zoom_params.w;

    // Aspect corrected distance to mouse
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Base color
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Desaturated background version
    let gray = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let dimColor = vec3<f32>(gray * 0.3); // Darker gray

    // Reveal mask (1.0 near mouse, 0.0 far away)
    let reveal = 1.0 - smoothstep(size, size + softness + 0.01, dist);

    // Create a "radar ring" at the edge of the reveal
    let ringWidth = 0.02 + softness * 0.1;
    let ring = smoothstep(ringWidth, 0.0, abs(dist - size));

    // Determine Ring Color
    var ringColorVec = vec3<f32>(0.2, 1.0, 0.5); // Tech Green
    if (colorMode > 0.5) {
        ringColorVec = vec3<f32>(1.0, 0.3, 0.1); // Alert Orange
    }

    // Combine
    // Revealed area sees full color. Outside sees dim gray.
    var finalColor = mix(dimColor, baseColor.rgb, reveal);

    // Add ring overlay
    finalColor = finalColor + ringColorVec * ring * intensity;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
