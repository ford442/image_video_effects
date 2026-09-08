// ═══════════════════════════════════════════════════════════════════
//  divine-light-gpt52
//  Category: lighting-effects
//  Features: mouse-driven, volumetric, atmospheric, audio-reactive, upgraded-rgba
//  Ideas: Cauchy crepuscular ray dispersion, rose-window stained-glass projection, Airy disk diffraction halo
//  A packing: display RGBA (RGB=ACES tone-mapped beam radiance, A=volumetric transmission)
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Intensity, y=Decay, z=Density, w=Threshold
  ripples: array<vec4<f32>, 50>,
};

const PHI = 1.61803398874989484820;

fn hash21(p: vec2<f32>) -> vec2<f32> {
    let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
    return fract(vec2<f32>(n, n * PHI)) - 0.5;
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uu = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i).x, hash21(i + vec2<f32>(1.0, 0.0)).x, uu.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)).x, hash21(i + vec2<f32>(1.0, 1.0)).x, uu.x), uu.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var a = 0.5;
    var s = 0.0;
    var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        s = s + a * vnoise(q);
        q = q * 2.02;
        a = a * 0.5;
    }
    return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
    let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2)),
                       fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8)));
    return fbm(p + 4.0 * r);
}

fn voronoiF2minusF1(p: vec2<f32>) -> f32 {
    var F1 = 1e9;
    var F2 = 1e9;
    let ip = floor(p);
    for (var i = -1; i <= 1; i = i + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            let n = ip + vec2<f32>(f32(i), f32(j));
            let d = length(p - n - hash21(n));
            let isCloser = f32(d < F1);
            let isSecond = f32(d < F2) * (1.0 - isCloser);
            F2 = mix(F2, F1, isCloser);
            F2 = mix(F2, d, isSecond);
            F1 = mix(F1, d, isCloser);
        }
    }
    return F2 - F1;
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.001;
    let nx = warpedFBM(p + vec2<f32>(0.0, eps), t) - warpedFBM(p - vec2<f32>(0.0, eps), t);
    let ny = warpedFBM(p + vec2<f32>(eps, 0.0), t) - warpedFBM(p - vec2<f32>(eps, 0.0), t);
    return vec2<f32>(nx, -ny) / max(2.0 * eps, 1e-6);
}

fn hgPhase(cosTheta: f32, g: f32) -> f32 {
    let gg = g * g;
    return (1.0 - gg) / max(pow(1.0 + gg - 2.0 * g * cosTheta, 1.5), 1e-6);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 1.0);
    
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Single-writer spring-damper cursor for the divine light source in extraBuffer[133..138]
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var sprungCenter = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var centerVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        sprungCenter = select(vec2<f32>(0.5), rawMouse, rawMouse.x >= 0.0);
        centerVel = vec2<f32>(0.0);
    }
    let dt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let omega = 7.0;
    centerVel += ((rawMouse - sprungCenter) * (omega * omega) - centerVel * (2.0 * omega)) * dt;
    sprungCenter += centerVel * dt;

    if (global_id.x == 0u && global_id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = sprungCenter.x;
        extraBuffer[134] = sprungCenter.y;
        extraBuffer[135] = centerVel.x;
        extraBuffer[136] = centerVel.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }

    var center = sprungCenter;
    if (center.x < 0.0) { center = vec2<f32>(0.5, 0.5); }
    
    let intensity = u.zoom_params.x * 2.2;
    let decay = 0.88 + u.zoom_params.y * 0.11;
    let density = mix(0.6, 1.4, u.zoom_params.z);
    let threshold = u.zoom_params.w;
    let audioBoost = 1.0 + bass * 0.35;
    
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var dir = (center - uv) * vec2<f32>(aspect, 1.0);
    let dirLen = length(dir);
    let steps = 48;
    let delta = dir / max(f32(steps), 1.0) * density;
    var accum = vec3<f32>(0.0);
    var weight = 1.0;
    var current = uv;

    // IDEA 2: Cathedral rose-window stained-glass chromatic projection pattern
    let rayAngle = atan2(dir.y, dir.x);
    let roseRosePetals = cos(rayAngle * 8.0 + time * 0.2);
    let roseGothicRings = sin(dirLen * 25.0 - time * 0.5);
    let stainedGlassMask = 0.5 + 0.5 * (roseRosePetals * roseGothicRings);
    let stainedGlassTint = 0.5 + 0.5 * cos(rayAngle * 4.0 + vec3<f32>(0.0, 2.094, 4.188));
    
    for (var i = 0; i < steps; i = i + 1) {
        let fi = f32(i);

        // IDEA 1: Cauchy crepuscular ray dispersion
        // Differential radial sampling offsets for R, G, B creating rainbow chromatic fringes
        let dispersionStep = (fi / f32(steps)) * 0.008 * (1.0 + treble * 0.8);
        let sampleR = textureSampleLevel(readTexture, u_sampler, current + delta * dispersionStep, 0.0).r;
        let sampleG = textureSampleLevel(readTexture, u_sampler, current, 0.0).g;
        let sampleB = textureSampleLevel(readTexture, u_sampler, current - delta * dispersionStep, 0.0).b;
        let sample = vec3<f32>(sampleR, sampleG, sampleB);

        let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
        let contrib = select(0.0, 1.0, luma > threshold);
        let stepDir = current - uv;
        let cosTheta = dot(dir, stepDir) / max(dirLen * length(stepDir), 1e-6);
        let phase = hgPhase(cosTheta, 0.3);

        let rayContribution = sample * weight * intensity * audioBoost * contrib * phase;
        accum += rayContribution * mix(vec3<f32>(1.0), stainedGlassTint, stainedGlassMask * 0.4);

        // Atmospheric dust motes
        let dust = warpedFBM(current * resolution * 0.015 + vec2<f32>(time * 0.4, -time * 0.25), time);
        let cell = voronoiF2minusF1(current * 8.0 + time * 0.1);
        accum += vec3<f32>(dust * 0.015 + cell * 0.008) * weight * intensity * audioBoost;

        let flow = curl2D(current * 3.0 + fi * 0.05, time);
        current = current + delta + flow * delta * 0.3;
        weight = weight * decay;
    }
    
    accum = accum * (1.0 / max(f32(steps), 1.0)) * 0.9;
    accum = accum * vec3<f32>(1.1, 1.05, 0.95);

    let dist = length((uv - center) * vec2<f32>(aspect, 1.0));

    // IDEA 3: Airy disk multi-ring diffraction halo around the light source
    let airyCoord = dist * 80.0;
    let airyRings = select(1.0, pow(sin(airyCoord) / max(airyCoord, 0.001), 2.0), airyCoord > 0.1);
    let airySpectrum = 0.5 + 0.5 * cos(dist * 60.0 - time * 2.0 + vec3<f32>(0.0, 2.094, 4.188));
    let airyHalo = airyRings * exp(-dist * 8.0) * airySpectrum * (0.8 + mids * 0.6);

    let halo = smoothstep(0.5, 0.0, dist) * intensity * 0.35 * audioBoost;
    var finalRGB = original.rgb + accum + vec3<f32>(halo * 1.1, halo, halo * 0.8) + airyHalo * 0.5;

    // Temporal beam persistence via exact textureLoad from dataTextureC
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    finalRGB = mix(finalRGB, prev, 0.05);

    let effectLuma = dot(accum, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(original.a + effectLuma * 0.5 + halo * 0.3, 0.0, 1.0);
    let toneMappedRGB = acesFilm(max(finalRGB, vec3<f32>(0.0)));
    
    textureStore(writeTexture, coord, vec4<f32>(toneMappedRGB, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(toneMappedRGB, alpha));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
