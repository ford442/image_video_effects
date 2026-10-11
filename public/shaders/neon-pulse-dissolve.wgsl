// ═══════════════════════════════════════════════════════════════════
//  Neon Pulse Dissolve
//  Category: image
//  Features: audio-reactive, mouse-driven, upgraded-rgba, semantic-alpha
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: neon tube core + halo; neon threshold fringe; failing-tube flicker
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Detects edges in the source, overlays glowing neon halos that
//  pulse with audio bass, and dissolves the image interior into
//  luminous colour noise driven by mid/treble frequencies.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=GlowRadius, y=DissolveAmount, z=NeonSaturation, w=EdgeSharpness

const PI: f32 = 3.14159265358979;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let cell = floor(p);
    let f = fract(p);
    let smoothF = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(cell), hash(cell + vec2<f32>(1.0, 0.0)), smoothF.x),
        mix(hash(cell + vec2<f32>(0.0, 1.0)), hash(cell + vec2<f32>(1.0, 1.0)), smoothF.x),
        smoothF.y
    );
}

fn sobel(uv: vec2<f32>, ps: vec2<f32>) -> f32 {
    let tl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-ps.x,  ps.y), 0.0).rgb;
    let tc = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,   ps.y), 0.0).rgb;
    let tr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( ps.x,  ps.y), 0.0).rgb;
    let ml = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-ps.x,  0.0 ), 0.0).rgb;
    let mr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( ps.x,  0.0 ), 0.0).rgb;
    let bl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-ps.x, -ps.y), 0.0).rgb;
    let bc = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,  -ps.y), 0.0).rgb;
    let br = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( ps.x, -ps.y), 0.0).rgb;

    let luma = vec3<f32>(0.299, 0.587, 0.114);
    let gx = dot(-tl + tr - 2.0*ml + 2.0*mr - bl + br, luma);
    let gy = dot( tl + 2.0*tc + tr - bl - 2.0*bc - br, luma);
    return sqrt(gx*gx + gy*gy);
}

// Neon hue from angle
fn neonColor(angle: f32, sat: f32) -> vec3<f32> {
    let h = fract(angle / (2.0 * PI));
    let h6 = h * 6.0;
    let c = sat;
    let x = c * (1.0 - abs(fract(h6 * 0.5) * 2.0 - 1.0));
    var rgb: vec3<f32>;
    if      (h6 < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(1.0 - sat) * 0.5;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv     = vec2<f32>(gid.xy) / dims;
    let coord  = vec2<i32>(gid.xy);
    let ps     = 1.0 / dims;
    let time   = u.config.x;

    // Audio
    let bass    = plasmaBuffer[0].x;
    let mid     = plasmaBuffer[0].y;
    let treble  = plasmaBuffer[0].z;

    // Params
    let glowRadius     = mix(1.0, 6.0,  u.zoom_params.x);
    let dissolveAmt    = mix(0.0, 1.0,  u.zoom_params.y);
    let neonSat        = mix(0.6, 1.0,  u.zoom_params.z);
    let edgeSharpness  = mix(2.0, 20.0, u.zoom_params.w);

    // Source colour
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Edge magnitude
    var edge = sobel(uv, ps * glowRadius);
    edge = clamp(edge * edgeSharpness, 0.0, 1.0);
    edge = edge * (1.0 + bass * 2.0);

    let aspect = dims.x / dims.y;
    let mouseDelta = (uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0);
    let mouseEnergy = (1.0 - smoothstep(0.04, 0.32, length(mouseDelta))) * step(0.5, u.zoom_config.w);
    let scanRunner = pow(max(0.0, sin(uv.y * 58.0 + uv.x * 19.0 - time * 16.0)), 14.0);

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            clickFront += (1.0 - smoothstep(0.0, 0.025, abs(length(delta) - age * 0.46))) * exp(-age * 1.5);
        }
    }
    edge = clamp(edge + scanRunner * (0.08 + treble * 0.16) + clickFront * 0.7 + mouseEnergy * 0.2, 0.0, 2.0);

    // Idea 1: neon tube core + halo — a 1-px Sobel tap marks the glass
    // centre of each tube; it burns near-white inside the wide coloured
    // halo that GlowRadius spreads.
    let coreEdge  = clamp(sobel(uv, ps) * edgeSharpness, 0.0, 1.0);
    let core      = smoothstep(0.55, 0.95, coreEdge) * clamp(edge, 0.0, 1.0);

    // Idea 3: failing-tube flicker — coarse sign "segments" occasionally
    // stutter dark like a neon tube on a tired transformer; treble raises
    // the stutter rate. Only the neon light flickers, not the photo.
    // Fixed tick clock (time * audio-scaled rate re-rolls every frame once
    // time is large); treble raises the stutter odds per tick instead.
    let segCell   = floor(uv * vec2<f32>(aspect, 1.0) * 9.0);
    let segClock  = floor(time * 8.0);
    let segSeed   = vec2<f32>(fract(segClock * 0.1317) * 97.0, fract(segClock * 0.0719) * 61.0);
    let stutter   = step(hash(segCell + segSeed), 0.035 + treble * 0.08);
    let flick     = 1.0 - stutter * (0.55 + 0.3 * hash(segCell + segSeed.yx));

    // Neon edge colour cycles with position + time
    let angle     = atan2(uv.y - 0.5, uv.x - 0.5) + time * 0.5 + bass * PI;
    let neonCol   = neonColor(angle, neonSat);
    let tubeCore  = mix(neonCol, vec3<f32>(1.0, 0.98, 0.95), 0.75) * core * 0.65 * (1.0 + bass);
    let neonGlow  = (neonCol * edge * (1.0 + bass * 1.5) + tubeCore) * flick;

    // Interior dissolve into colour noise
    let noiseUV   = uv * 18.0 + vec2<f32>(time * 3.2, time * 1.9);
    let n         = valueNoise(noiseUV);
    let noiseCol  = neonColor(n * 2.0 * PI + time, neonSat * 0.7);
    let dissolve  = dissolveAmt * (0.2 + mid * 0.5 + treble * 0.5 + scanRunner * 0.35 + mouseEnergy * 0.45) * (1.0 - clamp(edge, 0.0, 1.0));
    var interior  = mix(src.rgb, noiseCol, clamp(dissolve * 2.0, 0.0, 1.0));

    // Idea 2: neon threshold fringe — a coarse drifting field is cut at the
    // same dissolve level: cells under it are fully eaten into colour noise
    // and the cut contour itself is drawn as a thin neon line.
    let level     = clamp(dissolve * 2.0, 0.0, 1.0);
    let levelOn   = smoothstep(0.0, 0.03, level);
    let cellField = valueNoise(uv * vec2<f32>(aspect, 1.0) * 7.0 + vec2<f32>(time * 0.35, -time * 0.22));
    let eaten     = (1.0 - smoothstep(level - 0.02, level + 0.02, cellField)) * levelOn;
    let fringe    = (1.0 - smoothstep(0.0, 0.025, abs(cellField - level))) * levelOn;
    interior      = mix(interior, noiseCol, eaten);
    let fringeCol = neonCol * fringe * 0.9 * (1.0 + bass) * flick;

    // Blend: edges overlay on interior, then ACES on display RGB
    var finalRGB = interior + neonGlow + fringeCol;
    finalRGB = acesToneMap(max(finalRGB, vec3<f32>(0.0)));

    // Semantic alpha: eaten interior loses coverage, neon light keeps it
    let alpha = clamp(src.a * (1.0 - eaten * 0.35 - level * 0.2) + edge * 0.8 + core * 0.2 + fringe * 0.4, 0.0, 1.0);

    let outColor = vec4<f32>(finalRGB, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(edge + core * 0.25, 0.0, 1.0), 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, outColor);
}
