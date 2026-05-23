// ═══════════════════════════════════════════════════════════════════
//  Glass Brick Distortion — Phase A Upgrade
//  Category: distortion
//  Features: mouse-driven, depth-aware, audio-reactive, temporal
//  Complexity: Medium
//  Created: 2026-05-23
//  By: Claude (Sonnet 4.6)
// ═══════════════════════════════════════════════════════════════════
//
//  Param1: brick_size           — number of bricks across (more = smaller bricks)
//  Param2: ior_strength         — index-of-refraction / lens curvature
//  Param3: chromatic_aberration — per-channel IOR spread (RGB dispersion)
//  Param4: depth_influence      — near glass (depth→1) thicker → stronger refraction

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BrickSize, y=IORStrength, z=ChromaticAberration, w=DepthInfluence
  ripples: array<vec4<f32>, 50>,
};

// Schlick Fresnel approximation
fn schlick(cosTheta: f32, R0: f32) -> f32 {
    return R0 + (1.0 - R0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let uv    = vec2<f32>(gid.xy) / resolution;
    let time  = u.config.x;
    let aspect = resolution.x / resolution.y;

    // Params
    let brickCount = u.zoom_params.x * 38.0 + 4.0;
    let iorStr     = u.zoom_params.y * 0.14 + 0.01;
    let chromaStr  = u.zoom_params.z * 0.08;
    let depthInfl  = u.zoom_params.w;

    // Audio
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass = select(0.0, plasmaBuffer[0].x, hasAudio);

    // Depth — near glass (depth→1) is thicker → more refraction
    let depth     = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let thickness = 0.08 + depth * depthInfl * 0.12;
    let iorEff    = iorStr * (1.0 + thickness) * (1.0 + bass * 0.25);

    // Mouse clear zone — cursor melts the glass to reveal source
    let mouse     = u.zoom_config.yz;
    let mDist     = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let clearMask = smoothstep(0.18, 0.09, mDist);

    // Brick grid
    let uvS      = uv * vec2<f32>(brickCount * aspect, brickCount);
    let brickId  = floor(uvS);
    let brickUV  = fract(uvS);
    let bCenter  = (brickId + 0.5) / vec2<f32>(brickCount * aspect, brickCount);

    // Grout lines
    let groutW  = 0.04;
    let isGrout = f32(brickUV.x < groutW || brickUV.x > 1.0 - groutW ||
                      brickUV.y < groutW || brickUV.y > 1.0 - groutW);

    // Plano-convex lens offset — Snell-inspired refraction from brick-center
    let bCentered  = brickUV - 0.5;
    let lensMag    = dot(bCentered, bCentered);
    let baseOffset = bCentered * (0.5 - lensMag) * iorEff;

    // Per-channel IOR dispersion — red bends least, blue most (realistic glass)
    let offR = baseOffset * 1.0;
    let offG = baseOffset * (1.0 + chromaStr);
    let offB = baseOffset * (1.0 + chromaStr * 2.1);

    // activeMask: zero at grout lines and mouse clear zone
    let activeMask = (1.0 - clearMask) * (1.0 - isGrout);
    let uvR = clamp(mix(uv, bCenter + offR, activeMask), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(mix(uv, bCenter + offG, activeMask), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(mix(uv, bCenter + offB, activeMask), vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample each channel through its own refracted UV
    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    var color = vec3<f32>(r, g, b);

    // Fresnel highlight at glancing angles (edge of each brick)
    let cosTheta = 1.0 - lensMag * 4.0;
    let fresnel  = schlick(max(cosTheta, 0.0), 0.04) * activeMask;
    color = mix(color, vec3<f32>(0.92, 0.96, 1.0), fresnel * 0.35);

    // Beer-Lambert absorption through glass thickness (blue tint typical of glass)
    let glassColor = vec3<f32>(0.96, 0.98, 1.0);
    let absorbed   = exp(-(1.0 - glassColor) * thickness * 2.0);
    color *= mix(vec3<f32>(1.0), absorbed, activeMask);

    // Grout — dark mortar lines
    color = mix(color, color * 0.25, isGrout * (1.0 - clearMask));

    // Ripple wobble — ripple waves distort bricks as they pass through
    let rippleCount = min(u32(u.config.y), 50u);
    var rippleDisp  = vec2<f32>(0.0);
    for (var i = 0u; i < rippleCount; i++) {
        let rp   = u.ripples[i].xy;
        let rt   = u.ripples[i].z;
        let rAge = time - rt;
        if (rAge < 0.0 || rAge > 2.5) { continue; }
        let rDist  = length((uv - rp) * vec2<f32>(aspect, 1.0));
        let rFront = rAge * 0.45;
        let rRing  = sin((rDist - rFront) * 30.0)
                   * exp(-abs(rDist - rFront) * 12.0)
                   * exp(-rAge * 1.5);
        rippleDisp += normalize(uv - rp + vec2<f32>(0.0001)) * rRing * 0.008;
    }
    if (dot(rippleDisp, rippleDisp) > 0.000001) {
        let rSample = clamp(uv + rippleDisp, vec2<f32>(0.0), vec2<f32>(1.0));
        color = mix(color, textureSampleLevel(readTexture, u_sampler, rSample, 0.0).rgb, 0.3);
    }

    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));

    // Temporal persistence
    let prev  = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;
    color = mix(color, prev * 0.94, 0.1);

    let alpha = clamp(dot(color, vec3<f32>(0.33)) * 0.5 + 0.5 + fresnel * 0.3 + depth * 0.1, 0.0, 1.0);

    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(color, alpha));
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 1.0));
}
