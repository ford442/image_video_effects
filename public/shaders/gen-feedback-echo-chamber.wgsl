// ═══════════════════════════════════════════════════════════════════════════════
//  Gen Feedback Echo Chamber v3 — Interactivist Upgrade
//  Category: feedback/temporal
//  Features: gravity-well, shockwave, bass-envelope, luma-spawn, temporal-echo
// ═══════════════════════════════════════════════════════════════════════════════

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

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = wellPos - pos;
    let dist2 = dot(d, d) + 0.01;
    return normalize(d) * strength / dist2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // ─── AUDIO ENVELOPE ───
    let bassRaw = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let prevEnv = extraBuffer[0];
    let bass = bass_env(prevEnv, bassRaw, 0.8, 0.15);

    // Parameters
    let accumulationRate = u.zoom_params.x;
    let echoScale = u.zoom_params.y * 0.05;
    let intensity = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    // ─── MOUSE GRAVITY WELL ───
    let gWell = gravityWell(uv, mouse, 0.02 + mouseDown * 0.08);
    let warpedUV = uv + gWell * echoScale * 2.0;

    // ─── VIDEO LUMA SPAWN ───
    let video = textureLoad(readTexture, coord, 0);
    let luma = dot(video.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let spawnMask = smoothstep(0.6, 0.9, luma) * (0.3 + treble * 0.7);

    // ─── CLICK SHOCKWAVE ───
    let clickDist = length(uv - mouse);
    let shockwave = mouseDown * exp(-clickDist * clickDist * 400.0) * sin(clickDist * 40.0 - time * 8.0);

    // Current frame
    let current = textureLoad(readTexture, coord, 0);

    // Previous accumulated frame
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Generative pattern
    let patternUV = warpedUV * 10.0;
    let pattern = hash(floor(patternUV) + time * 0.1 * (1.0 + mids * 0.5));

    // Echo displacement with mids-driven morphing
    let echoUV = warpedUV + vec2<f32>(
        sin(time * 0.5 * (1.0 + mids * 0.3) + warpedUV.y * 5.0) * echoScale * (1.0 + bass * 0.3),
        cos(time * 0.3 * (1.0 + mids * 0.3) + warpedUV.x * 5.0) * echoScale * (1.0 + bass * 0.2)
    );

    // Sample echo
    let echo = textureSampleLevel(dataTextureC, u_sampler, fract(echoUV), 0.0);

    // Generative color
    let genColor = vec3<f32>(
        0.5 + 0.5 * sin(time + warpedUV.x * 5.0 + pattern + colorShift * 6.283),
        0.5 + 0.5 * sin(time * 0.8 * (1.0 + mids * 0.2) + warpedUV.y * 5.0 + pattern + 2.0 + colorShift * 3.142),
        0.5 + 0.5 * sin(time * 0.6 * (1.0 + mids * 0.2) + (warpedUV.x + warpedUV.y) * 3.0 + pattern + 4.0)
    );

    // Blend with video and spawn mask
    let blended = mix(echo.rgb, genColor * intensity, 0.3 + spawnMask * 0.4);
    let withVideo = mix(blended, current.rgb, 0.15 + shockwave * 0.3);
    let finalColor = mix(withVideo, video.rgb, spawnMask * 0.25);

    // Add shockwave color burst
    let burstCol = vec3<f32>(1.0, 0.7, 0.3) * shockwave * (1.0 + bass * 2.0);
    let finalColor2 = finalColor + burstCol;

    // Treble sparkle
    let sparkle = hash(uv * 400.0 + time * 7.0) * treble * 1.5;
    let finalColor3 = finalColor2 + vec3<f32>(sparkle);

    // ─── TEMPORAL ACCUMULATION ───
    let brightness = dot(finalColor3, vec3<f32>(0.299, 0.587, 0.114));
    let trailFade = 0.92 - accumulationRate * 0.08;
    let newAlpha = clamp(brightness * intensity + spawnMask * 0.5 + abs(shockwave), 0.05, 1.0);
    let accAlpha = prev.a * trailFade + newAlpha * (1.0 - trailFade);
    let accColor = mix(prev.rgb, finalColor3, 0.08 + accumulationRate * 0.05);

    // ─── CHROMATIC ABERRATION ───
    let caStr = 0.003 * (1.0 + bass) + 0.001;
    let chromaticRGB = vec3<f32>(accColor.r + caStr, accColor.g, accColor.b - caStr * 0.5);
    let finalRGB = acesToneMap(chromaticRGB * (1.1 + bass * 0.3));

    // Alpha encodes trail age + interaction intensity
    let alpha = clamp(accAlpha * (0.8 + spawnMask * 0.4) + abs(shockwave), 0.0, 1.0);
    let output = vec4<f32>(finalRGB, alpha);

    textureStore(dataTextureA, coord, output);
    textureStore(writeTexture, global_id.xy, output);

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Persist envelope globally (only thread 0,0 writes)
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[0] = bass;
    }
}
