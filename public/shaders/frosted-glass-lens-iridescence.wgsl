// ═══════════════════════════════════════════════════════════════════
//  Frosted Glass Lens Iridescence
//  Category: advanced-hybrid
//  Features: audio-reactive, mouse-driven, click-reactive, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-09-06
//  Ideas: microscopic condensation droplet beads; pointer-drag moisture wipe; lens bevel Cauchy prism dispersion
//  A packing: ACES display RGBA
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
    config: vec4<f32>,       // x=Time, y=RippleCount, zw=Resolution
    zoom_config: vec4<f32>,  // x=Time, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=FrostAmount, y=LensRadius, z=EdgeSoftness, w=FilmIOR
    ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn acesToneMap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
    let g = 1.0 - abs(t - 0.45) * 2.5;
    let b = 1.0 - smoothstep(0.0, 0.45, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
    let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
    let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
    let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;
    var color = vec3<f32>(0.0);
    var sampleCount = 0.0;
    for (var lambda = 390.0; lambda <= 690.0; lambda = lambda + 40.0) {
        let phase = opd / lambda;
        let interference = cos(phase * TAU) * 0.5 + 0.5;
        color = color + wavelengthToRGB(lambda) * interference;
        sampleCount = sampleCount + 1.0;
    }
    return color / max(sampleCount, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let time = u.config.x;
    let isMouseDown = u.zoom_config.w > 0.5;
    let mouseUV = u.zoom_config.yz;

    // Persistent single-writer state management in extraBuffer[133..138]
    if (global_id.x == 0u && global_id.y == 0u) {
        var targetPos = mouseUV;
        if (!isMouseDown && extraBuffer[137] < 0.5) {
            targetPos = vec2<f32>(0.5 + 0.2 * cos(time * 0.7), 0.5 + 0.2 * sin(time * 0.85));
        }

        var curP = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        if (curP.x == 0.0 && curP.y == 0.0) { curP = mouseUV; }

        var pVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        let diff = targetPos - curP;
        pVel = pVel + diff * 0.18;
        pVel = pVel * 0.82;
        curP = curP + pVel;

        extraBuffer[133] = clamp(curP.x, 0.0, 1.0);
        extraBuffer[134] = clamp(curP.y, 0.0, 1.0);
        extraBuffer[135] = clamp(pVel.x, -0.05, 0.05);
        extraBuffer[136] = clamp(pVel.y, -0.05, 0.05);

        let prevDown = extraBuffer[137];
        var rippleImpulse = extraBuffer[138] * 0.94;
        if (isMouseDown && prevDown < 0.5) {
            rippleImpulse = 1.0;
        }
        extraBuffer[137] = select(0.0, 1.0, isMouseDown);
        extraBuffer[138] = rippleImpulse;
    }

    let smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    let clickImpulse = extraBuffer[138];

    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let aspect = res.x / res.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sliders
    let rawFrost = clamp(u.zoom_params.x, 0.0, 1.0);
    let lensRadius = mix(0.12, 0.72, u.zoom_params.y);
    let edgeSoftness = mix(0.02, 0.28, u.zoom_params.z);
    let filmIOR = mix(1.2, 2.4, u.zoom_params.w);

    let distVec = (uv - smoothMouse) * aspectVec;
    let dist = length(distVec);
    let holdEffect = smoothstep(0.35, 0.0, dist) * select(0.3, 1.0, isMouseDown);

    // ─── Native Idea 2: Pointer-Drag Moisture Wipe ───
    // Held pointer clears frost and condensation, creating a clean glass trail
    let wipeFactor = smoothstep(lensRadius * 0.85, 0.0, dist) * select(0.4, 0.95, isMouseDown);
    let frostAmt = rawFrost * (1.0 - wipeFactor * 0.85);

    // Capped click ripple fronts
    var rippleDistortion = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rAge = time - r.z;
        if (r.z > 0.0 && rAge > 0.0 && rAge < 2.5) {
            let rDist = length((uv - r.xy) * aspectVec);
            let env = smoothstep(2.5, 0.0, rAge);
            let wave = sin(rDist * 34.0 - rAge * 11.0) * exp(-rDist * 6.0) * env;
            rippleDistortion = rippleDistortion + wave * 0.35;
        }
    }
    rippleDistortion = rippleDistortion + sin(dist * 30.0 - time * 8.0) * exp(-dist * 7.0) * clickImpulse * 0.5;

    // Lens magnification & chromatic dispersion
    let lensMask = 1.0 - smoothstep(lensRadius, lensRadius + edgeSoftness, dist);
    let lensBulge = (1.0 - dist / (lensRadius + edgeSoftness + 0.001)) * lensMask;
    let magStrength = (0.25 + holdEffect * 0.35 + bass * 0.15) * lensMask;
    let lensOffset = -normalize(distVec + vec2<f32>(0.0001)) * lensBulge * magStrength;

    // ─── Native Idea 1: Microscopic Condensation Droplet Beads ───
    let dropGrid = uv * 36.0;
    let dropId = floor(dropGrid);
    let dropFract = fract(dropGrid) - vec2<f32>(0.5);
    let dropSeed = hash12(dropId);
    let dropRadius = 0.22 * (0.5 + dropSeed * 0.5);
    let dropDist = length(dropFract);
    let dropMask = smoothstep(dropRadius, dropRadius * 0.6, dropDist) * step(0.68, dropSeed) * frostAmt;
    let dropRefract = dropFract * dropMask * 0.018;

    // Multi-tap microfacet frost scattering
    let noiseVal = hash12(uv * 180.0 + vec2<f32>(time * 0.05, -time * 0.03));
    let noiseAngle = hash12(uv * 90.0 - time * 0.02) * TAU;
    let scatterRadius = (frostAmt * 0.025 * (1.0 - lensMask * 0.7) + rippleDistortion * 0.01) * (1.0 + mids * 0.3);
    let frostOffset = vec2<f32>(cos(noiseAngle), sin(noiseAngle)) * noiseVal * scatterRadius;

    let caStrength = (0.006 * frostAmt + 0.012 * lensMask + treble * 0.004) * smoothstep(0.0, lensRadius, dist);
    let caDir = normalize(distVec + vec2<f32>(0.0001));

    let baseUV = uv + lensOffset + frostOffset + dropRefract;
    let uvR = clamp(baseUV + caDir * caStrength, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(baseUV, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(baseUV - caDir * caStrength * 0.8, vec2<f32>(0.0), vec2<f32>(1.0));

    let colR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    var scatteredColor = vec3<f32>(colR, colG, colB);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvG, 0.0).r;

    // Beer-Lambert glass absorption
    let glassThickness = 0.04 + frostAmt * 0.12 * (1.0 + noiseVal) + depth * 0.08;
    let glassTint = mix(vec3<f32>(0.92, 0.96, 1.0), vec3<f32>(0.98, 0.93, 0.99), treble);
    let absorption = exp(-(vec3<f32>(1.0) - glassTint) * glassThickness * 3.5);
    let transmission = (absorption.r + absorption.g + absorption.b) * 0.3333;

    // Thin-film iridescence coating on glass surface
    let toCenter = uv - vec2<f32>(0.5);
    let viewDist = length(toCenter);
    let cosTheta = sqrt(max(1.0 - viewDist * viewDist * 0.5, 0.02));

    let filmThicknessBase = 220.0 + frostAmt * 450.0 + lensMask * 200.0;
    let filmNoise = hash12(uv * 14.0 + time * 0.08) * 0.6 + hash12(uv * 28.0 - time * 0.12) * 0.4;
    let thickness = filmThicknessBase * (0.65 + depth * 0.5 + filmNoise * 0.35 + holdEffect * 0.3 + bass * 0.2);

    let iridescent = thinFilmColor(thickness, cosTheta, filmIOR);
    let R0 = 0.04;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cosTheta, 4.0);
    let edgeIridescence = fresnel * (0.4 + frostAmt * 0.5 + lensMask * 0.4);

    // Composite glass layers
    var finalColor = scatteredColor * absorption * glassTint;
    finalColor = mix(finalColor, iridescent, edgeIridescence * 0.65);

    // Lens bevel specular highlight & Native Idea 3: Bevel Prism Dispersion
    let bevelMask = smoothstep(lensRadius - 0.02, lensRadius, dist) * (1.0 - smoothstep(lensRadius, lensRadius + edgeSoftness, dist));
    let normalBevel = normalize(vec3<f32>(distVec * 15.0, 1.0));
    let specLight = normalize(vec3<f32>(0.5, 0.8, -0.6));
    let spec = pow(max(dot(normalBevel, specLight), 0.0), 40.0) * bevelMask * (1.0 + treble);

    // Idea 3: Bevel Cauchy spectral separation
    let bevelDispersion = normalBevel.xy * (0.014 + treble * 0.012) * bevelMask;
    let prismR = textureSampleLevel(readTexture, u_sampler, clamp(baseUV + bevelDispersion, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let prismB = textureSampleLevel(readTexture, u_sampler, clamp(baseUV - bevelDispersion * 0.8, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    finalColor = mix(finalColor, vec3<f32>(prismR, finalColor.g, prismB), bevelMask * 0.6);
    finalColor = finalColor + vec3<f32>(spec * 0.8);

    // Exact temporal feedback from dataTextureC
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    finalColor = mix(finalColor, prev, 0.1 + mids * 0.08);

    let tonemapped = acesToneMap(finalColor * (1.0 + treble * 0.1));
    let alpha = clamp(transmission * 0.6 + edgeIridescence * 0.3 + bevelMask * 0.3 + holdEffect * 0.15 + dropMask * 0.2, 0.2, 0.98);
    let outputRGBA = vec4<f32>(tonemapped, alpha);

    textureStore(writeTexture, pixel, outputRGBA);
    textureStore(dataTextureA, pixel, outputRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
