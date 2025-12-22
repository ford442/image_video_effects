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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let twistStrength = (u.zoom_params.x - 0.5) * 20.0; // -10 to +10
    let radius = mix(0.1, 0.8, u.zoom_params.y);
    let pinchStrength = (u.zoom_params.z - 0.5) * 2.0; // -1 to +1
    let hardness = mix(0.0, 0.95, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Vector from mouse to current pixel
    var dVec = uv - mousePos;
    dVec.x *= aspect;
    let dist = length(dVec);

    // Effect Strength
    // Smoothstep creates the falloff
    let effectT = 1.0 - smoothstep(radius * (1.0 - hardness), radius, dist);

    var finalUV = uv;

    if (effectT > 0.0) {
        // Twist: Angle depends on distance from center (closest = most twist)
        // Squared falloff looks more natural for fluids
        let angle = twistStrength * effectT * effectT;
        let s = sin(angle);
        let c = cos(angle);

        // Rotate dVec
        var rotatedDVec = vec2(
            dVec.x * c - dVec.y * s,
            dVec.x * s + dVec.y * c
        );

        // Pinch
        // If pinch > 0 (zoom in), we need to sample closer to center, so multiply dVec by < 1
        // If pinch < 0 (zoom out / bulge), we sample further, multiply by > 1
        let pinchFactor = 1.0 - (pinchStrength * effectT);
        rotatedDVec = rotatedDVec * pinchFactor;

        // Restore aspect and UV
        rotatedDVec.x /= aspect;
        finalUV = mousePos + rotatedDVec;
    }

    let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).rgb;

    textureStore(writeTexture, global_id.xy, vec4(color, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
