// ═══════════════════════════════════════════════════════════════════
//  ethereal-swirl-coupled
//  Category: advanced-hybrid
//  Features: fluid-coupling, fractal-swirl, temporal, mouse-driven, audio-reactive
//  Complexity: Very High
//  Chunks From: ethereal-swirl.wgsl, mouse-fluid-coupling.wgsl
//  Created: 2026-04-18
//  By: Agent CB-19 — Lighting & Energy Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Ethereal swirling clouds coupled with viscous fluid dynamics.
//  Mouse drags fluid that advects the fractal swirl field, creating
//  vortex streets and silky color-absorption trails in the dreamscape.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash2 (from ethereal-swirl.wgsl) ═══
fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(123.456, 789.012));
    p2 = p2 + dot(p2, p2 + 45.678);
    return fract(p2.x * p2.y);
}

// ═══ CHUNK: fbm (from ethereal-swirl.wgsl) ═══
fn fbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 2.0;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        value = value + amp * (hash2(p * freq) - 0.5);
        freq = freq * 2.1;
        amp = amp * 0.5;
    }
    return value;
}

// ═══ CHUNK: hsv2rgb (from ethereal-swirl.wgsl) ═══
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

fn sampleVelocity(tex: texture_2d<f32>, smp: sampler, uv: vec2<f32>) -> vec2<f32> {
    return textureSampleLevel(tex, smp, uv, 0.0).xy;
}

fn sampleDensity(tex: texture_2d<f32>, smp: sampler, uv: vec2<f32>) -> f32 {
    return textureSampleLevel(tex, smp, uv, 0.0).a;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;

    // Parameters
    let cloudScale = u.zoom_params.x * 7.0 + 1.0;
    let flowSpeed = u.zoom_params.y * 0.4;
    let colorSpeed = u.zoom_params.z * 0.2;
    let persistence = clamp(u.zoom_params.w * 0.95, 0.0, 0.95);
    let viscosity = mix(0.92, 0.99, u.zoom_params.x);
    let mouseRadius = mix(0.03, 0.15, u.zoom_params.y);
    let colorShift = u.zoom_params.z;
    let vortexStrength = u.zoom_params.w * 2.0;

    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luminance = dot(srcColor, vec3<f32>(0.2126, 0.7152, 0.0722));

    // ═══ Fluid coupling (from mouse-fluid-coupling) ═══
    let mousePos = u.zoom_config.yz;
    let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
    let mouseVel = (mousePos - prevMouse) * 60.0;
    let mouseSpeed = length(mouseVel);

    if (gid.x == 0u && gid.y == 0u) {
        textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
    }

    let px = vec2<f32>(1.0) / res;
    let prevVel = sampleVelocity(dataTextureC, u_sampler, uv);
    let prevDens = sampleDensity(dataTextureC, u_sampler, uv);

    let backUV = uv - prevVel * px * 2.0;
    let advectedVel = sampleVelocity(dataTextureC, u_sampler, backUV);
    let advectedDens = sampleDensity(dataTextureC, u_sampler, backUV);

    var vel = advectedVel * viscosity;
    var dens = advectedDens * viscosity;

    let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(toMouse);
    let influence = smoothstep(mouseRadius, 0.0, dist);
    vel = vel + mouseVel * influence * 0.5;

    let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
    vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;

    // Click ripples
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 2.0) {
            let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let rDist = length(rToMouse);
            let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
            let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
            vel = vel + outward * rInfluence * 0.3;
            dens = dens + rInfluence * 0.5;
        }
    }

    let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
    vel = vel * edgeDamp;
    vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
    dens = clamp(dens, 0.0, 2.0);

    // ═══ Ethereal swirl (from ethereal-swirl) ═══
    let baseFlow = vec2<f32>(
        fbm(uv * cloudScale * 0.3 + vec2<f32>(time * flowSpeed * 0.1, 0.0)),
        fbm(uv * cloudScale * 0.3 + vec2<f32>(0.0, time * flowSpeed * 0.15))
    );
    let turb = vec2<f32>(
        fbm(uv * cloudScale * 1.2 + baseFlow * 2.5 + vec2<f32>(time * flowSpeed * 0.2, 0.0)),
        fbm(uv * cloudScale * 1.2 + baseFlow * 2.5 + vec2<f32>(0.0, time * flowSpeed * 0.25))
    );
    let turbulenceAmt = 0.15;
    let flowVec = baseFlow * 0.2 + turb * turbulenceAmt;
    let depthWarp = depthVal * 0.05;
    let distortedUV = uv + flowVec + depthWarp * flowVec + vel * 0.5;

    let cloudBase = fbm(distortedUV * cloudScale);
    let cloudDetail = fbm(distortedUV * cloudScale * 3.0 + vec2<f32>(time * 0.1, time * 0.07));
    let cloudRaw = mix(cloudBase, cloudDetail, 0.5);
    let cloudDensity = smoothstep(0.2, 0.7, abs(cloudRaw) * 3.0);

    let baseHue = fract(distortedUV.x + distortedUV.y * 0.3 + time * colorSpeed);
    let hue = fract(baseHue + cloudDensity * 0.2);
    let sat = mix(0.6, 1.0, luminance);
    let val = mix(0.4, 1.0, luminance);
    let cloudColor = hsv2rgb(hue, sat, val);

    let blendStr = 0.5;
    let blendFactor = cloudDensity * smoothstep(0.1, 0.5, luminance) * blendStr;
    var blendedColor = mix(srcColor, cloudColor, blendFactor);

    // Fluid color absorption
    let blurAmount = dens * colorShift * 0.02;
    let blurUV = uv + vel * blurAmount * 5.0;
    let fluidColor = textureSampleLevel(readTexture, u_sampler, blurUV, 0.0).rgb;
    let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * colorShift);
    blendedColor = mix(blendedColor, fluidColor * fluidTint, dens * 0.3);

    // Feedback
    let prevFrame = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let finalColor = mix(blendedColor, prevFrame, persistence);

    // Store fluid state
    let vorticity = vel.x - vel.y;
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(vel, vorticity, dens));

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
