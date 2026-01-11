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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=DecaySpeed, y=BrushRadius, z=NoiseIntensity, w=Unused
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    // Params
    let decaySpeed = u.zoom_params.x * 0.05 + 0.001;
    let brushRadius = u.zoom_params.y * 0.3 + 0.05;
    let noiseIntensity = u.zoom_params.z;

    // Mouse
    let mouse = u.zoom_config.yz;
    let dist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

    // Read previous mask (Red channel of dataTextureC)
    let prevMask = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Update Mask
    var mask = prevMask - decaySpeed; // Decay

    // Add brush
    let brush = smoothstep(brushRadius, brushRadius * 0.5, dist);
    mask = max(mask, brush);
    mask = clamp(mask, 0.0, 1.0);

    // Save mask
    textureStore(dataTextureA, global_id.xy, vec4<f32>(mask, 0.0, 0.0, 1.0));

    // Generate Static Noise
    let noiseVal = hash12(uv * 100.0 + vec2<f32>(u.config.x * 10.0));
    let noiseColor = vec4<f32>(vec3<f32>(noiseVal), 1.0);

    // Sample Video
    let videoColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Mix: Mask=1 -> Video, Mask=0 -> Noise
    let finalColor = mix(noiseColor, videoColor, mask);

    textureStore(writeTexture, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
