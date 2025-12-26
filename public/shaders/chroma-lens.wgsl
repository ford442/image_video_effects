// --- CHROMA LENS ---
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
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let mag = u.zoom_params.x;            // Magnification (0-1)
    let aberration = u.zoom_params.y;     // Chroma Separation (0-1)
    let radius = u.zoom_params.z;         // Lens Radius (0-1)
    let blurEdges = u.zoom_params.w;      // Blur Amount (0-1)

    // Mouse
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let dVec = (uv - mouse) * aspectVec;
    let dist = length(dVec);

    var finalUV_R = uv;
    var finalUV_G = uv;
    var finalUV_B = uv;

    // Lens Effect
    if (dist < radius) {
        let ndist = dist / radius; // 0 at center, 1 at edge

        // Distortion curve (barrel)
        // zoom factor increases towards center
        // Let's model it as mapping a larger area of source to the lens area? No, that's shrinking.
        // Magnifying means showing a smaller area of source in the lens.
        // So we need to scale the UV vector from center by a factor < 1.

        // Factor curve:
        // Center (ndist=0): factor = 1.0 - mag
        // Edge (ndist=1): factor = 1.0
        // Parabolic interpolation

        let lensCurve = 1.0 - (1.0 - ndist * ndist) * mag;

        // Chromatic Aberration: different scaling factors for R, G, B
        // R scales more (spreads out), B scales less? Or offset?
        // Let's scale them slightly differently based on aberration param.

        let abbStrength = aberration * 0.05 * (ndist); // More aberration at edges of lens

        let factorR = lensCurve - abbStrength;
        let factorG = lensCurve;
        let factorB = lensCurve + abbStrength;

        finalUV_R = mouse + (uv - mouse) * factorR;
        finalUV_G = mouse + (uv - mouse) * factorG;
        finalUV_B = mouse + (uv - mouse) * factorB;

        // Blur / Edge Softening
        // If blurEdges > 0, we can add a simple blur by jittering samples, but expensive.
        // Or mix with blurred texture? We don't have one.
        // Let's just do the lens and aberration.
    }

    let r = textureSampleLevel(readTexture, u_sampler, finalUV_R, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, finalUV_G, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, finalUV_B, 0.0).b;

    // Add a rim/glass reflection effect at the edge
    var color = vec4<f32>(r, g, b, 1.0);

    if (dist < radius && dist > radius * 0.95) {
        let rim = smoothstep(radius * 0.95, radius, dist);
        color = mix(color, vec4<f32>(1.0), rim * 0.3 * blurEdges);
    }

    // Antialiased circle edge
    let mask = 1.0 - smoothstep(radius, radius + 0.01, dist);

    // If we are outside the lens, just show original
    // But we computed lens distortion inside.
    // The if(dist < radius) handled the UV modification.
    // Outside that, finalUV is original UV.
    // So this is seamless.

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Passthrough Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
