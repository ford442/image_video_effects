// ═══════════════════════════════════════════════════════════════════
//  Holographic Failure Iridescence
//  Category: advanced-hybrid
//  Features: holographic, thin-film-interference, glitch, depth-aware,
//            audio-reactive, mouse-driven, exact-feedback
//  Complexity: High
// ═══════════════════════════════════════════════════════════════════
//  Simulated hologram projection failure merged with physical
//  thin-film optical iridescence. Glitching phase carriers, block
//  tearing, and laser flicker overlay soap-bubble interference
//  derived from depth, angle, and audio dynamics.
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
    zoom_params: vec4<f32>,  // x=Failure, y=Holographic, z=FilmIOR, w=Turbulence
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
            targetPos = vec2<f32>(0.5 + 0.2 * cos(time * 0.9), 0.5 + 0.2 * sin(time * 1.1));
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
    let failureAmount = clamp(u.zoom_params.x, 0.0, 1.0);
    let holographicIntensity = clamp(u.zoom_params.y, 0.0, 1.0);
    let filmIOR = mix(1.2, 2.4, u.zoom_params.z);
    let turbulence = clamp(u.zoom_params.w, 0.0, 1.0);
    
    let distMouse = length((uv - smoothMouse) * aspectVec);
    let holdEffect = smoothstep(0.4, 0.0, distMouse) * select(0.3, 1.0, isMouseDown);
    
    // Capped click ripple fronts
    var rippleDistortion = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rAge = time - r.z;
        if (r.z > 0.0 && rAge > 0.0 && rAge < 2.5) {
            let rDist = length((uv - r.xy) * aspectVec);
            let env = smoothstep(2.5, 0.0, rAge);
            let wave = sin(rDist * 35.0 - rAge * 11.0) * exp(-rDist * 6.5) * env;
            rippleDistortion = rippleDistortion + wave * 0.4;
        }
    }
    rippleDistortion = rippleDistortion + sin(distMouse * 30.0 - time * 8.0) * exp(-distMouse * 7.0) * clickImpulse * 0.5;
    
    // Failure glitch jitter & scanline desync
    let glitchBlock = hash12(floor(uv * vec2<f32>(18.0, 6.0) + vec2<f32>(time * 12.0, 0.0)));
    let isGlitchRow = step(0.92 - failureAmount * 0.35 - bass * 0.1, glitchBlock);
    let scanlineJitter = sin(uv.y * 180.0 + time * 25.0) * 0.003 * failureAmount;
    let blockJitter = (hash12(vec2<f32>(floor(uv.y * 24.0), floor(time * 15.0))) - 0.5) * 0.04 * failureAmount * isGlitchRow;
    
    let glitchedUV = clamp(uv + vec2<f32>(blockJitter + scanlineJitter + rippleDistortion * 0.02, rippleDistortion * 0.01), vec2<f32>(0.0), vec2<f32>(1.0));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, glitchedUV, 0.0).r;
    let sample = textureSampleLevel(readTexture, u_sampler, glitchedUV, 0.0).rgb;
    let luma = dot(sample, vec3<f32>(0.2126, 0.7152, 0.0722));
    
    // Laser flicker
    let flickerNoise = hash12(vec2<f32>(floor(time * 24.0), 0.0));
    let flicker = step(failureAmount * 0.35 + bass * 0.1, flickerNoise) * 0.3 + 0.7;
    
    // Iridescence computation
    let toCenter = uv - vec2<f32>(0.5);
    let distCenter = length(toCenter);
    let cosTheta = sqrt(max(1.0 - distCenter * distCenter * 0.5, 0.02));
    
    let filmThicknessBase = mix(220.0, 780.0, holographicIntensity);
    let noiseVal = hash12(uv * 12.0 + time * 0.1) * 0.5 + hash12(uv * 26.0 - time * 0.15) * 0.25;
    var thickness = filmThicknessBase * (0.6 + depth * 0.6 + noiseVal * turbulence + holdEffect * 0.4 + bass * 0.2);
    thickness = thickness + isGlitchRow * 250.0 * failureAmount;
    
    let iridescent = thinFilmColor(thickness, cosTheta, filmIOR);
    let fresnel = pow(1.0 - cosTheta, 2.5);
    
    // Holographic carrier wave
    let holoPhase = uv.x * 28.0 + uv.y * 14.0 + time * 2.0 + depth * 15.0;
    let holoCarrier = vec3<f32>(
        0.35 + 0.45 * sin(holoPhase),
        0.45 + 0.45 * sin(holoPhase + 2.094),
        0.65 + 0.35 * sin(holoPhase + 4.188)
    );
    
    // Failure artifacts (digital tears & chromatic breakdown)
    let tearNoise = hash12(floor(uv * vec2<f32>(40.0, 120.0)) + vec2<f32>(time * 18.0, time * 5.0));
    let tearMask = step(0.96 - failureAmount * 0.3, tearNoise);
    let tearColor = vec3<f32>(0.9, 0.3, 0.8) * (1.0 + treble);
    
    var finalColor = mix(sample * flicker, iridescent * (1.2 + bass * 0.3), fresnel * 0.65 * holographicIntensity);
    finalColor = mix(finalColor, holoCarrier * flicker * (luma + 0.3), holographicIntensity * 0.4);
    finalColor = mix(finalColor, tearColor, tearMask * failureAmount * 0.65);
    
    // Chromatic dispersion fringe around failures
    let caOffset = vec2<f32>(0.004 * failureAmount * (1.0 + treble), 0.0);
    let rSample = textureSampleLevel(readTexture, u_sampler, clamp(glitchedUV + caOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, clamp(glitchedUV - caOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    finalColor = mix(finalColor, vec3<f32>(rSample, finalColor.g, bSample), failureAmount * 0.4);
    
    // Exact temporal feedback from dataTextureC
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    finalColor = mix(finalColor, prev, 0.1 + mids * 0.08);
    
    let tonemapped = acesToneMap(finalColor * (1.0 + treble * 0.1));
    let alpha = clamp(luma * 0.5 + failureAmount * 0.35 + holographicIntensity * 0.2 + holdEffect * 0.15 + clickImpulse * 0.15, 0.2, 0.98);
    let outputRGBA = vec4<f32>(tonemapped, alpha);
    
    textureStore(writeTexture, pixel, outputRGBA);
    textureStore(dataTextureA, pixel, outputRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
