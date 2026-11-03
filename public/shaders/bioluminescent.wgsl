// ═══════════════════════════════════════════════════════════════
//  Bioluminescent Growth
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal-persistence, depth-aware
//  Upgraded: 2026-09-12, 2026-10-31
//  Ideas: spore tropism toward live click inoculum; quorum flash where growth exceeds neighbors; luciferin recharge wave in C.g; hyphal tip frontier and fruiting gill striations
//  A packing: raw (growth, luciferinCharge, 0, 1)
// ═══════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const BIO_TISSUE_DENSITY: f32 = 2.0;
const VEIN_OPACITY: f32 = 0.85;
const GLOW_TRANSPARENCY: f32 = 0.6;

fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3d(p: vec3<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    var u2 = f * f * (3.0 - 2.0 * f);
    let n = i.x + i.y * 57.0 + i.z * 113.0;
    return mix(mix(mix(hash(vec2<f32>(n + 0.0, 0.0)), hash(vec2<f32>(n + 1.0, 0.0)), u2.x),
                   mix(hash(vec2<f32>(n + 57.0, 0.0)), hash(vec2<f32>(n + 58.0, 0.0)), u2.x), u2.y),
               mix(mix(hash(vec2<f32>(n + 113.0, 0.0)), hash(vec2<f32>(n + 114.0, 0.0)), u2.x),
                   mix(hash(vec2<f32>(n + 170.0, 0.0)), hash(vec2<f32>(n + 171.0, 0.0)), u2.x), u2.y), u2.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadState(coord: vec2<i32>, maxCoord: vec2<i32>) -> vec2<f32> {
    return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), maxCoord), 0).rg;
}

fn bio_color(t: f32, mode: f32, pulse: f32) -> vec3<f32> {
    let pulse_beat = sin(t * 10.0 + pulse * 5.0) * 0.3 + 0.7;
    let pal0 = vec3<f32>(0.2, 1.0, 0.3);
    let pal1 = vec3<f32>(0.1, 0.6, 1.0);
    let pal2 = vec3<f32>(1.0, 0.2, 0.8);
    let pal3 = vec3<f32>(1.0, 0.4, 0.1);
    let idx = clamp(mode, 0.0, 0.999) * 4.0;
    let i0 = i32(idx);
    let f = fract(idx);
    var a = pal0;
    var b = pal1;
    if (i0 == 1) { a = pal1; b = pal2; }
    if (i0 == 2) { a = pal2; b = pal3; }
    if (i0 >= 3) { a = pal3; b = pal0; }
    return mix(a, b, f) * pulse_beat;
}

fn calculateGrowthAlpha(growth: f32, vein_pattern: f32, glow_intensity: f32) -> f32 {
    let densityAlpha = mix(0.2, VEIN_OPACITY, growth);
    let veinAlpha = mix(densityAlpha, VEIN_OPACITY * 0.95, vein_pattern * 0.5);
    let glowAlpha = mix(veinAlpha, GLOW_TRANSPARENCY, glow_intensity * growth * 0.6);
    let absorption = exp(-growth * BIO_TISSUE_DENSITY * 0.5);
    let finalAlpha = mix(glowAlpha, glowAlpha * 0.7, absorption * 0.3);
    return clamp(finalAlpha, 0.25, 0.92);
}

fn growthSSS(growth: f32, vein_pattern: f32, baseColor: vec3<f32>) -> vec3<f32> {
    let absorptionR = exp(-growth * 1.2);
    let absorptionG = exp(-growth * 0.9);
    let absorptionB = exp(-growth * 0.7);
    let scattered = vec3<f32>(
        baseColor.r * absorptionR,
        baseColor.g * absorptionG,
        baseColor.b * absorptionB
    );
    let veinScatter = vein_pattern * vec3<f32>(0.3, 0.5, 0.4) * growth;
    return scattered + veinScatter;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);
    let uv = vec2<f32>(coord) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let aspect = resolution.x / max(resolution.y, 1.0);

    let spread_mult = 1.0 + u.zoom_params.x * 0.1;
    let branch_density = u.zoom_params.y;
    let glow_intensity = u.zoom_params.z;
    let spore_count = u32(u.zoom_params.w * 10.0);
    let color_mode = fract(mids * 0.45 + treble * 0.15);
    let pulse = bass;

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    let prev = loadState(coord, maxCoord);
    var growth = prev.x;
    var luciferin = select(prev.y, 0.75, time < 0.1);

    let ripple_count = min(u32(u.config.y), 50u);
    var nearest = 8.0;
    var sporeDir = vec2<f32>(0.0);
    for (var i: u32 = 0u; i < min(ripple_count, spore_count + 1u); i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.1 && age < 2.0) {
            let d_aspect = distance(uv * vec2<f32>(aspect, 1.0), ripple.xy * vec2<f32>(aspect, 1.0));
            let influence = smoothstep(0.05, 0.0, d_aspect) * (1.0 - smoothstep(1.5, 2.0, age));
            growth = max(growth, influence);
            luciferin = max(luciferin, influence);
            if (d_aspect < nearest) {
                nearest = d_aspect;
                sporeDir = ripple.xy - uv;
            }
        }
    }

    let heldDist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    growth = max(growth, smoothstep(0.045, 0.0, heldDist) * f32(held) * 0.85);

    let sL = loadState(coord + vec2<i32>(-1, 0), maxCoord);
    let sR = loadState(coord + vec2<i32>(1, 0), maxCoord);
    let sD = loadState(coord + vec2<i32>(0, -1), maxCoord);
    let sU = loadState(coord + vec2<i32>(0, 1), maxCoord);
    let nL = sL.x;
    let nR = sR.x;
    let nD = sD.x;
    let nU = sU.x;
    let neighbor_avg = (nL + nR + nD + nU) * 0.25;
    let neighbor_luciferin = (sL.y + sR.y + sD.y + sU.y) * 0.25;
    let depth_mask = smoothstep(0.1, 0.9, depth);
    growth = min(1.0, growth * 0.998 + neighbor_avg * spread_mult * depth_mask * branch_density);

    // Idea 1 — spore tropism: extra growth from the neighbor that faces the inoculum
    let dirLen = max(length(sporeDir), 0.0001);
    let dir = sporeDir / dirLen;
    let towardCoord = coord + vec2<i32>(i32(sign(dir.x)), i32(sign(dir.y)));
    let toward = loadState(towardCoord, maxCoord).x;
    let tropism = (1.0 - smoothstep(0.0, 0.28, nearest)) * (0.12 + u.zoom_params.x * 0.08);
    growth = min(1.0, growth + toward * tropism * (1.0 - growth));

    // Idea 2 — quorum flash where local growth exceeds the neighbor field
    let quorum = clamp(growth - neighbor_avg, 0.0, 1.0);

    // ── Idea 3: luciferin metabolic recharge wave in dataTextureA.g ──
    let recharge = (0.022 + neighbor_luciferin * 0.08) * (1.0 - luciferin) * smoothstep(0.05, 0.35, growth);
    let discharge = quorum * 0.38 * luciferin;
    luciferin = clamp(mix(luciferin, neighbor_luciferin, 0.14) + recharge - discharge, 0.0, 1.0);

    textureStore(dataTextureA, coord, vec4<f32>(growth, luciferin, 0.0, 1.0));

    let vein_noise = noise3d(vec3<f32>(uv * 20.0, time * 0.5 * (1.0 + treble * 0.2)));
    let veins = smoothstep(0.3, 0.7, growth + vein_noise * 0.2);

    let glow_falloff = pow(max(growth, 0.0), 2.0) * glow_intensity;
    let metabolicWave = 0.65 + 0.35 * sin(time * 5.5 - growth * 10.0 + luciferin * 6.28318);
    var bio_light = bio_color(time, color_mode, pulse) * glow_falloff * (0.6 + 0.65 * luciferin * metabolicWave);

    bio_light += bio_light * pow(quorum * 3.2, 2.0) * (0.55 + bass * 0.6) * (0.5 + 0.8 * luciferin);

    // ── Idea 4: hyphal tip frontier & mature fruiting gill striations ──
    let growthGrad = vec2<f32>(nR - nL, nU - nD);
    let gradMag = length(growthGrad);
    let hyphalTip = gradMag * smoothstep(0.06, 0.45, growth) * (1.0 - smoothstep(0.65, 0.92, growth));
    let gillAngle = atan2(growthGrad.y, growthGrad.x);
    let gillStriation = (0.5 + 0.5 * cos(gillAngle * 12.0 + dot(uv, vec2<f32>(45.0, -38.0)))) * smoothstep(0.62, 0.92, growth);
    bio_light += vec3<f32>(0.35, 1.0, 0.78) * hyphalTip * glow_intensity * 1.4;

    let ss_scatter = smoothstep(0.0, 0.5, growth) * 0.3;
    let scatteredBase = growthSSS(growth, veins, base_color) * (1.0 - gillStriation * 0.22);
    let growth_alpha = calculateGrowthAlpha(growth, veins, glow_intensity);
    var final_color = scatteredBase * (1.0 - veins * 0.3) + bio_light + ss_scatter;
    final_color = acesToneMap(max(final_color, vec3<f32>(0.0)));

    textureStore(writeTexture, coord, vec4<f32>(final_color, growth_alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
