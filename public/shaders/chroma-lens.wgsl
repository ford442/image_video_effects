// ═══════════════════════════════════════════════════════════════════
//  Chroma Lens
//  Mouse-positioned magnifying lens with barrel distortion, per-channel
//  chromatic separation toward the rim, and a glass rim highlight.
//  Features: mouse-driven, audio-reactive, upgraded-rgba
// ═══════════════════════════════════════════════════════════════════

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Params — bass breathes the lens, mids widen the chroma split
    let mag = u.zoom_params.x * (1.0 + bass * 0.4);        // Magnification (0-1)
    let aberration = u.zoom_params.y * (1.0 + mids * 0.5); // Chroma Separation (0-1)
    let radius = u.zoom_params.z * (1.0 + bass * 0.3);     // Lens Radius (0-1)
    let blurEdges = u.zoom_params.w;      // Blur Amount (0-1)

    // Mouse
    var mouse = u.zoom_config.yz;
    let heldLens = step(0.5, u.zoom_config.w);
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let dVec = (uv - mouse) * aspectVec;
    let dist = length(dVec);
    let activeRadius = max(0.001, radius * (1.0 + heldLens * 0.18));

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let delta = (uv - ripple.xy) * aspectVec;
            clickFront += smoothstep(0.022, 0.0, abs(length(delta) - age * 0.44)) * exp(-age * 1.5);
        }
    }

    var finalUV_R = uv;
    var finalUV_G = uv;
    var finalUV_B = uv;

    // Lens Effect
    if (dist < activeRadius) {
        let ndist = dist / activeRadius; // 0 at center, 1 at edge

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

        let abbStrength = aberration * 0.05 * ndist * (1.0 + clickFront); // More aberration at edges of lens

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

    let edgeBand = smoothstep(activeRadius * 0.55, activeRadius, dist) * (1.0 - smoothstep(activeRadius, activeRadius + 0.02, dist));
    let tangent = vec2<f32>(-dVec.y, dVec.x) / max(dist, 0.001);
    let blurOffset = tangent * blurEdges * edgeBand * 0.006;
    let safeR = clamp(finalUV_R, vec2<f32>(0.0), vec2<f32>(1.0));
    let safeG = clamp(finalUV_G, vec2<f32>(0.0), vec2<f32>(1.0));
    let safeB = clamp(finalUV_B, vec2<f32>(0.0), vec2<f32>(1.0));
    let r = (textureSampleLevel(readTexture, u_sampler, safeR, 0.0).r + textureSampleLevel(readTexture, u_sampler, clamp(safeR + blurOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r) * 0.5;
    let g = (textureSampleLevel(readTexture, u_sampler, safeG, 0.0).g + textureSampleLevel(readTexture, u_sampler, clamp(safeG - blurOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g) * 0.5;
    let b = (textureSampleLevel(readTexture, u_sampler, safeB, 0.0).b + textureSampleLevel(readTexture, u_sampler, clamp(safeB + blurOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b) * 0.5;

    // Source alpha follows the green (undisplaced) channel's sample point
    let srcAlpha = textureSampleLevel(readTexture, u_sampler, safeG, 0.0).a;

    // Add a rim/glass reflection effect at the edge
    var color = vec4<f32>(r, g, b, srcAlpha);

    let rim = smoothstep(activeRadius * 0.88, activeRadius, dist) * (1.0 - smoothstep(activeRadius, activeRadius + 0.012, dist));
    let angle = atan2(dVec.y, dVec.x);
    let rimRunner = pow(max(0.0, sin(angle * 14.0 - time * 15.0)), 12.0) * rim;
    color = mix(color, vec4<f32>(1.0, 0.75 + mids * 0.2, 1.0, 1.0), clamp(rim * blurEdges * 0.3 + rimRunner * 0.35 + clickFront * 0.4, 0.0, 0.8));

    // Antialiased circle edge — glass body reads slightly more solid than the plate
    let mask = 1.0 - smoothstep(activeRadius, activeRadius + 0.01, dist);
    color.a = clamp(color.a + mask * 0.15, 0.0, 1.0);

    // If we are outside the lens, just show original
    // But we computed lens distortion inside.
    // The if(dist < radius) handled the UV modification.
    // Outside that, finalUV is original UV.
    // So this is seamless.

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), color);

    // Passthrough Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
