// ═══════════════════════════════════════════════════════════════════
//  Luma Refraction
//  Category: image
//  Features: wave-propagation, mouse-interactive, audio-reactive, upgraded-rgba,
//            chromatic-refraction, click-raindrops, audio-rain, audio-wave-amplitude
//  Complexity: Medium
//  Upgraded: 2026-05-31
//  Batch 22 (2026-07-31):
//    - FIX: removed the mask-as-color feedback. The old "temporal wave memory"
//      mixed dataTextureC.rgb (wave STATE: h in [-10,10], v, 0) into the display
//      color, injecting simulation garbage into the image. The wave state now
//      never enters the display path; refraction offsets visualize it honestly.
//    - Click raindrops: live ripples drop one-shot gaussian wave impulses.
//    - Audio rain: strong bass transients sprinkle random rain impulses.
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

// ───────────────────────────────────────────────────────────────────
//  hash21 — deterministic 2D→1D hash for branchless rain sprinkling
// ───────────────────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // ── Slider params (saved-preset contract: x/y/z/w mapping is fixed) ──
    let waveSpeed = u.zoom_params.x;
    let mouseForce = u.zoom_params.y;
    let damping = u.zoom_params.z;
    let refractionAmt = u.zoom_params.w;

    // ── Audio bands ──
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ═══════════════════════════════════════════════════════════════
    //  Wave state read (engine-forced A/C contract — VERBATIM)
    //  dataTextureC holds the previous frame's state: r = h, g = v
    // ═══════════════════════════════════════════════════════════════
    let state = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    var h = state.r;
    var v = state.g;

    let texel = 1.0 / resolution;
    let n = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
    let s = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    let e = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let w_val = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;

    // ═══════════════════════════════════════════════════════════════
    //  Wave-equation core (SACRED — VERBATIM)
    //  Laplacian of the height field drives velocity; propagation speed
    //  is luma-driven: bright regions transmit waves faster.
    // ═══════════════════════════════════════════════════════════════
    let laplacian = (n + s + e + w_val) / 4.0 - h;

    let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

    // Audio-driven wave amplitude
    let localSpeed = waveSpeed * (0.2 + 1.0 * luma) * (1.0 + bass * 0.3);

    v = v + laplacian * localSpeed;
    v = v * damping;

    // ═══════════════════════════════════════════════════════════════
    //  Impulse sources (all inject into v BEFORE h integration)
    // ═══════════════════════════════════════════════════════════════

    // ── Mouse stir: radius widens when Mouse Force is high ──
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    let stirRadius = 0.05 + mouseForce * 0.05;
    if (mouseDown > 0.5 && dist < stirRadius) {
        v = v + (1.0 - dist / stirRadius) * mouseForce * 0.5;
    }

    // ── Click raindrops: each live ripple drops a one-shot gaussian ──
    // impulse at its click point (same form as the mouse stir, radius
    // ~0.05), so clicks splash the pond without holding the button.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 0.12) {
            let rd = distance(uv * vec2<f32>(aspect, 1.0), ripple.xy * vec2<f32>(aspect, 1.0));
            let bump = exp(-rd * rd / (0.05 * 0.05));
            v = v + bump * 0.8;
        }
    }

    // ── Audio rain: strong bass transients sprinkle random rain ──
    // impulses across the whole surface (branchless step form), so
    // beats make the pond drizzle.
    let rainSeed = hash21(uv * 91.0 + floor(time * 3.0));
    let rainGate = step(0.998 - bass * 0.002, rainSeed);
    v = v + rainGate * 0.3;

    // ── Ambient drizzle: a faint constant sprinkle keeps the pond ──
    // alive even in silence.
    let drizzleSeed = hash21(uv * 37.0 + floor(time * 7.0) + 17.17);
    let drizzleGate = step(0.9995, drizzleSeed);
    v = v + drizzleGate * 0.05;

    // ═══════════════════════════════════════════════════════════════
    //  Integration + state write (SACRED — VERBATIM)
    // ═══════════════════════════════════════════════════════════════
    h = h + v;
    h = clamp(h, -10.0, 10.0);

    textureStore(dataTextureA, global_id.xy, vec4<f32>(h, v, 0.0, 1.0));

    // ═══════════════════════════════════════════════════════════════
    //  Chromatic refraction (structure preserved — VERBATIM taps)
    //  The wave gradient acts as a surface normal; R/G/B refract at
    //  slightly different offsets. The wave is visualized honestly
    //  through refraction alone — state never enters the display path.
    // ═══════════════════════════════════════════════════════════════
    let gradX = (e - w_val) * 0.5;
    let gradY = (s - n) * 0.5;

    let normal = vec2<f32>(gradX, gradY);

    // Chromatic refraction: R/G/B see different index of refraction
    let rOffset = normal * refractionAmt * 0.5 * (1.0 + treble * 0.2);
    let gOffset = normal * refractionAmt * 0.5;
    let bOffset = normal * refractionAmt * 0.5 * (1.0 - bass * 0.2);

    let rUV = clamp(uv - rOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv - gOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - bOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    var finalColor = vec3<f32>(0.0);
    finalColor.r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    finalColor.g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    finalColor.b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // ── Dispersion glint: derived ONLY from the refracted image taps ──
    // (never from wave state). Where R/B channels separate, the crest
    // catches a faint spectral sparkle; mids make it shimmer with audio.
    let chroma = abs(finalColor.r - finalColor.b);
    let glint = chroma * (0.08 + mids * 0.08);
    finalColor = finalColor + vec3<f32>(glint * 0.9, glint * 0.6, glint);
    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // ── Semantic alpha: wave crests stay slightly more opaque ──
    let alpha = clamp(0.8 + abs(h) * 0.05, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

    // ── Depth passthrough ──
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
