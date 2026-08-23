// ═══════════════════════════════════════════════════════════════════
//  Dynamic Lens Flares Prismatic
//  Category: advanced-hybrid
//  Features: lens-flares, prismatic-dispersion, spectral-rendering,
//            mouse-driven, audio-reactive, exact-feedback
//  Complexity: Very High
// ═══════════════════════════════════════════════════════════════════
//  Cinematic optical lens flares with physical prismatic dispersion.
//  Ghost elements refract through virtual glass lens surfaces using
//  Cauchy's equation, creating distinct chromatic splitting along
//  the optical axis with starburst diffraction and ring halos.
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
    zoom_params: vec4<f32>,  // x=Intensity, y=Threshold, z=Spread, w=GhostCount
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

fn refractThroughSurface(uv: vec2<f32>, center: vec2<f32>, ior: f32, curvature: f32) -> vec2<f32> {
    let toCenter = uv - center;
    let dist = length(toCenter);
    let lensStrength = curvature * 0.35;
    let offset = toCenter * (1.0 - 1.0 / max(ior, 0.01)) * lensStrength * (1.0 + dist * 1.5);
    return uv + offset;
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
            targetPos = vec2<f32>(0.5 + 0.25 * cos(time * 0.6), 0.5 + 0.2 * sin(time * 0.75));
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
    let aspect = res.x / res.y;
    let aspectVec = vec2<f32>(aspect, 1.0);
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    // Sliders
    let intensity = mix(0.2, 2.2, u.zoom_params.x);
    let threshold = mix(0.05, 0.85, u.zoom_params.y);
    let spread = mix(0.2, 1.8, u.zoom_params.z);
    let cauchyB = mix(0.015, 0.08, u.zoom_params.z);
    let maxGhosts = mix(3.0, 8.0, u.zoom_params.w);
    let spectralSat = mix(0.4, 1.4, u.zoom_params.w);
    
    let distLight = length((uv - smoothLight) * aspectVec);
    let holdEffect = smoothstep(0.4, 0.0, distLight) * select(0.3, 1.0, isMouseDown);
    
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
    rippleDistortion = rippleDistortion + sin(distLight * 32.0 - time * 8.0) * exp(-distLight * 7.5) * clickImpulse * 0.5;
    
    let center = vec2<f32>(0.5, 0.5);
    let axis = center - smoothLight;
    
    let lightColorFull = textureSampleLevel(readTexture, u_sampler, smoothLight, 0.0).rgb;
    let maxRGB = max(lightColorFull.r, max(lightColorFull.g, lightColorFull.b));
    var lightColor = vec3<f32>(0.1);
    if (maxRGB > threshold) {
        lightColor = lightColorFull * intensity;
    } else {
        lightColor = mix(vec3<f32>(0.1), lightColorFull, maxRGB / max(threshold, 0.01)) * intensity;
    }
    lightColor = lightColor * (1.0 + bass * 0.4);
    
    // Ghost elements with prismatic dispersion along the optical axis
    var flareAccum = vec3<f32>(0.0);
    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    
    for (var i = 0.0; i < 8.0; i = i + 1.0) {
        if (i >= maxGhosts) { break; }
        let scale = -0.9 + (i * 0.45);
        let offset = axis * (scale * spread);
        let ghostPos = center + offset + vec2<f32>(sin(i * 1.5 + time * 0.2) * 0.02, cos(i * 1.8 + time * 0.15) * 0.02);
        
        let uvAspect = (uv - vec2<f32>(0.5)) * aspectVec + vec2<f32>(0.5);
        let ghostAspect = (ghostPos - vec2<f32>(0.5)) * aspectVec + vec2<f32>(0.5);
        let d = length(uvAspect - ghostAspect);
        
        let size = (0.05 + 0.08 * sin(i * 123.4 + 1.0)) * (1.0 + mids * 0.25);
        let softness = 0.025;
        let weight = smoothstep(size + softness, size, d);
        
        // 4-band Cauchy prismatic dispersion per ghost
        var prismaticGhost = vec3<f32>(0.0);
        for (var j: i32 = 0; j < 4; j = j + 1) {
            let ior = cauchyIOR(WAVELENGTHS[j], 1.5, cauchyB + bass * 0.03);
            let refractedUV = refractThroughSurface(uv, ghostPos, ior, 0.45);
            let wrappedUV = clamp(refractedUV, vec2<f32>(0.0), vec2<f32>(1.0));
            let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);
            let absorption = exp(-0.4 * (4.0 - f32(j)) * 0.14);
            let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[j])) * absorption;
            prismaticGhost = prismaticGhost + wavelengthToRGB(WAVELENGTHS[j]) * bandIntensity * spectralSat;
        }
        
        let hueShift = i * 0.65 + time * 0.1;
        let r = cos(hueShift) * 0.5 + 0.5;
        let g = cos(hueShift + 2.094) * 0.5 + 0.5;
        let b = cos(hueShift + 4.188) * 0.5 + 0.5;
        let ghostColor = vec3<f32>(r, g, b) * lightColor;
        
        let dispersedColor = mix(ghostColor, prismaticGhost * lightColor, 0.45);
        flareAccum = flareAccum + dispersedColor * weight * 0.4;
    }
    
    // Halo ring
    let distToMouseAspect = length((uv - smoothLight) * aspectVec);
    let ringRadius = 0.28 * spread * (1.0 + bass * 0.2);
    let ringWidth = 0.025;
    let ring = smoothstep(ringRadius + ringWidth, ringRadius, distToMouseAspect) - smoothstep(ringRadius, ringRadius - ringWidth, distToMouseAspect);
    flareAccum = flareAccum + lightColor * ring * 0.25 * (1.0 + treble * 0.3);
    
    // Starburst rays
    let dirToMouse = normalize((uv - smoothLight) * aspectVec + vec2<f32>(0.0001));
    let angle = atan2(dirToMouse.y, dirToMouse.x);
    let ray = max(0.0, sin(angle * 12.0 + time * 0.3) * sin(angle * 6.0 - time * 0.2));
    let rayFalloff = 1.0 / (distToMouseAspect * 12.0 + 0.12);
    flareAccum = flareAccum + lightColor * ray * rayFalloff * 0.22 * (1.0 + treble * 0.5);
    
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    var finalColor = baseColor + flareAccum;
    
    // Exact temporal feedback from dataTextureC
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    finalColor = mix(finalColor, prev, 0.08 + mids * 0.05);
    
    let tonemapped = acesToneMap(finalColor * (1.0 + treble * 0.1));
    let flareLum = dot(flareAccum, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(dot(baseColor, vec3<f32>(0.2126, 0.7152, 0.0722)) * 0.4 + flareLum * 0.6 + holdEffect * 0.2 + clickImpulse * 0.2, 0.15, 0.98);
    let outputRGBA = vec4<f32>(tonemapped, alpha);
    
    textureStore(writeTexture, pixel, outputRGBA);
    textureStore(dataTextureA, pixel, outputRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
