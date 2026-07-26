// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Bloom v3
//  Category: generative
//  Features: audio-reactive, reaction-diffusion, gray-scott, chemotaxis,
//            quorum-sensing, volumetric-scatter, upgraded-rgba, aces-tone-map,
//            per-tendril-spectrum, spring-damper-nutrient
//  Complexity: Very High
//  Created: 2026-05-31
//  Upgraded: 2026-07-26 (batch 16)
//
//  Upgrade notes:
//   - Fixed double ACES tonemap (was applied twice, washing highlights).
//     Output path now uses a SINGLE acesToneMap call.
//   - HDR bloom term is hue-preserving-clamped to ~1.2 BEFORE the tonemap
//     so quorum waves bloom without clipping the palette.
//   - Each tendril phase-offsets its pulse from its own FFT bin
//     (plasmaBuffer[(i % 8) + 1].x) instead of following global bands.
//   - Mouse nutrient source is eased through a critically-damped spring
//     (extraBuffer[133..136], init flag [137]) so chemotaxis trails read
//     as pursuit rather than snapping to the cursor.
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
  config: vec4<f32>,       // x=Time, y=RippleCount (engine), z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=TendrilCount, y=PulseSpeed, z=DotDensity, w=GlowRadius
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Hue-preserving clamp: scales the HDR color so its brightest channel
// sits at or below `ceiling` while keeping channel ratios (hue) intact.
fn huePreserveClamp(c: vec3<f32>, ceiling: f32) -> vec3<f32> {
    let peak = max(c.r, max(c.g, c.b));
    let scale = min(1.0, ceiling / max(peak, 1e-4));
    return c * scale;
}

// Critically-damped spring step toward the nutrient aim point.
// State lives in extraBuffer[133..136] (pos.xy, vel.xy), init flag [137].
fn springStep(pos: vec2<f32>, vel: vec2<f32>, aim: vec2<f32>, omega: f32, dt: f32) -> vec4<f32> {
    let accel = omega * omega * (aim - pos) - 2.0 * omega * vel;
    let newVel = vel + accel * dt;
    let newPos = pos + newVel * dt;
    return vec4<f32>(newPos, newVel);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz;

    // ── Slider wiring (zoom_params) ─────────────────────────────────
    // x: Tendril Count  -> number of background tendril strands (3..8)
    // y: Pulse Speed    -> tendril sway + node pulse tempo (0.2..2.2)
    // z: Dot Density    -> fraction of glow-dot cells that ignite + size
    // w: Glow Radius    -> ambient/scatter/bloom falloff radius
    let tendrilCount = 3 + i32(u.zoom_params.x * 5.0);
    let pulseSpeed = 0.2 + u.zoom_params.y * 2.0;
    let dotDensity = u.zoom_params.z;
    let glowRadius = u.zoom_params.w;

    // ── Spring-damper nutrient source ───────────────────────────────
    // The chemotaxis aim glides toward the mouse through a critically
    // damped spring so the colony pursues the cursor with visible lag.
    var springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        // First contact: snap the spring onto the cursor, zero velocity.
        springPos = mouse;
        springVel = vec2<f32>(0.0, 0.0);
    }
    let springState = springStep(springPos, springVel, mouse, 6.0, 0.016);
    let nutrientAim = springState.xy;
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = springState.x;
        extraBuffer[134] = springState.y;
        extraBuffer[135] = springState.z;
        extraBuffer[136] = springState.w;
        extraBuffer[137] = 1.0;
    }

    let aspect = res.x / res.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);

    // ── Background bioluminescent tendrils ──────────────────────────
    var bgCol = vec3<f32>(0.0, 0.02, 0.05);
    var bgGlow = 0.0;

    for (var ti = 0; ti < tendrilCount; ti = ti + 1) {
        let tf = f32(ti);
        // Per-tendril spectrum: each strand listens to its own FFT bin
        // and phase-offsets its pulse, so tendrils dance independently.
        let band = plasmaBuffer[(ti % 8) + 1].x;
        let baseAngle = (tf / f32(tendrilCount) - 0.5) * 1.5 + 1.5708;
        let wave = sin(uv.x * 8.0 + tf * 2.1 + time * pulseSpeed + band * 3.0) * 0.15;
        let wave2 = cos(uv.x * 15.0 - tf * 1.7 + time * pulseSpeed * 1.3 + band * 5.0) * 0.08;

        var minTendrilDist = 1e9;
        for (var si = 0; si < 20; si = si + 1) {
            let sf = f32(si) / 20.0;
            let ty = -0.4 + sf * 0.9;
            let tx = (baseAngle - 1.5708) * 0.3 * sf + wave * sf + wave2 * sf * sf;
            let tpos = vec2<f32>(tx, ty);
            let td = length(p - tpos);
            let width = 0.008 * (1.0 + sf * 0.5) * (1.0 + band * 0.3);
            let seg = smoothstep(width, 0.0, td);
            minTendrilDist = min(minTendrilDist, td / width);
            bgGlow = bgGlow + seg * (1.0 - sf * 0.3);

            // Node pulse phase-offset by this tendril's own FFT band.
            let pulse = sin(time * 3.0 * pulseSpeed + tf * 5.0 + sf * 10.0 + band * 6.2831) * 0.5 + 0.5;
            let nodeSize = 0.012 * pulse * (1.0 + treble * 0.5 + band * 0.5);
            let node = smoothstep(nodeSize, 0.0, td);
            bgGlow = bgGlow + node * 2.0;
        }

        let tendrilCol = vec3<f32>(0.1, 0.8, 0.6) * (0.5 + mids * 0.3 + band * 0.2);
        bgCol = bgCol + tendrilCol * smoothstep(1.0, 0.0, minTendrilDist);
    }

    // ── Scattered glow dots ─────────────────────────────────────────
    // Dot Density slider gates how many grid cells ignite, and scales
    // the radius of the ones that do.
    let dotUV = uv * 30.0;
    let dotId = floor(dotUV);
    let dotFract = fract(dotUV) - 0.5;
    let dotGate = step(hash21(dotId + vec2<f32>(7.0, 3.0)), 0.15 + dotDensity * 0.85);
    let dotPhase = hash21(dotId) * 6.28 + time * (0.5 + hash21(dotId + vec2<f32>(1.0, 0.0)) * 2.0);
    let dotPulse = sin(dotPhase) * 0.5 + 0.5;
    let dotSize = 0.08 * dotPulse * (0.3 + dotDensity * 0.7);
    let dot = smoothstep(dotSize, 0.0, length(dotFract)) * dotGate;
    let dotCol = vec3<f32>(0.2, 1.0, 0.7) * dot * (0.3 + bass * 0.7);
    bgCol = bgCol + dotCol;
    bgGlow = bgGlow + dot;

    // Ambient halo — Glow Radius widens the falloff and brightens it.
    let ambient = smoothstep(0.2 + glowRadius * 0.5, 0.0, length(p)) * (0.04 + glowRadius * 0.12);
    bgCol = bgCol + vec3<f32>(0.05, 0.15, 0.2) * ambient;

    // ── Reaction-diffusion Gray-Scott colony layer ──────────────────
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let texel = 1.0 / res;
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(-texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, -texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let Du = 0.18;
    let Dv = 0.09;
    let feed = 0.025 + bass * 0.015;
    let kill = 0.055 - mids * 0.008;

    let uVal = prev.r;
    let vVal = prev.g;

    let lapU = left.r + right.r + up.r + down.r - 4.0 * uVal;
    let lapV = left.g + right.g + up.g + down.g - 4.0 * vVal;

    let uv2 = uVal * vVal * vVal;
    let du = Du * lapU - uv2 + feed * (1.0 - uVal);
    let dv = Dv * lapV + uv2 - (feed + kill) * vVal;

    // Chemotaxis toward the spring-eased nutrient source (pursuit, not snap)
    let gradN = normalize(nutrientAim - uv + vec2<f32>(0.0001));
    let motility = 0.02 + mids * 0.03;
    let chemoU = motility * (gradN.x * (right.r - left.r) + gradN.y * (up.r - down.r));
    let chemoV = motility * (gradN.x * (right.g - left.g) + gradN.y * (up.g - down.g));

    var un = uVal + du + chemoU;
    var vn = vVal + dv + chemoV;

    // Nutrient pellet drop follows the eased spring position
    let pellet = smoothstep(0.03, 0.0, length(uv - nutrientAim)) * u.zoom_config.w;
    un = un + pellet * 0.4;

    // Treble flash events (stress response)
    let flash = step(0.75, treble) * hash21(uv * 20.0 + time * 3.0) * 0.25;
    vn = vn + flash;

    un = clamp(un, 0.0, 1.0);
    vn = clamp(vn, 0.0, 1.0);

    // Quorum sensing glow activation
    let quorum = smoothstep(0.18, 0.28, vn);
    let glow = vn * quorum * 5.0;

    // Depth attenuation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let attenuation = 1.0 - depth * 0.6;

    // Colony density
    let density = clamp(un + vn * 0.5, 0.0, 1.0);

    // Deep ocean bioluminescence palette
    var col = mix(vec3<f32>(0.0, 0.04, 0.08), vec3<f32>(0.0, 0.5, 0.6), glow);
    col = mix(col, vec3<f32>(0.2, 0.9, 0.6), smoothstep(0.4, 1.0, glow));

    // Blend background tendrils behind colony
    col = col + bgCol * (1.0 - density);

    // Volumetric light scatter — Glow Radius widens the scatter cone
    let scatter = smoothstep(0.2 + glowRadius * 0.5, 0.0, length(uv - 0.5)) * glow * (0.15 + glowRadius * 0.3);
    col = col + vec3<f32>(0.1, 0.3, 0.4) * scatter;

    // HDR bloom on quorum activation waves.
    // Hue-preserving clamp at ~1.2 BEFORE the tonemap keeps the wave
    // crests hot without clipping the bioluminescent palette.
    let bloom = pow(quorum, 2.0) * 2.5 * (1.0 + bass);
    let bloomCol = huePreserveClamp(vec3<f32>(0.4, 0.8, 1.0) * bloom, 1.2);
    col = col + bloomCol;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // Single ACES tone map (the old second pass washed out highlights)
    col = acesToneMap(col);

    let alpha = clamp(density * glow * attenuation + bgGlow * 0.1, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(un, vn, glow, density));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(glow * 0.4 * attenuation, 0.0, 0.0, 0.0));
}
