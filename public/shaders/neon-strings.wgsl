// ═══════════════════════════════════════════════════════════════════
//  Neon Strings — Blackbody Heated Wire
//  Category: lighting-effects
//  Features: pluckable-strings, mouse-velocity, harmonics, audio-reactive, blackbody, upgraded-rgba
//  Complexity: High
//  Created: Phase B
//  Upgraded: 2026-05-23
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=StringCount, y=Tension, z=Intensity, w=CoolRate
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979;
const TAU: f32 = 6.28318530717959;
const PHI: f32 = 1.61803398874989;

fn blackbody(T: f32) -> vec3<f32> {
    let t = max(T, 800.0);
    let isLow = t <= 6600.0;
    let r = select(clamp(pow(t / 6600.0, -0.1332), 0.0, 1.0), 1.0, isLow);
    let gLow = clamp((log(t / 6600.0) * 0.39 + 0.0559) * 1.2, 0.0, 1.0);
    let gHigh = clamp(pow(t / 6600.0, -0.0755), 0.0, 1.0);
    let g = select(gHigh, gLow, isLow);
    let bLow = select(0.0, clamp((log(t / 10000.0) + 0.586) * 0.49, 0.0, 1.0), t > 2000.0);
    let b = select(1.0, bLow, isLow);
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let stringCount = u.zoom_params.x * 20.0 + 5.0;
    let tension     = clamp(u.zoom_params.y, 0.05, 1.0);
    let intensity   = u.zoom_params.z * 4.0;
    let coolRate    = mix(0.5, 5.0, u.zoom_params.w);

    let mouse      = u.zoom_config.yz;
    let mouseDown  = u.zoom_config.w;
    let mouseStr   = floor(mouse.y * stringCount);
    let strIdx     = floor(uv.y * stringCount);
    let sameStr    = step(abs(strIdx - mouseStr), 0.5);

    let fundFreq = 6.0 * sqrt(tension);

    let x = uv.x;
    let phaseOff = strIdx * PHI;
    let h1 = sin(PI * x) * cos(time * fundFreq * PI * 2.0 + phaseOff);
    let h2 = sin(2.0 * PI * x) * cos(time * fundFreq * 2.0 * PI * 2.0 + phaseOff);
    let h3 = sin(3.0 * PI * x) * cos(time * fundFreq * 3.0 * PI * 2.0 + phaseOff);
    let amp = h1 + 0.5 * h2 + 0.25 * h3;

    let pluckX = mouse.x;
    let dx = abs(uv.x - pluckX);
    let pluckEnv = exp(-dx * 8.0 / max(tension, 0.05)) * sameStr * (mouseDown * 0.7 + 0.3);
    let packetDirection = select(-1.0, 1.0, fract(strIdx * PHI) > 0.5);
    let packetPhase = fract((x - pluckX) * packetDirection - time * (1.2 + tension * 2.8) + 0.5);
    let packet = exp(-pow((packetPhase - 0.5) / 0.11, 2.0)) * sameStr * (0.25 + mouseDown * 0.75);
    let pluckOsc = sin((time * fundFreq * 1.5 + dx * 20.0) * PI * 2.0) * pluckEnv;

    var clickImpulse = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.2) {
            let rippleString = floor(ripple.y * stringCount);
            let onString = step(abs(strIdx - rippleString), 0.5);
            let front = abs(abs(x - ripple.x) - age * (0.38 + tension * 0.45));
            clickImpulse += onString * (1.0 - smoothstep(0.0, 0.035, front)) * (1.0 - age / 2.2);
        }
    }

    let bassVibrato = bass * 0.04 * sin(time * PI * 2.0 * 7.0 + strIdx * 1.3);

    let totalAmp = amp * 0.035 + pluckOsc + packet * sin(packetPhase * TAU) * 0.22 + clickImpulse * 0.18 + bassVibrato;

    let T_ambient = 1200.0;
    let T_max     = 16000.0;
    let T = T_ambient + (T_max - T_ambient) * clamp(totalAmp * totalAmp * 800.0, 0.0, 1.0);

    let coolEnvelope = sin(PI * x) * sin(PI * x);
    let T_cooled = T_ambient + (T - T_ambient) * pow(coolEnvelope, 1.0 / max(coolRate, 0.1));
    let T_clamped = clamp(T_cooled, 800.0, 18000.0);

    let stringY     = fract(uv.y * stringCount);
    let widthNorm   = 0.0005 + 0.002 * (1.0 - tension);
    let coreDist    = abs(stringY - 0.5 + totalAmp * 0.8);
    let coreGlow    = exp(-coreDist * coreDist / (widthNorm * widthNorm));
    let haloWidth   = 0.014 + widthNorm * 8.0;
    let haloGlow    = exp(-coreDist * coreDist / (haloWidth * haloWidth));

    let SB_factor = pow(T_clamped / 6500.0, 4.0);
    let brightness = clamp(SB_factor * 0.15, 0.0, 1.0);

    let bbColor = blackbody(T_clamped);
    let emission = bbColor * (coreGlow * intensity + haloGlow * brightness * 0.4 * intensity);

    let shimmer = treble * 0.15 * sin(time * 80.0 + strIdx * 7.0) * coreGlow;
    let finalEmission = emission + blackbody(min(T_clamped * 1.5, 18000.0)) * shimmer;

    // Pull an exact history texel against packet travel for harmonic afterimages.
    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
    let streakPixels = i32(round(packetDirection * (3.0 + tension * 8.0)));
    let historyCoord = clamp(coord - vec2<i32>(streakPixels, 0), vec2<i32>(0), maxCoord);
    let history = textureLoad(dataTextureC, historyCoord, 0);
    let afterimage = clamp(history.rgb, vec3<f32>(0.0), vec3<f32>(4.0)) * (0.28 + packet * 0.32 + clickImpulse * 0.18);

    let bg    = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let blend = clamp(coreGlow + haloGlow * brightness * 0.2, 0.0, 1.0);
    let color = finalEmission + afterimage + bg * (1.0 - blend) * 0.3;

    let alpha = clamp(coreGlow * 2.0 + haloGlow * brightness * 0.5 + blend * 0.3 + mids * 0.15, 0.0, 1.0);

    let finalColor = vec4<f32>(color, alpha);

    let dep = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(dep, 0.0, 0.0, 0.0));
}
