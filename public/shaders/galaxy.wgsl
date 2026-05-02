// ═══════════════════════════════════════════════════════════════════
//  Galaxy Simulation v2 - Audio-reactive spiral galaxy
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven,
//            procedural, animated
//  Upgraded: 2026-05-02 (Tier-1 integration pass)
//  CRITICAL FIX: replaced legacy u.config.yzw audio with plasmaBuffer
//  Creative additions: bass-driven breathing arms, diffraction-spike stars,
//                      reverse-flow during silence
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

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    let q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453);
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;

    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ═══ AUDIO from plasmaBuffer (replaces u.config.yzw) ═══
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioOverall = (bass + mids + treble) / 3.0;
    let silence = smoothstep(0.08, 0.0, audioOverall);

    // Domain-specific params
    let opacityP = u.zoom_params.x;        // Opacity
    let armCountP = u.zoom_params.y;       // Arm Count
    let rotationP = u.zoom_params.z;       // Rotation Speed
    let armSpread = u.zoom_params.w;       // Arm Spread

    let opacity = mix(0.5, 1.0, opacityP);
    let arms = mix(2.0, 6.0, armCountP);
    let rotation = mix(0.5, 3.0, rotationP);
    let spread = mix(0.1, 0.5, armSpread);

    // Mouse-driven center offset (parallax)
    let aspect = resolution.x / max(resolution.y, 1.0);
    let mouseUV = u.zoom_config.yz - vec2<f32>(0.5);
    let centerOffset = mouseUV * 0.4;
    var screenP = (uv - 0.5 - centerOffset * 0.5) * 2.0;
    screenP.x = screenP.x * aspect;

    let radius = length(screenP);
    let angle = atan2(screenP.y, screenP.x);

    // Bass drives spiral rotation; silence reverses time
    let timeFlow = mix(time, -time, silence);
    let bassRot = rotation * timeFlow * 0.1 * (1.0 + bass * 1.2);
    // Mids twist arms (more arm-relative shear)
    let armTwist = radius * (2.0 + mids * 1.5);
    let spiralAngle = angle + bassRot - armTwist;
    let armModulation = cos(spiralAngle * arms);

    // ─── Creative: bass-driven breathing arms ───
    let breath = 1.0 + sin(timeFlow * 0.7) * 0.05 + bass * 0.18;
    let breathRadius = radius / max(breath, 0.001);

    let coreDensity = exp(-breathRadius * 3.0);
    let armDensity = smoothstep(1.0 - spread, 1.0, armModulation) * exp(-breathRadius * 1.5);
    let density = (coreDensity * 0.6 + armDensity * 0.4) * 1.25;

    // Stars
    let starHash = hash3(vec3<f32>(floor(screenP * 50.0), time * 0.01));
    let starThresh = 0.997;
    let isStar = step(starThresh, starHash.x);
    let starBright = isStar * starHash.y;

    // ─── Creative: diffraction-spike stars (4-point cross) ───
    let starCell = floor(screenP * 50.0);
    let starOffset = (fract(screenP * 50.0) - 0.5) / 50.0;
    let spikeLen = (0.002 + starHash.y * 0.012) * (1.0 + bass * 0.3);
    let spikeH = spikeLen / max(abs(starOffset.y) + 0.0005, 0.0005) * smoothstep(spikeLen, 0.0, abs(starOffset.x));
    let spikeV = spikeLen / max(abs(starOffset.x) + 0.0005, 0.0005) * smoothstep(spikeLen, 0.0, abs(starOffset.y));
    let spike = (spikeH + spikeV) * 0.0008 * isStar * starHash.y;
    // Star color temperature: blue (young/hot) → red (old/cool) by hash.z
    let starTempColor = mix(vec3<f32>(0.6, 0.7, 1.0), vec3<f32>(1.0, 0.7, 0.5), starHash.z);

    // Galaxy palette
    let coreColor = vec3<f32>(0.3, 0.5, 1.0);
    let armColor = vec3<f32>(1.0, 0.8, 0.4);
    let baseColor = mix(coreColor, armColor, smoothstep(0.0, 0.5, breathRadius));

    var generatedColor = baseColor * density;
    generatedColor = generatedColor + starTempColor * starBright;
    generatedColor = generatedColor + starTempColor * spike;

    // Treble drives twinkle frequency
    let twinkleFreq = 3.0 + treble * 18.0;
    let twinkle = sin(time * twinkleFreq + breathRadius * 10.0) * 0.1 + 0.9;
    generatedColor = generatedColor * twinkle;

    // Central pulsing eye (singularity)
    let eye = exp(-radius * 60.0) * (1.0 + bass * 2.0);
    generatedColor = generatedColor + vec3<f32>(1.0, 0.95, 0.8) * eye * 0.6;

    // Vignette
    let vignette = 1.0 - radius * 0.5;
    generatedColor = generatedColor * vignette;

    // Tone map
    generatedColor = acesToneMapping(generatedColor);

    let luma = dot(generatedColor, vec3<f32>(0.299, 0.587, 0.114));
    let presence = smoothstep(0.05, 0.2, luma);
    let alpha = presence;

    let finalColor = mix(inputColor.rgb, generatedColor, alpha * opacity);
    let finalAlpha = max(inputColor.a, alpha * opacity);

    let generatedDepth = 1.0 - radius * 0.5;
    let finalDepth = mix(inputDepth, generatedDepth, alpha * opacity);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));

    // Star density field for downstream multi-pass glow
    textureStore(dataTextureA, coord, vec4<f32>(density, armDensity, starBright, alpha));
}
