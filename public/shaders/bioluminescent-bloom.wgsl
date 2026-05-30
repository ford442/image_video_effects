// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Bloom v2
//  Category: generative
//  Features: audio-reactive, reaction-diffusion, gray-scott, chemotaxis,
//            quorum-sensing, volumetric-scatter, upgraded-rgba
//  Complexity: Very High
//  Created: 2026-05-31
//  Upgraded: 2026-05-31
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz;

    let tendrilCount = 3 + i32(u.zoom_params.x * 5.0);
    let pulseSpeed = u.zoom_params.y * 2.0;
    let dotDensity = u.zoom_params.z;
    let glowRadius = u.zoom_params.w;

    let aspect = res.x / res.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);

    // Background bioluminescent tendrils
    var bgCol = vec3<f32>(0.0, 0.02, 0.05);
    var bgGlow = 0.0;

    for (var ti = 0; ti < tendrilCount; ti = ti + 1) {
        let tf = f32(ti);
        let baseAngle = (tf / f32(tendrilCount) - 0.5) * 1.5 + 1.5708;
        let wave = sin(uv.x * 8.0 + tf * 2.1 + time * pulseSpeed) * 0.15;
        let wave2 = cos(uv.x * 15.0 - tf * 1.7 + time * pulseSpeed * 1.3) * 0.08;

        var minTendrilDist = 1e9;
        for (var si = 0; si < 20; si = si + 1) {
            let sf = f32(si) / 20.0;
            let ty = -0.4 + sf * 0.9;
            let tx = (baseAngle - 1.5708) * 0.3 * sf + wave * sf + wave2 * sf * sf;
            let tpos = vec2<f32>(tx, ty);
            let td = length(p - tpos);
            let width = 0.008 * (1.0 + sf * 0.5) * (1.0 + bass * 0.3);
            let seg = smoothstep(width, 0.0, td);
            minTendrilDist = min(minTendrilDist, td / width);
            bgGlow = bgGlow + seg * (1.0 - sf * 0.3);

            let pulse = sin(time * 3.0 + tf * 5.0 + sf * 10.0) * 0.5 + 0.5;
            let nodeSize = 0.012 * pulse * (1.0 + treble);
            let node = smoothstep(nodeSize, 0.0, td);
            bgGlow = bgGlow + node * 2.0;
        }

        let tendrilCol = vec3<f32>(0.1, 0.8, 0.6) * (0.5 + mids * 0.5);
        bgCol = bgCol + tendrilCol * smoothstep(1.0, 0.0, minTendrilDist);
    }

    // Scattered glow dots
    let dotUV = uv * 30.0;
    let dotId = floor(dotUV);
    let dotFract = fract(dotUV) - 0.5;
    let dotPhase = hash21(dotId) * 6.28 + time * (0.5 + hash21(dotId + vec2<f32>(1.0, 0.0)) * 2.0);
    let dotPulse = sin(dotPhase) * 0.5 + 0.5;
    let dot = smoothstep(0.08 * dotPulse * dotDensity, 0.0, length(dotFract));
    let dotCol = vec3<f32>(0.2, 1.0, 0.7) * dot * (0.3 + bass * 0.7);
    bgCol = bgCol + dotCol;
    bgGlow = bgGlow + dot;

    let ambient = smoothstep(0.5, 0.0, length(p)) * 0.1 * glowRadius;
    bgCol = bgCol + vec3<f32>(0.05, 0.15, 0.2) * ambient;

    // Reaction-diffusion Gray-Scott colony layer
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let texel = 1.0 / res;
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(-texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, -texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let Du = 0.18;
    let Dv = 0.09;
    let feed = 0.025 + bass * 0.015;
    let kill = 0.055 - mids * 0.008;

    let uVal = prev.r;
    let vVal = prev.g;

    let lapU = left.r + right.r + up.r + down.r - 4.0 * uVal;
    let lapV = left.g + right.g + up.g + down.g - 4.0 * vVal;

    let uv2 = uVal * vVal * vVal;
    let du = Du * lapU - uv2 + feed * (1.0 - uVal);
    let dv = Dv * lapV + uv2 - (feed + kill) * vVal;

    // Chemotaxis toward mouse nutrient source
    let gradN = normalize(mouse - uv + vec2<f32>(0.0001));
    let motility = 0.02 + mids * 0.03;
    let chemoU = motility * (gradN.x * (right.r - left.r) + gradN.y * (up.r - down.r));
    let chemoV = motility * (gradN.x * (right.g - left.g) + gradN.y * (up.g - down.g));

    var un = uVal + du + chemoU;
    var vn = vVal + dv + chemoV;

    // Mouse nutrient pellet drop
    let pellet = smoothstep(0.03, 0.0, length(uv - mouse)) * u.zoom_config.w;
    un = un + pellet * 0.4;

    // Treble flash events (stress response)
    let flash = step(0.75, treble) * hash21(uv * 20.0 + time * 3.0) * 0.25;
    vn = vn + flash;

    un = clamp(un, 0.0, 1.0);
    vn = clamp(vn, 0.0, 1.0);

    // Quorum sensing glow activation
    let quorum = smoothstep(0.18, 0.28, vn);
    let glow = vn * quorum * 5.0;

    // Depth attenuation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let attenuation = 1.0 - depth * 0.6;

    // Colony density
    let density = clamp(un + vn * 0.5, 0.0, 1.0);

    // Deep ocean bioluminescence palette
    var col = mix(vec3<f32>(0.0, 0.04, 0.08), vec3<f32>(0.0, 0.5, 0.6), glow);
    col = mix(col, vec3<f32>(0.2, 0.9, 0.6), smoothstep(0.4, 1.0, glow));

    // Blend background tendrils behind colony
    col = col + bgCol * (1.0 - density);

    // Volumetric light scatter
    let scatter = smoothstep(0.5, 0.0, length(uv - 0.5)) * glow * 0.3;
    col = col + vec3<f32>(0.1, 0.3, 0.4) * scatter;

    // HDR bloom on quorum activation waves
    let bloom = pow(quorum, 2.0) * 2.5 * (1.0 + bass);
    col = col + vec3<f32>(0.4, 0.8, 1.0) * bloom;

    // ACES tone mapping
    col = aces_tone_map(col);

    let alpha = clamp(density * glow * attenuation + bgGlow * 0.1, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(un, vn, glow, density));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(glow * 0.4 * attenuation, 0.0, 0.0, 0.0));
}
