// ────────────────────────────────────────────────────────────────────────────────
//  Chromatic Focus Interactive
//  Depth-of-field like effect with strong chromatic aberration away from mouse.
// ────────────────────────────────────────────────────────────────────────────────
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let aspect = dims.x / dims.y;

    // Params
    let strength = u.zoom_params.x * 0.05; // Max displacement
    let blurAmt = u.zoom_params.y; // Simulate blur by sampling multiple points? Or just strong separation.
    let focusRad = u.zoom_params.z;
    let hardness = u.zoom_params.w * 5.0 + 1.0;

    let mouse = u.zoom_config.yz;
    let click = u.zoom_config.w;

    // Focus point is mouse
    let center = mouse;
    let distVec = (uv - center) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Calculate blur/abberation amount based on distance from focus
    // 0 at focusRad, 1 at edges
    var amount = smoothstep(focusRad, focusRad + 0.5, dist);
    amount = pow(amount, 1.0 / hardness); // Hardness controls falloff curve

    // Direction for displacement
    let dir = normalize(distVec);

    // Chromatic Abberation
    let rOffset = dir * amount * strength;
    let bOffset = -dir * amount * strength;
    let gOffset = vec2<f32>(0.0);

    // Simple 3-tap sample for CA
    let r = textureSampleLevel(videoTex, videoSampler, uv + rOffset, 0.0).r;
    let g = textureSampleLevel(videoTex, videoSampler, uv + gOffset, 0.0).g;
    let b = textureSampleLevel(videoTex, videoSampler, uv + bOffset, 0.0).b;

    // Optional: Add simple blur if blurAmt > 0 (by sampling a bit further out for R and B)
    // Actually, let's just use the CA as the "blur" style.

    // Vignette
    let vig = 1.0 - amount * 0.3;

    var color = vec3<f32>(r, g, b) * vig;

    // Show focus ring if clicking
    if (click > 0.5) {
        let ring = abs(dist - focusRad);
        if (ring < 0.005) {
            color += vec3<f32>(0.5, 0.5, 0.5);
        }
    }

    textureStore(outTex, gid.xy, vec4<f32>(color, 1.0));
    
    // Pass through depth
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
