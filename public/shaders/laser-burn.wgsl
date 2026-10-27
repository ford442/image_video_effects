// ═══════════════════════════════════════════════════════════════════
//  Laser Burn
//  Category: interactive-mouse
//  Features: mouse-driven, temporal-accumulation, ember-glow, audio-sparks, upgraded-rgba
//  Complexity: High
//  Chunks From: laser-burn, bass_env, temporal-feedback
//  Created: 2026-05-10
//  Upgraded: 2026-05-31, 2026-10-27
//  Ideas: neighbour heat conduction; oxide lip on the char edge
//  A packing: raw (char, cooledHeat, ember, alpha). ACES on the display write only.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=BeamSize, y=BurnIntensity, z=HealRate, w=HeatGlow

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let c = max(x, vec3<f32>(0.0));
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMod = mix(1.0, 0.7, depth);

    // ── Sliders: 4 honestly-wired shader-specific constants ─────────
    // Beam Size       -> physical beam radius
    // Burn Intensity  -> heat injected per frame inside the beam
    // Heal Rate       -> char self-repair factor
    // Heat Glow       -> strength of the live fire glow
    let beamSize = mix(0.01, 0.15, u.zoom_params.x) * (1.0 + bass * 0.2);
    let burnSpeed = u.zoom_params.y * 0.2 * (1.0 + treble * 0.3);
    let healFactor = mix(1.0, 0.9, u.zoom_params.z);
    let heatMix = u.zoom_params.w;

    // ── Burn state (SACRED contract) ────────────────────────────────
    // dataTextureC = previous frame state: (charLevel, cooledHeat, emberLevel, burnAlpha)
    let coord = vec2<i32>(global_id.xy);
    let resI = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
    let prev = textureLoad(dataTextureC, coord, 0);
    var charLevel = prev.r;
    var heatLevel = prev.g;
    var emberLevel = prev.b;

    // ── Idea 1: heat conduction from the four stored neighbours.
    let nR = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), resI), 0);
    let nL = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), resI), 0);
    let nU = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), resI), 0);
    let nD = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), resI), 0);
    let neighHeat = (nR.g + nL.g + nU.g + nD.g) * 0.25;
    let neighChar = (nR.r + nL.r + nU.r + nD.r) * 0.25;
    heatLevel = heatLevel + (neighHeat - heatLevel) * 0.12;

    // The CPU clears extraBuffer every frame, so the old spring never left
    // the pointer. The beam is the cursor.
    let beamPos = u.zoom_config.yz;

    let mouseDown = step(0.5, u.zoom_config.w);

    let aspect = resolution.x / max(resolution.y, 0.001);
    var dVec = uv - beamPos;
    dVec.x *= aspect;
    let dist = length(dVec);

    let inBeam = step(dist, beamSize) * mouseDown;
    let intensity = smoothstep(beamSize, beamSize * 0.5, dist);
    // Bass deepens the char: the audio envelope feeds the heat injection
    heatLevel += intensity * burnSpeed * inBeam * bass_env(bass, mids);

    // ── Click brand stamps ──────────────────────────────────────────
    // Each live ripple sears a one-shot brand at its click point, so a
    // single click tattoos the surface without holding the button.
    // These feed the SAME char/ember pipeline below.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleAge = time - ripple.z;
        if (rippleAge >= 0.0 && rippleAge <= 4.0) {
            var rVec = uv - ripple.xy;
            rVec.x *= aspect; // aspect-corrected brand radius
            let rDist = length(rVec);
            let brandRadius = 0.08;
            let brand = smoothstep(brandRadius, brandRadius * 0.3, rDist);
            heatLevel += 0.6 * brand * exp(-rippleAge * 1.5); // one pulse
        }
    }

    // Ember accumulation: heat chars the surface, embers glow after
    let cooledHeat = heatLevel * 0.9;
    charLevel += cooledHeat * 0.1;
    charLevel = clamp(charLevel, 0.0, 1.0);
    charLevel *= healFactor;

    // Ember persistence: embers fade slower than heat
    emberLevel = mix(emberLevel, cooledHeat, 0.1);
    emberLevel *= 0.95;

    // ── Idea 2: oxide lip where this char differs from its neighbours.
    let charEdge = clamp(abs(charLevel - neighChar) * 4.0, 0.0, 1.0);
    emberLevel = clamp(emberLevel + charEdge * 0.28, 0.0, 1.0);

    // ── Per-sector spark showers ────────────────────────────────────
    // Divide the beam zone into 8 angular sectors around the beam
    // center; each sector's spark threshold rides its own FFT bin so
    // spark showers dance around the beam instead of firing globally.
    let beamAngle = atan2(dVec.y, dVec.x);
    let sectorF = floor((beamAngle + 3.14159265) / 6.2831853 * 8.0);
    let sector = u32(sectorF) % 8u;
    // plasmaBuffer[1..] is never uploaded. Sectors share the live treble band.
    let sectorBin = treble * fract(sin(f32(sector) * 12.9898) * 43758.5453);
    let sparkChance = hash12(uv * 100.0 + time * 10.0);
    let spark = step(1.0 - sectorBin * 0.3, sparkChance) * inBeam * 0.5;
    emberLevel += spark;
    emberLevel = clamp(emberLevel, 0.0, 1.0);

    let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Visuals: char darkens source, ember glow adds warmth
    var finalColor = source.rgb * (1.0 - charLevel);
    let fireColor = vec3<f32>(1.0, 0.6 + mids * 0.2, 0.2);
    let emberColor = vec3<f32>(1.0, 0.4, 0.1) * emberLevel * 2.0;
    finalColor += fireColor * cooledHeat * (0.5 + heatMix * 2.0);
    finalColor += emberColor * depthMod;

    // Audio sparks are bright white-yellow
    let sparkColor = vec3<f32>(1.0, 0.9, 0.6) * spark * 3.0;
    finalColor += sparkColor;

    let burnAlpha = clamp(charLevel * 0.6 + cooledHeat * 0.3 + emberLevel * 0.2 + dot(finalColor, vec3<f32>(0.299, 0.587, 0.114)) * 0.2, 0.0, 1.0);
    let outputColor = vec4<f32>(acesFilm(finalColor), burnAlpha);

    // State write: (charLevel, cooledHeat, emberLevel, burnAlpha)
    // Raw state only — never tonemap or clamp beyond the clamps above.
    let stateColor = vec4<f32>(charLevel, cooledHeat, emberLevel, burnAlpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), outputColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), stateColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
