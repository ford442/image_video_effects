// ═══════════════════════════════════════════════════════════════════
//  Pixelation Drift
//  Category: retro-glitch
//  Features: audio-reactive, temporal-persistence, chromatic-pixel-separation,
//            depth-aware, organic-motion, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-31
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

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, vec3<f32>(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let aspectVec = vec2<f32>(aspect, 1.0);

    // The previously dead mouse feature now controls a sprung mosaic focus.
    let rawMouse = u.zoom_config.yz;
    var mosaicCenter = vec2<f32>(extraBuffer[133u], extraBuffer[134u]);
    var mosaicVelocity = vec2<f32>(extraBuffer[135u], extraBuffer[136u]);
    let mosaicInitialized = extraBuffer[137u] >= 0.5;
    if (!mosaicInitialized) {
        mosaicCenter = rawMouse;
        mosaicVelocity = vec2<f32>(0.0);
    }
    let springDt = select(0.0, clamp(time - extraBuffer[138u], 0.0005, 0.05), mosaicInitialized);
    let springOmega = 9.0;
    let mosaicAccel = springOmega * springOmega * (rawMouse - mosaicCenter)
        - 2.0 * springOmega * mosaicVelocity;
    mosaicVelocity += mosaicAccel * springDt;
    mosaicCenter = clamp(mosaicCenter + mosaicVelocity * springDt, vec2<f32>(-0.2), vec2<f32>(1.2));
    if (gid.x == 0u && gid.y == 0u) {
        extraBuffer[133u] = mosaicCenter.x;
        extraBuffer[134u] = mosaicCenter.y;
        extraBuffer[135u] = mosaicVelocity.x;
        extraBuffer[136u] = mosaicVelocity.y;
        extraBuffer[137u] = 1.0;
        extraBuffer[138u] = time;
    }

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Audio-reactive pixel size
    let basePixelSize = max(u.zoom_params.x, 0.01) * 100.0 * (1.0 + bass * 0.3);
    let driftSpeed = u.zoom_params.y * (1.0 + mids * 0.2);
    let colorBleed = u.zoom_params.z;
    let depthInfluence = u.zoom_params.w;

    let depthFactor = mix(1.0, 1.0 - depth * 0.7, depthInfluence);
    let mouseDeltaAspect = (uv - mosaicCenter) * aspectVec;
    let mouseDistance = length(mouseDeltaAspect);
    let focusLens = exp(-mouseDistance * mouseDistance * 18.0);

    // Clicks send a chunky pixel-size ring through the grid for ~1.6 seconds.
    var clickPixelPulse = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.6) {
            let clickDistance = length((uv - ripple.xy) * aspectVec);
            clickPixelPulse += exp(-abs(clickDistance - age * 0.34) * 26.0) * exp(-age * 1.6);
        }
    }

    let heldFocus = select(1.0, 0.75, u.zoom_config.w > 0.5);
    let mousePixelScale = mix(1.0, 0.45 * heldFocus, focusLens);
    let pixelSize = max(basePixelSize * depthFactor * mousePixelScale * (1.0 + clickPixelPulse * 0.8), 1.0);

    let regionCoord = vec2<u32>(floor(clamp(uv * 8.0, vec2<f32>(0.0), vec2<f32>(7.0))));
    let region = (regionCoord.x + regionCoord.y) % 8u;
    let regionVoice = plasmaBuffer[(region % 8u) + 1u].x;

    // Organic drift with audio
    let driftScale = 5.0;
    let driftOffset = vec2<f32>(
        noise(uv * driftScale + vec2<f32>(time * driftSpeed * 0.2, 0.0)),
        noise(uv * driftScale + vec2<f32>(0.0, time * driftSpeed * 0.2))
    ) * 2.0 - 1.0;

    let safeMouseDir = mouseDeltaAspect / max(mouseDistance, 0.001);
    let mouseSwirl = vec2<f32>(-safeMouseDir.y / aspect, safeMouseDir.x)
        * focusLens * u.zoom_config.w * 0.012;

    let driftedUV = uv + driftOffset * 0.02 * driftSpeed * (1.0 + regionVoice * 0.3) + mouseSwirl;
    let pixelatedUV = clamp(
        floor(driftedUV * resolution / pixelSize) * pixelSize / resolution,
        vec2<f32>(0.0), vec2<f32>(1.0)
    );

    // Chromatic pixel separation: RGB sample at different pixel offsets
    let chromaShift = pixelSize / resolution.x * treble * 0.5;
    let rUV = clamp(pixelatedUV + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = pixelatedUV;
    let bUV = clamp(pixelatedUV - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    var color = vec3<f32>(r, g, b);
    var baseAlpha = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).a;

    // Color bleeding with audio
    if (colorBleed > 0.01) {
        let bleedOffset = vec2<f32>(
            sin(time * 0.5 + uv.y * 10.0 + bass * 3.14),
            cos(time * 0.5 + uv.x * 10.0 + mids * 3.14)
        ) * pixelSize / resolution * colorBleed * 2.0;
        let bleedUV = clamp(pixelatedUV + bleedOffset, vec2<f32>(0.0), vec2<f32>(1.0));
        let bleedColor = textureSampleLevel(readTexture, u_sampler, bleedUV, 0.0);
        color = mix(color, bleedColor.rgb, colorBleed * 0.3);
        baseAlpha = mix(baseAlpha, bleedColor.a, colorBleed * 0.3);
    }

    // Edge glow
    let pixelCenter = (floor(driftedUV * resolution / pixelSize) + 0.5) * pixelSize / resolution;
    let distToCenter = length((driftedUV - pixelCenter) * resolution);
    let edgeGlow = smoothstep(pixelSize * 0.4, pixelSize * 0.5, distToCenter);
    color = mix(color, color * 1.2, edgeGlow * 0.1);

    // Temporal persistence for smoother transitions
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let persistence = clamp(0.85 + bass * 0.05 + regionVoice * 0.03, 0.0, 0.95);
    let blended = mix(vec4<f32>(color, baseAlpha), prev, persistence);
    textureStore(dataTextureA, gid.xy, blended);

    // Semantic alpha based on pixel edge and audio
    let alpha = clamp(baseAlpha * (1.0 - edgeGlow * 0.2) + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(blended.rgb, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
