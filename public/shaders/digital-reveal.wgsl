// ═══════════════════════════════════════════════════════════════════
//  Digital Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-digital-rain, depth-reveal, chromatic-drops, upgraded-rgba
//  Complexity: High
//  Chunks From: digital-reveal, bass_env, hash22
//  Created: 2024-01-01
//  Upgraded: 2026-05-31
//  Upgraded: 2026-07-31 (swarm b19)
//    - Critically-damped spring reveal brush (extraBuffer[133..136])
//    - Click splash reveals (ripples -> decaying mask blobs)
//    - Depth-gated rain glyph brightness (near content glows through)
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthReveal = mix(0.3, 1.0, depth);

    // Slider wiring (saved-preset contract — ids/defaults unchanged):
    //   x = Rain Density — rain column count + white-drop odds (bass/mids boosted)
    //   y = Reveal Size  — spring brush radius
    //   z = Trail Fade   — mask persistence per frame
    //   w = Rain Speed   — glyph fall rate (treble boosted)
    let density = u.zoom_params.x * bass_env(bass, mids);
    let revealSize = u.zoom_params.y;
    let trailFade = u.zoom_params.z;
    let rainSpeed = u.zoom_params.w * (1.0 + treble * 0.5);

    let prevVal = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    let mouse = u.zoom_config.yz;   // raw cursor = spring target only

    // ── Spring-damper reveal brush ──────────────────────────────────
    // The raw mouse is only the TARGET; a critically-damped spring chases
    // it, so the brush paints with inertia and the feedback trail records
    // smooth swooping strokes instead of snapped jumps.
    // Persistent state lives in the extraBuffer[133..255] shader window
    // ([0..4] engine-reserved, [5..132] engine FFT bins):
    //   [133] = spring pos.x   [134] = spring pos.y
    //   [135] = spring vel.x   [136] = spring vel.y
    let mouseValid = mouse.x >= 0.0;
    let validF = select(0.0, 1.0, mouseValid);
    var springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    // First-touch snap: teleport the spring to the cursor so the brush
    // never glides in from the (0,0) corner on the very first stroke.
    let snapF = step(length(springPos), 0.0001) * step(length(springVel), 0.0001) * validF;
    springPos = mix(springPos, mouse, snapF);
    // Parked behaviour: invalid mouse aims the spring at its own position.
    let springGoal = mix(springPos, mouse, validF);
    let dt = 0.016;                        // fixed integration step
    let stiffness = 60.0;
    let damping = 2.0 * sqrt(stiffness);   // critical damping: glide, no overshoot
    let force = (springGoal - springPos) * stiffness - springVel * damping;
    springVel = springVel + force * dt;
    springPos = springPos + springVel * dt;
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;

    let aspect = resolution.x / resolution.y;
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let brushCorrected = vec2<f32>(springPos.x * aspect, springPos.y);
    let dist = distance(uvCorrected, brushCorrected);

    let brushRadius = revealSize * 0.3 + 0.05;
    let brush = validF * smoothstep(brushRadius, brushRadius * 0.5, dist);

    let fadeFactor = 0.8 + trailFade * 0.19;
    var newVal = max(prevVal * fadeFactor, brush) * depthReveal;

    // ── Click splash reveals ────────────────────────────────────────
    // Each live ripple stamps a decaying reveal blob (~0.15 radius, ~2s
    // fade) at its click point, so single clicks splash-reveal content
    // that then fades with trailFade through the feedback loop.
    let rippleCount = min(u32(u.config.y), 50u);   // config.y = ripple COUNT
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];                     // xy = click pos, z = click time
        let age = time - rp.z;
        let liveF = step(0.0, age) * step(age, 2.0);        // ~2s lifetime
        let rpDelta = (rp.xy - uv) * vec2<f32>(aspect, 1.0);
        let rpDist = length(rpDelta);
        let blob = 1.0 - smoothstep(0.0, 0.15, rpDist);     // ~0.15 radius
        let rippleBlob = blob * liveF * (1.0 - age * 0.5);  // linear ~2s fade
        newVal = max(newVal, rippleBlob);
    }

    // Mask feedback contract: dataTextureA stores (newVal,0,0,1) and
    // dataTextureC.r is read back next frame as prevVal — it is the reveal
    // mask, NOT display color; never tonemap it.
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newVal, 0.0, 0.0, 1.0));

    let gridSize = vec2<f32>(20.0, 20.0 * aspect) * (1.0 + density * 2.0);
    let cellUV = fract(uv * gridSize);
    let cellID = floor(uv * gridSize);

    let colSpeed = hash22(vec2<f32>(cellID.x, 0.0)).y * (rainSpeed * 5.0 + 1.0);
    let verticalPos = cellID.y + time * colSpeed;
    let charID = floor(verticalPos);
    let dropVal = fract(verticalPos);
    let charBright = smoothstep(0.0, 0.2, dropVal) * smoothstep(1.0, 0.8, dropVal);
    let flicker = step(0.1, hash22(vec2<f32>(cellID.x, charID)).x);

    // Chromatic drops: bass shifts green, treble shifts cyan/white highlights
    var rainColor = vec3<f32>(0.0, 1.0, 0.2) * charBright * flicker;
    rainColor.g = rainColor.g + bass * 0.3 * charBright;
    if (hash22(vec2<f32>(cellID.x, charID)).y > 0.98 - density * 0.1) {
        rainColor = vec3<f32>(0.8 + treble * 0.2, 1.0, 0.8 + treble * 0.2);
    }

    // Depth-gated rain: in unrevealed regions the glyphs subtly track the
    // depth map (far -> 0.6x dim, near -> 1.2x bright), so near content
    // glows through the rain and earns the depth-aware tag.
    let depthGlow = mix(1.0, mix(0.6, 1.2, depth), 0.4);
    rainColor = rainColor * depthGlow;

    let imageColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let finalColor = mix(rainColor, imageColor, clamp(newVal, 0.0, 1.0));
    let alpha = clamp(newVal + charBright * 0.2 + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
