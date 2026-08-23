// ═══════════════════════════════════════════════════════════════════
//  Anamorphic Caustic Flare
//  Category: visual-effects
//  Features: anamorphic, caustic, lens-flare, refraction, audio-stretch, mouse-tilt, cinematic, semantic-alpha
//  Complexity: High
//  Chunks From: _hash_library.wgsl (hash21)
//  Created: 2026-06-01
//  Upgraded: 2026-08-02 (sprung lens tilt + breathing flare anchor, click flare bursts, per-band FFT caustic shimmer)
//  By: Grok (new image/video effect — premium anamorphic lens with living water caustics refracting the source)
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
  config: vec4<f32>,       // [time, rippleCount, resW, resH]
  zoom_config: vec4<f32>,  // [time, mouseX, mouseY, mouseDown]
  zoom_params: vec4<f32>,  // x=Flare, y=Caustic, z=Refraction, w=Stretch
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash21 (from _hash_library.wgsl) ═══
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn caustic(p: vec2<f32>, t: f32, freq: f32) -> f32 {
    let q = p * freq + vec2<f32>(t * 0.6, t * -0.4);
    let c1 = sin(q.x * 1.7 + sin(q.y * 2.3)) * 0.5 + 0.5;
    let c2 = sin(q.y * 2.1 + sin(q.x * 1.4 + t * 0.8)) * 0.5 + 0.5;
    return pow(c1 * c2, 1.6);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sliders — each drives a real constant of THIS shader's algorithm:
    //   flare      → anamorphic flare + streak strength (bass-stretched)
    //   caustic    → caustic highlight intensity (treble-animated)
    //   refraction → caustic refraction offset magnitude
    //   stretch    → caustic field frequency / bass stretch factor
    let flareStrength = u.zoom_params.x * (0.7 + bass * 0.9);
    let causticStrength = u.zoom_params.y * (0.8 + treble * 0.6);
    let refraction = u.zoom_params.z * 0.035;
    let stretch = u.zoom_params.w * (1.0 + bass * 0.8);

    let mouse = u.zoom_config.yz;

    // ── Spring-dampered lens tilt (extraBuffer[133..136] = pos.xy, vel.xy) ──
    // Critically-damped spring: the virtual lens glides behind the cursor
    // instead of snapping to it. Every thread derives the same current-frame
    // value; thread (0,0) alone persists it. [137] = lastTime,
    // [138] = initialized flag, so a valid top-left pointer is unambiguous.
    var sprungMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var sprungVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    let lastTime = extraBuffer[137];
    let springInitialized = extraBuffer[138] > 0.5;
    if (!springInitialized) {
        sprungMouse = mouse;
        sprungVel = vec2<f32>(0.0, 0.0);
    }
    let dt = select(0.0, clamp(time - lastTime, 0.0, 0.1), springInitialized);
    let omega = 8.0; // spring natural frequency (rad/s)
    let accel = omega * omega * (mouse - sprungMouse) - 2.0 * omega * sprungVel;
    sprungVel += accel * dt;
    sprungMouse += sprungVel * dt;
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = sprungMouse.x;
        extraBuffer[134] = sprungMouse.y;
        extraBuffer[135] = sprungVel.x;
        extraBuffer[136] = sprungVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
    }

    // Lens tilt rides the SPRUNG x — never the raw cursor.
    let mouseTilt = (sprungMouse.x - 0.5) * 0.6;

    // Sample input (will be refracted by caustics)
    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Breathing flare anchor: mostly centered, but the lens leans toward the
    // sprung cursor y so the flare line breathes with mouse movement.
    let flareY = mix(0.5, sprungMouse.y, 0.35);

    // Anamorphic horizontal flare (classic blue + orange)
    let centerDist = abs(uv.y - flareY) * 1.8;
    let anamorph = smoothstep(0.08, 0.0, centerDist) * flareStrength;
    let flareCol = mix(vec3<f32>(0.2, 0.55, 1.0), vec3<f32>(1.0, 0.6, 0.15), uv.x * 0.6 + 0.2);
    var flare = flareCol * pow(anamorph, 1.3) * (1.0 + bass * 0.5);

    // Add horizontal light streaks (anamorphic signature)
    let streak = smoothstep(0.012, 0.0, abs(uv.y - flareY)) * (0.6 + bass * 0.4);
    flare += vec3<f32>(0.85, 0.9, 1.0) * streak * flareStrength * 0.7;

    // ── Click flare bursts ──
    // Each live ripple fires a decaying anamorphic flash centered on its
    // click's y-line (~1.2s life), plus a brief caustic energy spike near
    // the click point so the water light kicks where the user touched.
    var burstFlash = 0.0;
    var burstEnergy = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 1.2) { continue; }
        burstFlash = max(burstFlash, exp(-age * 2.0) * smoothstep(0.02, 0.0, abs(uv.y - ripple.y)));
        let clickDist = length((uv - ripple.xy) * vec2<f32>(res.x / res.y, 1.0));
        burstEnergy = max(burstEnergy, exp(-age * 3.0) * smoothstep(0.25, 0.0, clickDist));
    }
    // Second streak term — the click flash shares the streak color/weighting.
    flare += vec3<f32>(0.85, 0.9, 1.0) * burstFlash * flareStrength;

    // Living water caustics that refract the image
    let c = caustic(uv + mouseTilt * 0.1, time * 0.7 + mids * 0.3, 9.0 + stretch * 4.0);
    var causticMask = pow(c, 2.2) * causticStrength;

    // Per-band FFT caustic shimmer: 8 vertical bands each modulate their
    // causticMask by their own FFT bin, so the water light dances across
    // the spectrum instead of only following global mids/treble.
    let band = min(u32(uv.x * 8.0), 7u);
    causticMask = causticMask * (1.0 + plasmaBuffer[(band % 8u) + 1u].x * 0.3);

    // Click burst caustic spike — a brief local swell of water light.
    causticMask = min(causticMask + burstEnergy * causticStrength * 0.6, 3.0);

    // Refraction offset (stronger where caustic is bright)
    let refractUV = uv + vec2<f32>(causticMask * refraction * (sprungMouse.x - 0.5), causticMask * refraction * 0.6);
    let refracted = textureSampleLevel(readTexture, u_sampler, clamp(refractUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // Blend refracted image with caustic highlights
    let causticLight = vec3<f32>(0.6, 0.85, 1.0) * causticMask * 1.8;
    var col = mix(input.rgb, refracted.rgb, clamp(0.35 + causticMask * 0.5, 0.0, 1.0));
    col += causticLight * (0.4 + mids * 0.3);

    // Subtle filmic chromatic aberration on strong flares
    if (flareStrength > 0.4) {
        let caOff = flareStrength * 0.0018;
        let rUv = clamp(uv + vec2<f32>(caOff, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
        let bUv = clamp(uv - vec2<f32>(caOff * 0.7, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
        let r = textureSampleLevel(readTexture, u_sampler, rUv, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, bUv, 0.0).b;
        col.r = mix(col.r, r, 0.25);
        col.b = mix(col.b, b, 0.25);
    }

    // Final mix with anamorphic flare
    col = col * (1.0 - flareStrength * 0.25) + flare * 0.85;

    // Gentle contrast curve
    col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(0.88));

    // Semantic alpha — strong on bright caustic and flare regions (great for layering)
    let energy = causticMask * 0.65 + anamorph * 0.9 + streak * 0.4;
    let semantic_alpha = clamp(0.68 + energy * 0.42, 0.5, 1.0);

    let peak = max(col.r, max(col.g, col.b));
    let displayScale = select(1.0, 3.0 / max(peak, 1e-4), peak > 3.0);
    let displayColor = col * displayScale;
    
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let aspect = u.config.z / max(u.config.w, 1.0);
    let screenUV = vec2<f32>(global_id.xy) / vec2<f32>(u.config.z, u.config.w);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((screenUV - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(screenUV - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let __finalRGB = displayColor + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, global_id.xy, vec4<f32>(__finalRGB, semantic_alpha));

    // Depth carries caustic energy for downstream effects
    let d = clamp(0.25 + causticMask * 0.55 + anamorph * 0.3, 0.0, 0.97);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));

    // Store caustic field for possible multi-pass use
    textureStore(dataTextureA, global_id.xy, vec4<f32>(c, causticMask, flareStrength, semantic_alpha));
}
