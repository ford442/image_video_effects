// ═══════════════════════════════════════════════════════════════════
//  Chroma Lens Iridescence
//  Category: advanced-hybrid
//  Features: chroma-lens, thin-film-interference, depth-aware,
//            mouse-driven, audio-reactive, exact-feedback
//  Complexity: High
// ═══════════════════════════════════════════════════════════════════
//  Chromatic lens magnification fused with physical thin-film
//  optical iridescence. The lens body exhibits true wavelength-
//  dependent interference, radial chromatic aberration, and Fresnel
//  bevel reflections driven by pointer spring dynamics and audio.
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
    zoom_params: vec4<f32>,  // x=Magnification, y=ChromaticDispersion, z=LensRadius, w=Iridescence
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
            targetPos = vec2<f32>(0.5 + 0.22 * cos(time * 0.75), 0.5 + 0.2 * sin(time * 0.9));
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
    let mag = mix(-0.4, 1.4, u.zoom_params.x) * (1.0 + bass * 0.3);
    let aberration = mix(0.006, 0.055, u.zoom_params.y) * (1.0 + treble * 0.4);
    let radius = mix(0.16, 0.65, u.zoom_params.z);
    let filmThicknessBase = mix(200.0, 780.0, u.zoom_params.z);
    let iridStrength = mix(0.3, 1.6, u.zoom_params.w);
    let blurEdges = mix(0.015, 0.08, u.zoom_params.w);
    let filmIOR = 1.45;
    
    let dVec = (uv - smoothMouse) * aspectVec;
    let dist = length(dVec);
    let holdEffect = smoothstep(0.4, 0.0, dist) * select(0.3, 1.0, isMouseDown);
    
    // Capped click ripple fronts
    var rippleDistortion = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rAge = time - r.z;
        if (r.z > 0.0 && rAge > 0.0 && rAge < 2.5) {
            let toRip = (uv - r.xy) * aspectVec;
            let rDist = length(toRip);
            let env = smoothstep(2.5, 0.0, rAge);
            let wave = sin(rDist * 36.0 - rAge * 11.0) * exp(-rDist * 6.5) * env;
            rippleDistortion = rippleDistortion + wave * 0.35;
        }
    }
    rippleDistortion = rippleDistortion + sin(dist * 30.0 - time * 8.0) * exp(-dist * 7.0) * clickImpulse * 0.5;
    
    var finalUV_R = uv;
    var finalUV_G = uv;
    var finalUV_B = uv;
    
    let lensMask = 1.0 - smoothstep(radius, radius + blurEdges, dist);
    
    // Spherical / aspherical lens magnification & radial dispersion
    if (dist < radius + blurEdges) {
        let ndist = clamp(dist / max(radius, 0.001), 0.0, 1.0);
        let lensCurve = 1.0 - (1.0 - ndist * ndist) * mag;
        let abbStrength = aberration * ndist + rippleDistortion * 0.01;
        
        let factorR = lensCurve - abbStrength;
        let factorG = lensCurve;
        let factorB = lensCurve + abbStrength;
        
        let delta = uv - smoothMouse;
        finalUV_R = clamp(smoothMouse + delta * factorR, vec2<f32>(0.0), vec2<f32>(1.0));
        finalUV_G = clamp(smoothMouse + delta * factorG, vec2<f32>(0.0), vec2<f32>(1.0));
        finalUV_B = clamp(smoothMouse + delta * factorB, vec2<f32>(0.0), vec2<f32>(1.0));
    }
    
    let colR = textureSampleLevel(readTexture, u_sampler, finalUV_R, 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, finalUV_G, 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, finalUV_B, 0.0).b;
    var color = vec3<f32>(colR, colG, colB);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV_G, 0.0).r;
    let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
    
    // Thin-film iridescence overlay inside lens area
    let toCenter = uv - vec2<f32>(0.5);
    let dlen = length(toCenter);
    let cosTheta = sqrt(max(1.0 - dlen * dlen * 0.5, 0.02));
    let noiseVal = hash12(uv * 12.0 + time * 0.1) * 0.6 + hash12(uv * 26.0 - time * 0.15) * 0.4;
    var thickness = filmThicknessBase * (0.65 + depth * 0.55 + noiseVal * 0.35 + holdEffect * 0.3 + bass * 0.2);
    thickness = thickness + rippleDistortion * 150.0;
    
    let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * iridStrength;
    let fresnel = pow(1.0 - cosTheta, 2.5);
    let ndist = clamp(dist / max(radius, 0.001), 0.0, 1.0);
    
    let lensColor = mix(color, iridescent, fresnel * 0.65 * (1.0 - ndist * 0.8) * lensMask);
    color = mix(color, lensColor, lensMask);
    
    // Glass bevel rim highlight
    let rimMask = smoothstep(radius - 0.025, radius, dist) * (1.0 - smoothstep(radius, radius + blurEdges, dist));
    let rimColor = mix(vec3<f32>(1.0), vec3<f32>(0.5, 0.8, 1.0), treble);
    color = color + rimColor * rimMask * 0.45 * (1.0 + treble);
    
    // Exact temporal feedback from dataTextureC
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    color = mix(color, prev, 0.1 + mids * 0.06);
    
    let tonemapped = acesToneMap(color * (1.0 + treble * 0.1));
    let alpha = clamp(luma * 0.5 + lensMask * 0.3 + rimMask * 0.25 + holdEffect * 0.15 + clickImpulse * 0.15, 0.2, 0.98);
    let outputRGBA = vec4<f32>(tonemapped, alpha);
    
    textureStore(writeTexture, pixel, outputRGBA);
    textureStore(dataTextureA, pixel, outputRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
