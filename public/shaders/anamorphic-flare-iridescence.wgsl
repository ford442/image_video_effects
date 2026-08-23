// ═══════════════════════════════════════════════════════════════════
//  Anamorphic Flare Iridescence
//  Category: advanced-hybrid
//  Features: lens-flare, thin-film-interference, spectral-render,
//            mouse-driven, audio-reactive, exact-feedback
//  Complexity: Very High
// ═══════════════════════════════════════════════════════════════════
//  Cinematic anamorphic lens flare combined with physical thin-film
//  interference. Flare streaks, hexagonal ghosts, starburst rays,
//  and halo rings carry angle-dependent iridescent soap-bubble
//  reflections modulated by audio dynamics.
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
    zoom_params: vec4<f32>,  // x=FlareIntensity, y=StreakLength, z=FilmThickness, w=FilmIOR
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

fn hexagonAperture(uv: vec2<f32>, size: f32) -> f32 {
    let r = length(uv);
    let angle = atan2(uv.y, uv.x);
    let sectorAngle = fract(angle / (PI / 3.0)) * (PI / 3.0) - PI / 6.0;
    let dist = r * cos(sectorAngle) / cos(PI / 6.0);
    return smoothstep(size + 0.015, size - 0.015, dist);
}

fn anamorphicStreak(uv: vec2<f32>, lightPos: vec2<f32>, streakLength: f32, width: f32, aspect: f32) -> f32 {
    let toLight = uv - lightPos;
    let distX = abs(toLight.x) * aspect;
    let distY = abs(toLight.y);
    let hStreak = exp(-distX / max(streakLength, 0.01)) * exp(-distY * 60.0 / width);
    let vStreak = exp(-distY / max(streakLength * 0.12, 0.01)) * exp(-distX * 80.0 / width);
    return hStreak * 0.92 + vStreak * 0.08;
}

fn ghostElement(uv: vec2<f32>, lightPos: vec2<f32>, offset: vec2<f32>, size: f32) -> f32 {
    let center = vec2<f32>(0.5);
    let ghostPos = center + (center - lightPos) * offset * 2.0 + offset * 0.5;
    let dist = length(uv - ghostPos);
    let hexUV = (uv - ghostPos) / max(size, 0.001);
    let hex = hexagonAperture(hexUV, 0.8);
    let falloff = exp(-dist * dist * 10.0 / max(size, 0.001));
    return hex * falloff;
}

fn centralGlow(uv: vec2<f32>, lightPos: vec2<f32>, size: f32, aspect: f32) -> f32 {
    let dVec = (uv - lightPos) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);
    let core = exp(-dist * 18.0 / max(size, 0.01));
    let corona = exp(-dist * 6.0 / max(size, 0.01)) * 0.35;
    return core + corona;
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
            targetPos = vec2<f32>(0.5 + 0.28 * cos(time * 0.5), 0.5 + 0.18 * sin(time * 0.65));
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
    let flareIntensity = mix(0.3, 3.2, u.zoom_params.x);
    let streakLength = mix(0.1, 1.2, u.zoom_params.y) * (1.0 + bass * 0.4);
    let filmThicknessBase = mix(200.0, 850.0, u.zoom_params.z);
    let filmIOR = mix(1.2, 2.4, u.zoom_params.w);
    
    let distLight = length((uv - smoothLight) * aspectVec);
    let holdEffect = smoothstep(0.4, 0.0, distLight) * select(0.3, 1.0, isMouseDown);
    
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Capped click ripple fronts
    var rippleDistortion = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rAge = time - r.z;
        if (r.z > 0.0 && rAge > 0.0 && rAge < 2.5) {
            let rDist = length((uv - r.xy) * aspectVec);
            let env = smoothstep(2.5, 0.0, rAge);
            let wave = sin(rDist * 35.0 - rAge * 11.0) * exp(-rDist * 6.0) * env;
            rippleDistortion = rippleDistortion + wave * 0.35;
        }
    }
    rippleDistortion = rippleDistortion + sin(distLight * 30.0 - time * 8.0) * exp(-distLight * 7.0) * clickImpulse * 0.5;
    
    // Viewing angle for iridescence
    let toCenter = uv - vec2<f32>(0.5);
    let distCenter = length(toCenter);
    let cosTheta = sqrt(max(1.0 - distCenter * distCenter * 0.5, 0.02));
    
    var flareAccum = vec3<f32>(0.0);
    
    // 1. Anamorphic horizontal streak with thin-film interference
    let streak = anamorphicStreak(uv, smoothLight, streakLength, 1.8 + bass * 0.5, aspect);
    let streakThickness = filmThicknessBase * (0.6 + streak * 250.0 + rippleDistortion * 0.2);
    let streakIrid = thinFilmColor(streakThickness, cosTheta, filmIOR);
    flareAccum = flareAccum + streak * streakIrid * flareIntensity * 1.4;
    
    // 2. Hexagonal ghost reflections
    let ghostCount = i32(u.zoom_params.y * 5.0 + 2.0);
    for (var i: i32 = 0; i < ghostCount; i = i + 1) {
        let fi = f32(i);
        let ghostOffset = vec2<f32>(
            sin(fi * 1.3 + time * 0.1) * 0.16 + fi * 0.09,
            cos(fi * 0.75) * 0.1 + fi * 0.06
        );
        let ghostSize = (0.09 - fi * 0.01) * (1.0 + mids * 0.2);
        let ghostIntensity = (0.45 - fi * 0.05) * flareIntensity;
        let ghost = ghostElement(uv, smoothLight, ghostOffset, ghostSize);
        let ghostThickness = filmThicknessBase * (0.75 + fi * 0.28 + rippleDistortion * 0.1);
        let ghostIrid = thinFilmColor(ghostThickness, cosTheta, filmIOR);
        flareAccum = flareAccum + ghost * ghostIntensity * ghostIrid;
    }
    
    // 3. Central glow with interference corona
    let glow = centralGlow(uv, smoothLight, 0.16 + bass * 0.06, aspect);
    let glowThickness = filmThicknessBase * (1.0 + glow * 180.0);
    let glowIrid = thinFilmColor(glowThickness, cosTheta, filmIOR);
    flareAccum = flareAccum + glow * glowIrid * flareIntensity * 0.9;
    
    // 4. Starburst with spectral diffraction
    let toLight = (uv - smoothLight) * aspectVec;
    let angle = atan2(toLight.y, toLight.x);
    let dist = length(toLight);
    let starburst = pow(abs(sin(angle * 6.0 + time * 0.2)), 24.0) * exp(-dist * 3.2) * (1.0 + treble * 0.5);
    let starThickness = filmThicknessBase * (0.4 + starburst * 350.0);
    let starIrid = thinFilmColor(starThickness, cosTheta, filmIOR);
    flareAccum = flareAccum + starburst * starIrid * flareIntensity * 0.45;
    
    // 5. Rainbow halo ring
    let haloDist = abs(dist - 0.26 * (1.0 + bass * 0.2));
    let haloIntensity = exp(-haloDist * 90.0) * 0.55;
    let rainbowPhase = angle * 3.0 + time * 0.3;
    let rainbow = vec3<f32>(
        (sin(rainbowPhase) + 1.0) * 0.5,
        (sin(rainbowPhase + TAU / 3.0) + 1.0) * 0.5,
        (sin(rainbowPhase + 2.0 * TAU / 3.0) + 1.0) * 0.5
    );
    flareAccum = flareAccum + rainbow * haloIntensity * flareIntensity * 0.3;
    
    // Exact temporal feedback from dataTextureC
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    var finalColor = baseColor + flareAccum;
    finalColor = mix(finalColor, prev, 0.08 + mids * 0.05);
    
    let tonemapped = acesToneMap(finalColor * (1.0 + treble * 0.1));
    let flareLum = dot(flareAccum, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(dot(baseColor, vec3<f32>(0.2126, 0.7152, 0.0722)) * 0.4 + flareLum * 0.6 + holdEffect * 0.2 + clickImpulse * 0.2, 0.15, 0.98);
    let outputRGBA = vec4<f32>(tonemapped, alpha);
    
    textureStore(writeTexture, pixel, outputRGBA);
    textureStore(dataTextureA, pixel, outputRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
