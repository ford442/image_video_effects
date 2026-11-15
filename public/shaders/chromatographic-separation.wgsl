// ═══════════════════════════════════════════════════════════════════
//  Chromatographic Separation
//  Category: artistic
//  Features: depth-aware, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09, 2026-11-15
//  Ideas: solvent-front Rf; capillary tailing; longitudinal diffusion; solvent meniscus
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depthAlpha = mix(0.4, 1.0, depth);
    let lumaAlpha = mix(0.5, 1.0, luma);
    return mix(lumaAlpha, depthAlpha, depthWeight);
}

fn effectIntensityAlpha(
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    intensity: f32
) -> f32 {
    let displacement = length(displacedUV - originalUV);
    let displacementAlpha = smoothstep(0.0, 0.1, displacement);
    let edgeDist = min(min(originalUV.x, 1.0 - originalUV.x),
                       min(originalUV.y, 1.0 - originalUV.y));
    let edgeFade = smoothstep(0.0, 0.05, edgeDist);
    return baseAlpha * mix(0.6, 1.0, displacementAlpha * intensity) * edgeFade;
}

fn calculateAdvancedAlpha(
    color: vec3<f32>,
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    params: vec4<f32>
) -> f32 {
    let depthAlpha = depthLayeredAlpha(color, displacedUV, params.z);
    let effectAlpha = effectIntensityAlpha(originalUV, displacedUV, baseAlpha, params.x);
    return clamp(depthAlpha * effectAlpha, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    let prismFocus = mix(1.6, 0.35, smoothstep(0.0, 0.45, mouseDist));

    let separationAmount = u.zoom_params.x * 0.1 * (1.0 + bass * 0.5) * prismFocus;
    let rotation = u.zoom_params.y * 6.28;
    let depthWeight = u.zoom_params.z;
    let separationMode = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthOffset = (1.0 - depth) * separationAmount;

    let spin = rotation + time * 0.2 + mids * 1.2;
    let c = cos(spin);
    let s = sin(spin);

    let rOffset = vec2<f32>(c, s) * depthOffset * (1.0 + separationMode);
    let gOffset = vec2<f32>(c * 0.5, s * 0.5) * depthOffset;
    let bOffset = vec2<f32>(-c, -s) * depthOffset * (1.0 - separationMode * 0.5);

    // Idea 1 — solvent-front Rf: separation develops past a traveling Y line.
    let solvent = fract(time * (0.08 + separationMode * 0.12));
    let rf = smoothstep(solvent - 0.08, solvent + 0.02, uv.y);
    let rOff = rOffset * rf;
    let gOff = gOffset * rf;
    let bOff = bOffset * rf;

    // Idea 2 — capillary tailing along each channel's own offset axis.
    let tail = 0.35 + treble * 0.15;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + rOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let rTail = textureSampleLevel(readTexture, u_sampler, clamp(uv + rOff * (1.0 + tail), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + gOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let gTail = textureSampleLevel(readTexture, u_sampler, clamp(uv + gOff * (1.0 + tail), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + bOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let bTail = textureSampleLevel(readTexture, u_sampler, clamp(uv + bOff * (1.0 + tail), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    // ── Idea 3: longitudinal diffusion — the tail mix widens with distance traveled, above the front
    let traveled = clamp(uv.y, 0.0, 1.0);
    let diffuse = 0.35 + traveled * rf * 0.4;
    let separated = vec3<f32>(mix(r, rTail, diffuse), mix(g, gTail, diffuse), mix(b, bTail, diffuse));
    // ── Idea 4: solvent meniscus — a wet line on the traveling front
    let frontLine = smoothstep(0.018, 0.0, abs(uv.y - solvent));
    let wet = clamp(frontLine * (0.55 + bass * 0.25), 0.0, 1.0);
    let sepLuma = dot(separated, vec3<f32>(0.299, 0.587, 0.114));
    let finalColor = mix(separated, vec3<f32>(sepLuma * 0.42, sepLuma * 0.52, sepLuma * 0.64), wet);

    let displacedUV = uv + (rOff + gOff + bOff) / 3.0;
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let alpha = calculateAdvancedAlpha(finalColor, uv, displacedUV, baseSample.a, u.zoom_params);
    let display = aces(max(finalColor, vec3<f32>(0.0)));
    let outColor = vec4<f32>(display, clamp(alpha + rf * 0.08 + frontLine * 0.1, 0.0, 1.0));

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
