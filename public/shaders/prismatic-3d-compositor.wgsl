// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

// ═══════════════════════════════════════════════════════════════
//  Prismatic 3D Compositor - PASS 2 of 2
//  Adds parallax shifting, volumetric glow, chromatic aberration
//  and final composite with depth-aware blending.
//
//  Inputs:
//    - readTexture: Pass 1 cloud color
//    - readDepthTexture: Pass 1 cloud depth
//
//  Upgrade notes (Batch 22):
//    - FIXED inverted mouse units: zoom_config.yz is already
//      normalized [0,1]; dividing by dims a second time pinned the
//      parallax driver to the corner pixel. Parallax now tracks
//      the cursor across the whole frame.
//    - 'cameraZ' was really mouseDown: renamed, and pressing now
//      deepens the parallax push instead of gating it to zero.
//    - Treble band (plasmaBuffer[0].z) was a dead read: now feeds
//      the glow intensity so all three audio bands are live.
//    - Click prism flares: live ripples add a decaying chromatic
//      spike at the click point (~1.2s fade).
//
//  Features: compositor, parallax, volumetric-glow, mouse-driven, audio-reactive, upgraded-rgba
//  Previous Pass: volumetric-rainbow-clouds.wgsl
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>
};

// Mapping notes:
// u.zoom_config.yz -> mouse X,Y (already normalized [0,1] by the engine)
// u.zoom_config.w  -> mouseDown (0/1), used as a parallax push, NOT cameraZ
// u.zoom_params.x..w -> comp_params: glowRadius, glowIntensity, parallaxAmount, aberration
// u.ripples[i] = (clickX, clickY, clickTime, unused), count in u.config.y

const PARALLAX_SCALE: f32 = 0.05;      // slider (0..4) -> max ~±0.2 UV shift
const FLARE_LIFETIME: f32 = 1.2;       // seconds a click flare stays visible
const FLARE_DECAY: f32 = 2.0;          // exp falloff rate of the flare envelope
const FLARE_RADIUS: f32 = 40.0;        // spatial falloff of the flare (UV^-2)
const FLARE_BOOST: f32 = 3.0;          // aberration multiplier at flare core
const TWO_PI: f32 = 6.2831853;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / max(dims.y, 1.0);

    // Priority-1 fix: mouse arrives normalized — do NOT divide by dims again.
    let mousePos = u.zoom_config.yz;
    // Honest label: this channel carries mouseDown, not a camera depth.
    let mouseDown = u.zoom_config.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sample Pass 1 results (assume readTexture contains Pass1 color and readDepthTexture contains Pass1 depth)
    let cloudColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // 1) Parallax shift — depth-weighted cursor offset, bass lifts the far
    //    layers, pressing the mouse deepens the push by up to +50%.
    var parallax = u.zoom_params.z * depth * (1.0 + bass * 0.4);
    parallax = parallax * (1.0 + mouseDown * 0.5);
    let parallaxOffset = (mousePos - vec2<f32>(0.5, 0.5)) * parallax * PARALLAX_SCALE;
    let parallaxUV = uv + parallaxOffset;
    let parallaxSample = textureSampleLevel(readTexture, u_sampler, clamp(parallaxUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    // Fade to the unshifted pixel where the shift leaves the frame so edges
    // do not smear clamped border streaks into the composite.
    let inBounds = step(vec2<f32>(0.0, 0.0), parallaxUV) * step(parallaxUV, vec2<f32>(1.0, 1.0));
    let parallaxMask = inBounds.x * inBounds.y;
    let parallaxColor = mix(cloudColor, parallaxSample, parallaxMask);

    // 2) Volumetric glow
    let glowRadius = u.zoom_params.x * 0.01;
    let glowIntensity = u.zoom_params.y;
    let glowThreshold = 0.2;

    var glow = vec3<f32>(0.0);
    var count = 0.0;
    for (var x: i32 = -2; x <= 2; x = x + 1) {
        for (var y: i32 = -2; y <= 2; y = y + 1) {
            let sampleUV = clamp(uv + vec2<f32>(f32(x), f32(y)) * glowRadius, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
            let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
            let brightness = length(sampleColor);
            let weight = exp(-sampleDepth) * max(brightness - glowThreshold, 0.0);
            glow = glow + sampleColor * weight;
            count = count + weight;
        }
    }
    glow = glow / max(count, 1.0);

    // Spectral tint: hue rotates with depth so the halo reads prismatic
    // rather than a flat white bloom.
    let prismTint = 0.5 + 0.5 * cos(TWO_PI * (depth + vec3<f32>(0.0, 0.33, 0.67)));
    glow = glow * mix(vec3<f32>(1.0, 1.0, 1.0), prismTint, 0.35);

    // 3) Chromatic aberration along depth + click prism flares.
    let aberrationBase = u.zoom_params.w * depth * (1.0 + mids * 0.5);

    // Each live ripple contributes a decaying chromatic spike centred on its
    // click point: envelope exp(-age * 2.0), gone after ~1.2s.
    var flare = 0.0;
    var flareDir = vec2<f32>(0.0, 0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age <= FLARE_LIFETIME) {
            let toPixel = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let dist2 = dot(toPixel, toPixel);
            let envelope = exp(-age * FLARE_DECAY);
            let localFalloff = exp(-dist2 * FLARE_RADIUS);
            let contribution = envelope * localFalloff;
            flare = flare + contribution;
            // Radial split direction pointing away from the click.
            flareDir = flareDir + toPixel * contribution;
        }
    }
    flare = min(flare, 1.5);
    let aberration = aberrationBase * (1.0 + flare * FLARE_BOOST) + flare * 0.02;

    // Aberration direction: mostly radial from frame centre (classic prism
    // fringing) blended with the click-flare radial when a flare is hot.
    let radialDir = normalize((uv - vec2<f32>(0.5, 0.5)) * vec2<f32>(aspect, 1.0) + vec2<f32>(1e-5, 0.0));
    var abDir = normalize(mix(vec2<f32>(1.0, 0.0), radialDir, 0.65));
    let flareDirLen = length(flareDir);
    if (flareDirLen > 1e-4) {
        abDir = normalize(mix(abDir, flareDir / flareDirLen, clamp(flare, 0.0, 1.0) * 0.6));
    }

    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + abDir * aberration, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - abDir * aberration, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let aberrantColor = vec3<f32>(r, g, b);

    // 4) Composite with video (video assumed bound to historyTex via renderer when desired) - here we just mix with original readTexture
    let videoColor = cloudColor;
    // blend params: videoBlend in extraBuffer[0], glowThreshold in extraBuffer[1], depthSharpness in extraBuffer[2]
    let videoBlend = 0.5;
    // Parallax layer rides on top: depth-separated ghost that bass pushes forward
    let layered = mix(aberrantColor, parallaxColor, clamp(depth * (0.4 + bass * 0.5), 0.0, 1.0));
    // Treble (previously a dead read) now brightens the glow so all three
    // audio bands drive the composite.
    let liveGlowIntensity = glowIntensity * (1.0 + treble * 0.3);
    let lit = layered + glow * liveGlowIntensity * (1.0 + bass * 0.6)
            + prismTint * flare * 0.25;
    let finalColor = mix(videoColor, lit, videoBlend);

    // 5) Temporal feedback — mids shorten the trail so busy passages stay crisp
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;
    let feedback = mix(finalColor, prev, 0.85 - mids * 0.25);

    // Alpha carries composite luminance so downstream passes can key on it
    let alpha = clamp(length(finalColor) * 0.7 + depth * 0.3, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(feedback, alpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
