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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Mouse interaction
    let mousePos = u.zoom_config.yz; // y=MouseX, z=MouseY

    // Correct for aspect ratio to ensure circular distortion
    let aspect = resolution.x / resolution.y;

    // Parameters
    let tunnelDepth = u.zoom_params.x * 0.8; // Strength of the pull
    let refraction = u.zoom_params.y * 0.1; // Strength of chromatic aberration
    let twist = (u.zoom_params.z - 0.5) * 10.0; // Twist amount
    let vignetteStr = u.zoom_params.w;

    // Calculate vector from mouse to current pixel
    let dir = uv - mousePos;
    let dirCorrected = vec2<f32>(dir.x * aspect, dir.y);
    let dist = length(dirCorrected);
    let angle = atan2(dirCorrected.y, dirCorrected.x);

    // Avoid division by zero or weird artifacts at center
    if (dist < 0.001) {
        let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        textureStore(writeTexture, global_id.xy, color);
        return;
    }

    // Tunnel Distortion: Power function creates the "suck" or "push" effect
    // 1.0 = no change, < 1.0 = zoom in/pinch, > 1.0 = zoom out/bulge
    let distortPower = 1.0 - tunnelDepth;
    let newDist = pow(dist, distortPower);

    // Apply Twist
    let newAngle = angle + twist * (1.0 - smoothstep(0.0, 1.0, dist));

    // Calculate sampling offsets with chromatic aberration (Refraction)
    // We need to convert back from polar to cartesian, adjusting for aspect ratio
    let offsetDir = vec2<f32>(cos(newAngle), sin(newAngle));

    // The new position relative to mouse
    // X component needs to be divided by aspect to map back to UV space
    let relativePos = vec2<f32>(offsetDir.x * newDist / aspect, offsetDir.y * newDist);
    let centerUV = mousePos + relativePos;

    // Sample channels with slight offsets for refraction
    let rUV = centerUV - relativePos * refraction;
    let gUV = centerUV;
    let bUV = centerUV + relativePos * refraction;

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    var color = vec4<f32>(r, g, b, 1.0);

    // Vignette based on distance from mouse
    let vig = 1.0 - smoothstep(0.2, 1.5, dist * vignetteStr * 2.0);
    color = color * vig;

    textureStore(writeTexture, global_id.xy, color);

    // Pass through depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
