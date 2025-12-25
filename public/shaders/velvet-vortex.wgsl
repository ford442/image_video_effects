
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let radiusParam = u.zoom_params.x;
    let strength = u.zoom_params.y;
    let softness = u.zoom_params.z;
    let pulseSpeed = u.zoom_params.w;

    // Aspect Correction
    let aspect = resolution.x / resolution.y;
    let aspectScale = vec2<f32>(aspect, 1.0);
    let center = u.zoom_config.yz; // Mouse Pos

    let uvCorrected = uv * aspectScale;
    let centerCorrected = center * aspectScale;

    // Distance calculation
    let dist = distance(uvCorrected, centerCorrected);

    // Dynamic Swirl
    let time = u.config.x;
    let pulse = sin(time * pulseSpeed * 5.0) * 0.2 + 1.0;
    let effectiveRadius = radiusParam * pulse;

    // Calculate rotation amount
    // 1.0 - smoothstep gives us 1 at center, 0 at edge
    let swirlFactor = (1.0 - smoothstep(0.0, effectiveRadius, dist));
    // Additional softness falloff
    let softFactor = pow(swirlFactor, 1.0 / (softness + 0.1));

    let angle = strength * 10.0 * softFactor;

    let s = sin(angle);
    let c = cos(angle);

    // Rotate around center
    let dir = uvCorrected - centerCorrected;
    // Standard 2D rotation matrix:
    // x' = x cos - y sin
    // y' = x sin + y cos
    let rotatedDir = vec2<f32>(
        dir.x * c - dir.y * s,
        dir.x * s + dir.y * c
    );

    // Convert back to UV space
    let finalUV = (rotatedDir + centerCorrected) / aspectScale;

    // Read texture
    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Optional: Add a slight tint or brightness boost in the center
    // color = color * (1.0 + softFactor * 0.2);

    textureStore(writeTexture, global_id.xy, color);

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
