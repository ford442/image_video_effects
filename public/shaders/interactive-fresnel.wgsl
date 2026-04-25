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
  zoom_params: vec4<f32>,  // x=RingDensity, y=Magnification, z=Aberration, w=DepthInfluence
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    // Params
    let ringDensity = mix(1.0, 50.0, u.zoom_params.x);
    let magStrength = u.zoom_params.y * 2.0;
    let aberration = u.zoom_params.z * 0.05;
    let depthInfluence = u.zoom_params.w * 2.0;

    // Audio reactivity
    let audioPulse = 1.0 + plasmaBuffer[0].x * 0.5;

    var mouse = u.zoom_config.yz;
    var center = mouse;
    let dist = distance((uv - center) * aspectVec, vec2<f32>(0.0));

    // Create stepped rings
    let ringPhase = fract(dist * ringDensity);

    // Vector from center
    var dir = vec2<f32>(0.0);
    if (dist > 0.001) {
        dir = normalize((uv - center) * aspectVec);
    }

    // Depth-influenced displacement
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let displaceAmount = ringPhase * magStrength * 0.05 * (1.0 + (1.0 - depth) * depthInfluence) * audioPulse;

    // Apply displacement
    let baseUV = uv - (dir * displaceAmount) / aspectVec;

    // Chromatic Aberration with full vec4 sampling and alpha-aware blending
    let rUV = baseUV - (dir * aberration) / aspectVec;
    let gUV = baseUV;
    let bUV = baseUV + (dir * aberration) / aspectVec;

    let cR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
    let cG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    let cB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);

    let aberrationBlend = clamp(aberration * 20.0 * cG.a, 0.0, 1.0);
    let aberratedRGB = vec3<f32>(cR.r, cG.g, cB.b);
    let finalRGB = mix(cG.rgb, aberratedRGB, aberrationBlend);
    let finalColor = vec4<f32>(finalRGB, cG.a);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

    // Depth pass-through
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
