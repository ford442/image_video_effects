// ═══════════════════════════════════════════════════════════════════
//  Interactive Glitch Brush
//  Category: interactive-mouse
//  Features: mouse-driven, glitch, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
//  Swarm Upgrade: 2026-07-30 (Batch 17, Interactivist)
//    - Critically-damped spring brush (extraBuffer[133..136])
//    - Click glitch grenades (ripples -> decaying glitch zones)
//    - Per-channel treble-bin split shimmer (bins 5 vs 8)
//  NOTE: deliberately BRANCHLESS (select/step/smoothstep only).
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn random(st: vec2<f32>) -> f32 {
    return fract(sin(dot(st.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let trebleBinR = plasmaBuffer[5].x;   // shimmer driver for the red tear
    let trebleBinB = plasmaBuffer[8].x;   // shimmer driver for the blue tear

    // ── Sliders (zoom_params contract: ids/defaults unchanged) ──────
    let brushSize = max(u.zoom_params.x * 0.3 + 0.05, 0.001);   // Brush Size
    let intensity = clamp(u.zoom_params.y, 0.0, 1.0);           // Glitch Intensity
    let blockScale = max(u.zoom_params.z * 50.0 + 5.0, 0.001);  // Block Scale
    let colorSplit = clamp(u.zoom_params.w * 0.1, 0.0, 1.0);    // Color Split

    let audioIntensity = intensity * (1.0 + bass * 0.5 + mids * 0.25);

    // ── Spring-damper brush (critically damped) ─────────────────────
    // Persistent state: extraBuffer[133]=pos.x [134]=pos.y [135]=vel.x [136]=vel.y
    let mouseValid = mousePos.x >= 0.0;
    let validF = select(0.0, 1.0, mouseValid);
    var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    // First-touch snap: teleport the spring to the cursor so the brush
    // never glides in from the (0,0) corner on the very first stroke.
    let snapF = step(length(sPos), 0.0001) * step(length(sVel), 0.0001) * validF;
    sPos = mix(sPos, mousePos, snapF);
    // Parked behaviour: invalid mouse aims the spring at its own position.
    let springGoal = mix(sPos, mousePos, validF);
    let dt = 0.016;                       // fixed integration step
    let stiffness = 60.0;
    let damping = 2.0 * sqrt(stiffness);  // critical damping: glide, no overshoot
    let force = (springGoal - sPos) * stiffness - sVel * damping;
    sVel = sVel + force * dt;
    sPos = sPos + sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;

    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // ── Brush falloff (soft-edged, aspect-corrected, spring-driven) ─
    let diff = sPos - uv;
    let diffAspect = vec2<f32>(diff.x * aspect, diff.y);
    let dist = length(diffAspect);
    let brushMask = validF * (1.0 - smoothstep(brushSize * 0.65, brushSize, dist));

    // ── Click glitch grenades ───────────────────────────────────────
    // Each live ripple spawns a temporary glitch zone at its click point
    // (radius ~ brushSize) that decays over ~1s. Fully branchless.
    var grenade = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        let liveF = step(0.0, age) * step(age, 1.0);      // ~1s lifetime
        let rDelta = (rp.xy - uv) * vec2<f32>(aspect, 1.0);
        let rDist = length(rDelta);
        let zone = 1.0 - smoothstep(brushSize * 0.4, brushSize, rDist);
        let blast = zone * liveF * (1.0 - age);           // linear decay
        grenade = max(grenade, blast);
    }

    let activeMask = clamp(max(brushMask, grenade), 0.0, 1.0);

    // ── Block displacement (quantization VERBATIM) ──────────────────
    let blockUV = floor(uv * blockScale) / blockScale;
    let noise = random(blockUV + vec2<f32>(time * 0.1));
    let offsetX = select(0.0, (random(vec2<f32>(noise, time)) - 0.5) * audioIntensity * 0.2, noise > 0.5);
    // Grenades force block displacement even where the noise gate is shut.
    let grenadeOffsetX = (random(blockUV + vec2<f32>(time * 0.37)) - 0.5) * 0.25;
    let dispX = select(offsetX, grenadeOffsetX, grenade > 0.05);
    let offset = vec2<f32>(dispX * activeMask, 0.0);

    // ── Per-channel split shimmer ───────────────────────────────────
    // r/b tears are driven by DIFFERENT treble bins so the chromatic
    // split shimmers across the spectrum; the slider stays the base.
    let splitR = colorSplit * (0.5 + trebleBinR);
    let splitB = colorSplit * (0.5 + trebleBinB);

    let sampleUV_r = clamp(uv + offset - vec2<f32>(splitR, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleUV_g = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleUV_b = clamp(uv + offset + vec2<f32>(splitB, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, sampleUV_r, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV_g, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleUV_b, 0.0).b;

    // ── Inversion: base 5% chance, forced inside grenade zones ──────
    let invertBase = step(0.95, random(vec2<f32>(time, noise)));
    let invertNade = step(0.25, grenade) * step(0.5, random(blockUV + vec2<f32>(time * 0.73)));
    let invertCond = max(invertBase, invertNade) > 0.5;
    let glitchR = select(r, 1.0 - r, invertCond);
    let glitchG = select(g, 1.0 - g, invertCond);
    let glitchB = select(b, 1.0 - b, invertCond);

    let glitchLuma = 0.299 * glitchR + 0.587 * glitchG + 0.114 * glitchB;
    let glitchAlpha = clamp(glitchLuma + treble * 0.1, 0.1, 1.0);
    var glitchColor = vec4<f32>(glitchR, glitchG, glitchB, glitchAlpha);

    // Grenade flash: fresh blasts punch the brightness before decaying.
    glitchColor = vec4<f32>(glitchColor.rgb * (1.0 + grenade * 0.35), glitchColor.a);

    // Scanline modulo (VERBATIM)
    let scanlineCond = fract(uv.y * resolution.y * 0.5) < 0.5;
    glitchColor = select(glitchColor, glitchColor * 0.8, scanlineCond);

    color = mix(color, glitchColor, activeMask);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coords, color);
    textureStore(dataTextureA, global_id.xy, color);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
