// ═══════════════════════════════════════════════════════════════════
//  Hybrid Chromatic Liquid
//  Category: hybrid
//  Features: mouse-driven, audio-reactive, liquid-distortion, chromatic-aberration, flow-field, fresnel, upgraded-rgba
//  Complexity: High
//  Chunks From: gen_grid.wgsl (fbm2), crystal-facets.wgsl (fresnelSchlick), luma-flow-field.wgsl (flow-field pattern)
//  Created: 2026-03-22 (Agent 2A - Shader Surgeon)
//  Upgraded: 2026-11-20
//  Ideas: slope-driven dispersion (§12.2F Snell direction); surface-normal Fresnel + specular glint (§12.2F)
//  A packing: display RGBA (A is a plain copy of the output; nothing reads it as a field)
// ═══════════════════════════════════════════════════════════════════
//  Fluid-like distortion with RGB channel separation flowing along a
//  noise-generated flow field. Audio swells the liquid; the cursor pulls
//  and rings it.
//
//  Restored 2026-11-20: from commit 9983b1eb until now this file held an
//  unrelated halftone/ink print (dot size / edge threshold / levels / ink
//  density on the four sliders) while the JSON, description and slider
//  labels all describe THIS effect. The original did not compile
//  (`let rOffset` was assigned), which is why it was swapped out.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK 1: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK 2: valueNoise (from gen_grid.wgsl) ═══
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// ═══ CHUNK 3: fbm2 (from gen_grid.wgsl) ═══
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ═══ CHUNK 4: fresnelSchlick (from crystal-facets.wgsl) ═══
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// Display tone-map for the added glint only (the photograph and HEAD's highlight are not graded).
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let c = max(x, vec3<f32>(0.0));
    return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ HYBRID LOGIC: Flow Field + Chromatic Liquid ═══
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let ci = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let asp = vec2<f32>(resolution.x / resolution.y, 1.0);   // noise lives in aspect-correct space
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Parameters
    let flowScale = mix(1.0, 5.0, u.zoom_params.x);                              // x: Flow field scale
    let distortionStrength = mix(0.02, 0.15, u.zoom_params.y) * (1.0 + bass * 0.35); // y: Liquid distortion (bass swells it)
    let chromaticAmount = u.zoom_params.z * 0.08;                                // z: RGB split
    let flowSpeed = mix(0.2, 1.5, u.zoom_params.w);                              // w: Animation speed
    let flowT = time * flowSpeed * 0.1 + mids * 0.1;                             // mids push the phase (additive)

    // Pointer: HEAD's cursor behaviour (held-click ring + cursor pull, HEAD constants), now
    // bending the liquid's sample point so the JSON's `mouse-driven` stays true.
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;
    let toMouse = uv - mousePos;
    let distToMouse = length(toMouse);
    let clickRing = select(0.0, 1.0, isMouseDown) * sin(distToMouse * 40.0 - time * 8.0) * exp(-distToMouse * 4.0) * (1.0 + bass * 0.5);
    let cursorPull = 1.0 - smoothstep(0.0, 0.3, distToMouse);
    let uvp = uv + (toMouse / max(distToMouse, 1e-4)) * (clickRing * 0.05 + cursorPull * 0.02);

    // Calculate flow field from FBM
    let flowUV = uvp * asp * flowScale + vec2<f32>(flowT);
    let angle1 = fbm2(flowUV, 4) * 6.28318;
    let angle2 = fbm2(flowUV + vec2<f32>(5.2, 1.3), 4) * 6.28318;

    // Create flow vectors
    let flow = vec2<f32>(cos(angle1), sin(angle2));

    // Liquid displacement accumulates along flow
    var displacedUV = uvp;
    var height0 = 0.0;
    let steps = 5;
    for (var i: i32 = 0; i < steps; i = i + 1) {
        let fi = f32(i) / f32(steps);
        let noiseVal = fbm2(displacedUV * asp * flowScale + vec2<f32>(time * 0.2), 3);
        height0 = select(height0, noiseVal, i == 0);   // surface height at the unbent point
        displacedUV = displacedUV + flow * distortionStrength * noiseVal * (1.0 - fi);
    }

    // ── liquid surface normal from the displacement noise (feeds Ideas 1 and 2) ──
    // `noiseVal` was computed and thrown away; its gradient is the surface slope. Two forward
    // differences on the height that the first displacement step already used.
    let hp = uvp * asp * flowScale + vec2<f32>(time * 0.2);
    let eps = 0.02;
    let hx = fbm2(hp + vec2<f32>(eps, 0.0), 3);
    let hy = fbm2(hp + vec2<f32>(0.0, eps), 3);
    let slope = vec2<f32>(hx - height0, hy - height0) / eps;
    let nrm = normalize(vec3<f32>(-slope * 0.5, 1.0));

    // ── Idea 1: slope-driven dispersion (§12.2F Snell direction) ───────
    // HEAD split R/B by a constant (flow + (1,0)) vector. A refracting liquid disperses by how
    // much the surface is tilted: steep ripples split hard along the surface gradient, flat
    // patches stay nearly colour-true. Same slider, same flow offsets, plus a slope term.
    let steep = smoothstep(0.2, 1.6, length(slope));
    let splitVec = (flow + vec2<f32>(1.0, 0.0)) * mix(0.6, 1.5, steep) + nrm.xy * 3.0;
    var rOffset = displacedUV + splitVec * chromaticAmount;
    var gOffset = displacedUV;
    var bOffset = displacedUV - splitVec * chromaticAmount;

    // Sample with wrapping for liquid effect
    rOffset = fract(rOffset);
    gOffset = fract(gOffset);
    bOffset = fract(bOffset);

    // Sample input texture
    let r = textureSampleLevel(readTexture, u_sampler, rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bOffset, 0.0).b;
    var color = vec3<f32>(r, g, b);

    // Add liquid highlights based on distortion magnitude
    let distortionMag = length(displacedUV - uvp);
    let highlight = vec3<f32>(0.3, 0.5, 0.7) * distortionMag * 5.0;

    // ── Idea 2: surface-normal Fresnel + specular glint (§12.2F) ───────
    // HEAD fed Fresnel a fake cos(theta) from screen radius. Feed it the real normal too
    // (flat water reproduces HEAD exactly) and add a Blinn glint on the same normal, so the
    // rippled surface carries a wet sheen. Existing (0.8, 0.9, 1.0) rim tint kept.
    let edgeDist = length(uv - 0.5);
    let fresnel = fresnelSchlick(nrm.z * (1.0 - edgeDist), 0.1);
    let halfVec = normalize(normalize(vec3<f32>(-0.4, -0.5, 0.75)) + vec3<f32>(0.0, 0.0, 1.0));
    let glint = pow(max(dot(nrm, halfVec), 0.0), 160.0) * vec3<f32>(0.9, 0.95, 1.0) * 0.4;

    // HEAD's blue highlight is kept as-is; only the new emissive glint goes through the display curve.
    color = color + highlight + acesToneMap(glint);
    color = mix(color, vec3<f32>(0.8, 0.9, 1.0), fresnel * 0.3);

    // Alpha based on distortion
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(mix(0.5, 1.0, luma + distortionMag * 2.0), 0.0, 1.0);

    // Sample and write depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, gOffset, 0.0).r;

    textureStore(writeTexture, ci, vec4<f32>(color, alpha));
    textureStore(dataTextureA, ci, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth * (1.0 - distortionMag), 0.0, 0.0, 0.0));
}
