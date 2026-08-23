// ═══════════════════════════════════════════════════════════════════
//  Photonic Caustics Iridescence
//  Category: advanced-hybrid
//  Features: depth-aware, temporal, spectral-render, caustics,
//            audio-reactive, mouse-driven, exact-feedback
//  Complexity: Very High
// ═══════════════════════════════════════════════════════════════════
//  Backward photon-traced caustics combined with thin-film
//  optical iridescence. High-energy caustic focal concentrations
//  illuminate an iridescent surface layer with chromatic dispersion,
//  Fresnel reflections, and exact temporal feedback.
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
    zoom_params: vec4<f32>,  // x=IOR, y=LightSize, z=Dispersion, w=Intensity
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHOTON_COUNT: i32 = 12;

fn acesToneMap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract((p3.x + p3.y) * p3.z);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise2D(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    for (var i = 0; i < 3; i = i + 1) {
        value = value + amplitude * noise2D(p * freq + vec2<f32>(time * 0.2, time * 0.15));
        freq = freq * 2.0;
        amplitude = amplitude * 0.5;
    }
    return value;
}

fn getSurfaceNormal(uv: vec2<f32>, texelSize: vec2<f32>, time: f32, bass: f32) -> vec3<f32> {
    let hL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texelSize.x, 0.0), 0.0).r;
    let hR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).r;
    let hU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, -texelSize.y), 0.0).r;
    let hD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).r;

    let noiseScale = 8.0;
    let noiseAmp = 0.12 * (1.0 + bass * 0.4);
    let nL = fbm(uv * noiseScale + vec2<f32>(-texelSize.x * noiseScale, 0.0), time) * noiseAmp;
    let nR = fbm(uv * noiseScale + vec2<f32>(texelSize.x * noiseScale, 0.0), time) * noiseAmp;
    let nU = fbm(uv * noiseScale + vec2<f32>(0.0, -texelSize.y * noiseScale), time) * noiseAmp;
    let nD = fbm(uv * noiseScale + vec2<f32>(0.0, texelSize.y * noiseScale), time) * noiseAmp;

    let dx = ((hR + nR) - (hL + nL)) * 2.2;
    let dy = ((hD + nD) - (hU + nU)) * 2.2;

    return normalize(vec3<f32>(-dx, -dy, 0.22));
}

fn fresnelSchlick(cosTheta: f32, ior: f32) -> f32 {
    let r0 = (1.0 - ior) / (1.0 + ior);
    let r0sq = r0 * r0;
    return r0sq + (1.0 - r0sq) * pow(1.0 - cosTheta, 5.0);
}

fn refractRay(incident: vec3<f32>, normal: vec3<f32>, eta: f32) -> vec3<f32> {
    let cosi = -dot(normal, incident);
    let sin2t = eta * eta * (1.0 - cosi * cosi);
    if (sin2t > 1.0) {
        return reflect(incident, normal);
    }
    let cost = sqrt(1.0 - sin2t);
    return incident * eta + normal * (eta * cosi - cost);
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
    
    // Persistent single-writer state management
    if (global_id.x == 0u && global_id.y == 0u) {
        var targetPos = mouseUV;
        if (!isMouseDown && extraBuffer[137] < 0.5) {
            targetPos = vec2<f32>(0.5 + 0.25 * cos(time * 0.55), 0.5 + 0.2 * sin(time * 0.7));
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
    
    let smoothLight = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    let clickImpulse = extraBuffer[138];
    
    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let texelSize = 1.0 / res;
    let aspect = res.x / res.y;
    let aspectVec = vec2<f32>(aspect, 1.0);
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    // Sliders
    let baseIOR = mix(1.15, 1.85, u.zoom_params.x);
    let lightSize = mix(0.06, 0.35, u.zoom_params.y);
    let dispersion = mix(0.01, 0.09, u.zoom_params.z);
    let intensity = mix(0.4, 2.8, u.zoom_params.w);
    
    let lightHeight = 1.2;
    let distLight = length((uv - smoothLight) * aspectVec);
    let holdEffect = smoothstep(0.4, 0.0, distLight) * select(0.3, 1.0, isMouseDown);
    
    // Exact temporal feedback load from dataTextureC
    let prevCaustic = textureLoad(dataTextureC, pixel, 0).rgb;
    
    // Surface normal from depth & procedural fluid waves
    let surfaceNormal = getSurfaceNormal(uv, texelSize, time, bass);
    
    // Photonic photon-tracing accumulation
    var causticAccum = vec3<f32>(0.0);
    for (var p = 0; p < PHOTON_COUNT; p = p + 1) {
        let seed = vec3<f32>(uv, f32(p) + time * 0.02);
        let randomAngle = hash31(seed) * TAU;
        let randomRadius = sqrt(hash31(seed + vec3<f32>(1.0, 0.0, 0.0))) * lightSize;
        let photonOrigin = smoothLight + vec2<f32>(cos(randomAngle), sin(randomAngle)) * randomRadius;

        let toPixel = uv - photonOrigin;
        let dist2D = length(toPixel * aspectVec);
        let dir2D = toPixel / max(dist2D, 0.001);
        let lightDir = normalize(vec3<f32>(dir2D, -lightHeight));

        let cosTheta = abs(dot(lightDir, surfaceNormal));

        let iorR = baseIOR - dispersion;
        let iorG = baseIOR;
        let iorB = baseIOR + dispersion;

        let refractR = refractRay(lightDir, surfaceNormal, 1.0 / iorR);
        let refractG = refractRay(lightDir, surfaceNormal, 1.0 / iorG);
        let refractB = refractRay(lightDir, surfaceNormal, 1.0 / iorB);

        let convR = abs(dot(refractR, vec3<f32>(0.0, 0.0, -1.0)));
        let convG = abs(dot(refractG, vec3<f32>(0.0, 0.0, -1.0)));
        let convB = abs(dot(refractB, vec3<f32>(0.0, 0.0, -1.0)));

        let fresnel = 1.0 - fresnelSchlick(cosTheta, baseIOR);
        let attenuation = 1.0 / (1.0 + dist2D * 4.5);

        let cR = pow(convR, 5.0) * fresnel * attenuation;
        let cG = pow(convG, 5.0) * fresnel * attenuation;
        let cB = pow(convB, 5.0) * fresnel * attenuation;

        causticAccum = causticAccum + vec3<f32>(cR, cG, cB);
    }
    
    causticAccum = (causticAccum / f32(PHOTON_COUNT)) * intensity;
    
    // Capped click ripple caustics
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rAge = time - r.z;
        if (r.z > 0.0 && rAge > 0.0 && rAge < 2.5) {
            let toRipple = (uv - r.xy) * aspectVec;
            let dist = length(toRipple);
            let rippleStrength = smoothstep(2.5, 0.0, rAge) * 0.6;
            let wave = sin(dist * 35.0 - rAge * 11.0) * 0.5 + 0.5;
            let causticRing = wave * rippleStrength / (1.0 + dist * 8.0);
            causticAccum = causticAccum + vec3<f32>(causticRing * 0.5, causticRing * 0.75, causticRing * 1.0) * intensity;
        }
    }
    causticAccum = causticAccum + vec3<f32>(0.4, 0.7, 1.0) * sin(distLight * 30.0 - time * 8.0) * exp(-distLight * 6.5) * clickImpulse * intensity * 0.5;
    
    // Temporal caustics blend
    let accumulatedCaustic = mix(prevCaustic, causticAccum, 0.16 + mids * 0.08);
    let causticLuma = dot(accumulatedCaustic, vec3<f32>(0.2126, 0.7152, 0.0722));
    
    // Thin-film iridescence
    let filmThicknessBase = mix(220.0, 750.0, u.zoom_params.x);
    let filmIOR = mix(1.2, 2.4, u.zoom_params.y);
    let iridIntensity = mix(0.4, 1.6, u.zoom_params.z);
    let turbulence = clamp(u.zoom_params.w, 0.0, 1.0);
    
    let toCenter = uv - vec2<f32>(0.5);
    let distCenter = length(toCenter);
    let cosThetaView = sqrt(max(1.0 - distCenter * distCenter * 0.5, 0.02));
    
    let noiseVal = hash21(uv * 12.0 + time * 0.1) * 0.6 + hash21(uv * 24.0 - time * 0.15) * 0.4;
    let thickness = filmThicknessBase * (0.6 + causticLuma * 2.2 + noiseVal * turbulence * 0.4 + holdEffect * 0.3 + bass * 0.2);
    let iridescent = thinFilmColor(thickness, cosThetaView, filmIOR) * iridIntensity;
    let fresnelBlend = pow(1.0 - cosThetaView, 2.5);
    
    // Refracted source image
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    let refractDisplace = surfaceNormal.xy * (0.02 + holdEffect * 0.02);
    let colR = textureSampleLevel(readTexture, u_sampler, clamp(uv + refractDisplace + vec2<f32>(dispersion * 0.015, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, clamp(uv + refractDisplace, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, clamp(uv + refractDisplace - vec2<f32>(dispersion * 0.015, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let refractedChromatic = vec3<f32>(colR, colG, colB);
    
    var finalColor = mix(sourceColor, refractedChromatic, 0.45);
    finalColor = finalColor + accumulatedCaustic;
    finalColor = mix(finalColor, iridescent, fresnelBlend * 0.65 * clamp(causticLuma * 1.5, 0.0, 1.0));
    
    // Specular highlight
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let reflectDir = reflect(-viewDir, surfaceNormal);
    let lightDir3D = normalize(vec3<f32>((smoothLight - uv) * aspectVec, lightHeight));
    let specular = pow(max(dot(reflectDir, lightDir3D), 0.0), 48.0) * (1.0 + treble);
    finalColor = finalColor + vec3<f32>(specular * 0.6);
    
    let tonemapped = acesToneMap(finalColor * (1.0 + treble * 0.1));
    let alpha = clamp(dot(sourceColor, vec3<f32>(0.2126, 0.7152, 0.0722)) * 0.4 + causticLuma * 0.5 + holdEffect * 0.2 + clickImpulse * 0.15, 0.18, 0.98);
    let outputRGBA = vec4<f32>(tonemapped, alpha);
    
    textureStore(writeTexture, pixel, outputRGBA);
    textureStore(dataTextureA, pixel, outputRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
