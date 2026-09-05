// ═══════════════════════════════════════════════════════════════════
//  Glass Wall Prismatic
//  Category: advanced-hybrid
//  Features: mouse-driven, spectral-rendering, physical-dispersion,
//            refraction, audio-reactive, exact-feedback
//  Complexity: Very High
// ═══════════════════════════════════════════════════════════════════
//  A grid of glass tiles where each tile acts as a prismatic lens
//  with 4-band spectral dispersion via Cauchy's equation. Mouse
//  interaction tilts tiles with spring physics, refracting light
//  into rainbow spectra with mortar grooves and Fresnel highlights.
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
    zoom_params: vec4<f32>,  // x=GridSize, y=Curvature, z=Dispersion, w=Thickness
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

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001;
    return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
    let g = 1.0 - abs(t - 0.4) * 3.0;
    let b = 1.0 - smoothstep(0.0, 0.4, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
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
            targetPos = vec2<f32>(0.5 + 0.22 * sin(time * 0.7), 0.5 + 0.22 * cos(time * 0.85));
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
    let gridSize = mix(6.0, 26.0, u.zoom_params.x);
    let glassCurvature = mix(0.15, 1.1, u.zoom_params.y);
    let cauchyB = mix(0.01, 0.08, u.zoom_params.z);
    let glassThickness = mix(0.3, 1.4, u.zoom_params.w);

    let distMouse = length((uv - smoothMouse) * aspectVec);
    let holdEffect = smoothstep(0.45, 0.0, distMouse) * select(0.35, 1.0, isMouseDown);

    // Capped click ripple fronts
    var rippleOffset = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rAge = time - r.z;
        if (r.z > 0.0 && rAge > 0.0 && rAge < 2.5) {
            let toRip = (uv - r.xy) * aspectVec;
            let rDist = length(toRip);
            let env = smoothstep(2.5, 0.0, rAge);
            let phase = rDist * 38.0 - rAge * 12.0;
            let wave = sin(phase) * exp(-rDist * 5.5) * env;
            rippleOffset = rippleOffset + normalize(toRip + vec2<f32>(0.001)) * wave * 0.04;
        }
    }
    rippleOffset = rippleOffset + normalize((uv - smoothMouse) * aspectVec + vec2<f32>(0.001)) * sin(distMouse * 32.0 - time * 8.0) * exp(-distMouse * 6.5) * clickImpulse * 0.03;

    let scale = vec2<f32>(gridSize * aspect, gridSize);
    let scaledUV = uv * scale + rippleOffset * scale * 0.25;
    let cellID = floor(scaledUV);
    let cellUV = fract(scaledUV);
    let cellCenter = (cellID + vec2<f32>(0.5)) / scale;

    let vecToMouse = (smoothMouse - cellCenter) * aspectVec;
    let distToCell = length(vecToMouse);
    let influence = smoothstep(0.85, 0.0, distToCell);

    var tilt = vec2<f32>(0.0);
    if (distToCell > 0.001) {
        tilt = normalize(vecToMouse) * influence * (0.45 + mids * 0.4 + holdEffect * 0.35);
    }

    // Bevel normal profile
    let bevelX = smoothstep(0.0, 0.12, cellUV.x) * (1.0 - smoothstep(0.88, 1.0, cellUV.x));
    let bevelY = smoothstep(0.0, 0.12, cellUV.y) * (1.0 - smoothstep(0.88, 1.0, cellUV.y));
    let bevel = bevelX * bevelY;

    let nx = -(smoothstep(0.0, 0.12, cellUV.x) - smoothstep(0.88, 1.0, cellUV.x)) * bevelY;
    let ny = -(smoothstep(0.0, 0.12, cellUV.y) - smoothstep(0.88, 1.0, cellUV.y)) * bevelX;
    var normal = normalize(vec3<f32>(nx, ny, 2.0));
    normal = normalize(normal + vec3<f32>(tilt * 2.2, 0.0) + vec3<f32>(rippleOffset * 8.0, 0.0));

    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var dispersedColor = vec3<f32>(0.0);
    var totalWeight = 0.0;

    for (var i: i32 = 0; i < 4; i = i + 1) {
        let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB + bass * 0.04);
        let refractDir = refract(vec3<f32>(0.0, 0.0, -1.0), normal, 1.0 / ior);
        let refractOffset = refractDir.xy * glassCurvature * 0.35;
        let refractedUV = clamp(uv + refractOffset, vec2<f32>(0.0), vec2<f32>(1.0));

        let sample = textureSampleLevel(readTexture, u_sampler, refractedUV, 0.0).rgb;
        let absorption = exp(-glassThickness * (4.0 - f32(i)) * 0.14);
        let bandIntensity = sample * absorption;
        let wCol = wavelengthToRGB(WAVELENGTHS[i]);

        dispersedColor = dispersedColor + wCol * bandIntensity;
        totalWeight = totalWeight + absorption;
    }
    dispersedColor = dispersedColor * (2.2 / max(totalWeight, 0.001));

    let glassColor = mix(vec3<f32>(0.93, 0.96, 1.0), vec3<f32>(1.0, 0.91, 0.96), treble);
    let thickness = 0.05 + (1.0 - bevel) * 0.1 + length(tilt) * 0.06;
    let absorptionGlass = exp(-(vec3<f32>(1.0) - glassColor) * thickness * 2.5);
    let transmission = (absorptionGlass.r + absorptionGlass.g + absorptionGlass.b) * 0.3333;

    var finalColor = dispersedColor * glassColor;

    // Fresnel reflection
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let cosTheta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.04;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cosTheta, 4.5);

    let lightDir = normalize(vec3<f32>(vecToMouse, 0.6));
    let spec = pow(max(dot(normal, lightDir), 0.0), 36.0) * influence * (1.0 + treble);
    finalColor = finalColor + vec3<f32>(spec * 0.85);

    // Mortar groove lines
    let mortar = smoothstep(0.0, 0.06, cellUV.x) * smoothstep(1.0, 0.94, cellUV.x) *
                 smoothstep(0.0, 0.06, cellUV.y) * smoothstep(1.0, 0.94, cellUV.y);
    let blendedTransmission = mix(transmission * 0.25, transmission, mortar);
    finalColor = mix(finalColor * 0.35, finalColor, mortar);

    // Exact temporal feedback from dataTextureC
    let prevData = textureLoad(dataTextureC, pixel, 0).rgb;
    finalColor = mix(finalColor, prevData, 0.1 + mids * 0.06);

    let tonemapped = acesToneMap(finalColor * (1.0 + treble * 0.1));
    let alpha = clamp(blendedTransmission + fresnel * 0.4 + holdEffect * 0.2 + clickImpulse * 0.15, 0.2, 0.98);
    let outputRGBA = vec4<f32>(tonemapped, alpha);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, pixel, outputRGBA);
    textureStore(dataTextureA, pixel, outputRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
