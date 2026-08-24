// ═══════════════════════════════════════════════════════════════════
//  Holographic Interferometry Bilateral
//  Category: advanced-hybrid
//  Features: advanced-hybrid, holography, bilateral-filter,
//            interference-patterns, speckle-reduction, audio-reactive,
//            mouse-driven, exact-feedback
//  Complexity: High
// ═══════════════════════════════════════════════════════════════════
//  Simulated hologram with interference fringes and edge-preserving
//  bilateral filtering. High-frequency laser speckle noise is softly
//  filtered in flat zones while crisp interference fringe edges are
//  strictly preserved.
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
    zoom_params: vec4<f32>,  // x=FringeDensity, y=Coherence, z=ReconAngle, w=Saturation
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
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

fn speckleNoise(uv: vec2<f32>, coherence: f32, time: f32) -> f32 {
    let scale = mix(80.0, 420.0, coherence);
    var s = 0.0;
    for (var i = 0; i < 4; i = i + 1) {
        let fi = f32(i);
        s = s + hash12(uv * scale + vec2<f32>(fi * 13.7 + time * 0.04, fi * 42.3 - time * 0.02));
    }
    return s * 0.25;
}

fn interferencePattern(uv: vec2<f32>, depth: f32, fringeDensity: f32, angle: f32, distortion: f32) -> f32 {
    let objectPhase = depth * fringeDensity * 12.0 + distortion;
    let refPhase = (uv.x * cos(angle) + uv.y * sin(angle)) * fringeDensity * 45.0;
    let phaseDiff = objectPhase + refPhase;
    return 0.5 + 0.5 * cos(phaseDiff);
}

fn spectralReconstruct(totalPhase: f32, intensity: f32, satVal: f32) -> vec3<f32> {
    let hue = fract(totalPhase / TAU);
    let sat = clamp(0.65 + intensity * 0.35, 0.0, 1.0) * satVal;
    let val = clamp(0.45 + intensity * 0.55, 0.0, 1.5);

    let c = val * sat;
    let h = hue * 6.0;
    let x = c * (1.0 - abs(fract(h * 0.5) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);

    if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }

    return rgb + vec3<f32>(val - c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let time = u.config.x;
    let isMouseDown = u.zoom_config.w > 0.5;
    let mouseUV = u.zoom_config.yz;

    // Persistent single-writer state management
    if (global_id.x == 0u && global_id.y == 0u) {
        var targetPos = mouseUV;
        if (!isMouseDown && extraBuffer[137] < 0.5) {
            targetPos = vec2<f32>(0.5 + 0.22 * sin(time * 0.8), 0.5 + 0.22 * cos(time * 0.6));
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
    let pixelSize = 1.0 / res;
    let aspect = res.x / res.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sliders
    let fringeDensity = mix(15.0, 100.0, u.zoom_params.x);
    let coherence = clamp(u.zoom_params.y, 0.0, 1.0);
    let reconAngle = u.zoom_params.z * TAU + (smoothMouse.x - 0.5) * 1.5;
    let saturation = mix(0.5, 1.8, u.zoom_params.w);

    let distMouse = length((uv - smoothMouse) * aspectVec);
    let holdEffect = smoothstep(0.4, 0.0, distMouse) * select(0.3, 1.0, isMouseDown);

    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depthSrc = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let geo = sin(uv.x * 20.0 + time + bass) * cos(uv.y * 20.0 - time + mids) * 0.08;
    let depth = depthSrc + geo;
    let luma = dot(sourceColor, vec3<f32>(0.2126, 0.7152, 0.0722));

    // Capped click ripple fronts
    var rippleDistortion = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rAge = time - r.z;
        if (r.z > 0.0 && rAge > 0.0 && rAge < 2.5) {
            let rDist = length((uv - r.xy) * aspectVec);
            let env = smoothstep(2.5, 0.0, rAge);
            let wave = sin(rDist * 36.0 - rAge * 11.0) * exp(-rDist * 6.5) * env;
            rippleDistortion = rippleDistortion + wave * 0.35;
        }
    }
    rippleDistortion = rippleDistortion + sin(distMouse * 32.0 - time * 8.0) * exp(-distMouse * 7.5) * clickImpulse * 0.5;
    rippleDistortion = rippleDistortion + holdEffect * 0.25;

    // Center holographic sample
    let centerInterference = interferencePattern(uv, depth, fringeDensity, reconAngle, rippleDistortion);
    let centerPhase = acos(clamp(centerInterference * 2.0 - 1.0, -1.0, 1.0));
    let centerRecon = (uv.x * cos(reconAngle + 0.5) + uv.y * sin(reconAngle + 0.5)) * 22.0;
    let centerHolo = spectralReconstruct(centerPhase + centerRecon + rippleDistortion * 3.5, luma, saturation);
    let centerSpeckle = speckleNoise(uv + time * 0.005, coherence, time);
    let speckleMod = mix(1.0, 0.6 + 0.8 * centerSpeckle, coherence);
    let centerRaw = mix(sourceColor * 0.3, centerHolo * (luma * 1.2 + 0.2 + bass * 0.2) * speckleMod, 0.8);

    // Bilateral speckle-reduction filter over 5x5 footprint
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    let spatialSigma = mix(1.2, 2.8, coherence) * (1.0 + mids * 0.2);
    let rangeSigma = mix(0.08, 0.35, 1.0 - coherence * 0.5);
    let twoSpatialSq = 2.0 * spatialSigma * spatialSigma + 0.001;
    let twoRangeSq = 2.0 * rangeSigma * rangeSigma + 0.001;

    for (var dy = -2; dy <= 2; dy = dy + 1) {
        for (var dx = -2; dx <= 2; dx = dx + 1) {
            let offset = vec2<f32>(f32(dx), f32(dy));
            let sUV = clamp(uv + offset * pixelSize, vec2<f32>(0.0), vec2<f32>(1.0));
            let sColor = textureSampleLevel(readTexture, u_sampler, sUV, 0.0).rgb;
            let sDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sUV, 0.0).r + geo;
            let sLuma = dot(sColor, vec3<f32>(0.2126, 0.7152, 0.0722));
            let sInterf = interferencePattern(sUV, sDepth, fringeDensity, reconAngle, rippleDistortion);
            let sPhase = acos(clamp(sInterf * 2.0 - 1.0, -1.0, 1.0));
            let sRecon = (sUV.x * cos(reconAngle + 0.5) + sUV.y * sin(reconAngle + 0.5)) * 22.0;
            let sHolo = spectralReconstruct(sPhase + sRecon + rippleDistortion * 3.5, sLuma, saturation);
            let neighborVal = mix(sColor * 0.3, sHolo * (sLuma * 1.2 + 0.2 + bass * 0.2), 0.8);

            let spatialDistSq = dot(offset, offset);
            let spatialWeight = exp(-spatialDistSq / twoSpatialSq);
            let colorDistSq = dot(neighborVal - centerRaw, neighborVal - centerRaw);
            let rangeWeight = exp(-colorDistSq / twoRangeSq);

            let weight = spatialWeight * rangeWeight;
            accumColor = accumColor + neighborVal * weight;
            accumWeight = accumWeight + weight;
        }
    }

    let smoothedHolo = accumColor / max(accumWeight, 0.001);

    // Fringe edge confidence (1.0 = sharp fringe edge, 0.0 = smoothed interior)
    let edgeDiff = length(smoothedHolo - centerRaw);
    let edgeConfidence = clamp(edgeDiff * 4.0, 0.0, 1.0);

    let bilateralBlend = mix(0.75, 0.25, edgeConfidence);
    var finalHolo = mix(centerRaw, smoothedHolo, bilateralBlend);

    // Parallax depth view offset
    let parallax = (depth * 0.02 + holdEffect * 0.035) * (1.0 + mids * 0.25);
    let parallaxUV = clamp(uv + vec2<f32>(cos(reconAngle), sin(reconAngle)) * parallax, vec2<f32>(0.0), vec2<f32>(1.0));
    let parallaxColor = textureSampleLevel(readTexture, u_sampler, parallaxUV, 0.0).rgb;
    finalHolo = mix(finalHolo, parallaxColor * centerHolo, clamp(depth * 0.35 + holdEffect * 0.25, 0.0, 1.0));

    // Exact temporal feedback from dataTextureC
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    finalHolo = mix(finalHolo, prev, 0.12 + mids * 0.08);

    let finalColor = acesToneMap(finalHolo * (1.0 + treble * 0.15));
    let alpha = clamp(luma * 0.6 + edgeConfidence * 0.3 + holdEffect * 0.2 + clickImpulse * 0.2, 0.18, 0.98);
    let outputRGBA = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, pixel, outputRGBA);
    textureStore(dataTextureA, pixel, outputRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
