// ═══════════════════════════════════════════════════════════════════
//  Laser Burn
//  Category: interactive-mouse
//  Features: mouse-driven, temporal-accumulation, ember-glow, audio-sparks, upgraded-rgba
//  Complexity: High
//  Chunks From: laser-burn, bass_env, temporal-feedback
//  Created: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
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

    let beamSize = mix(0.01, 0.15, u.zoom_params.x) * (1.0 + bass * 0.2);
    let burnSpeed = u.zoom_params.y * 0.2 * (1.0 + treble * 0.3);
    let healFactor = mix(1.0, 0.9, u.zoom_params.z);
    let heatMix = u.zoom_params.w;

    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var charLevel = prev.r;
    var heatLevel = prev.g;
    var emberLevel = prev.b;

    let mouse = u.zoom_config.yz;
    let mouseDown = step(0.5, u.zoom_config.w);

    let aspect = resolution.x / max(resolution.y, 0.001);
    var dVec = uv - mouse;
    dVec.x *= aspect;
    let dist = length(dVec);

    let inBeam = step(dist, beamSize) * mouseDown;
    let intensity = smoothstep(beamSize, beamSize * 0.5, dist);
    heatLevel += intensity * burnSpeed * inBeam;

    // Ember accumulation: heat chars the surface, embers glow after
    let cooledHeat = heatLevel * 0.9;
    charLevel += cooledHeat * 0.1;
    charLevel = clamp(charLevel, 0.0, 1.0);
    charLevel *= healFactor;

    // Ember persistence: embers fade slower than heat
    emberLevel = mix(emberLevel, cooledHeat, 0.1);
    emberLevel *= 0.95;

    // Audio spark showers: treble creates flying sparks near the beam
    let sparkChance = hash12(uv * 100.0 + time * 10.0);
    let spark = step(1.0 - treble * 0.3, sparkChance) * inBeam * 0.5;
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
    let outputColor = vec4<f32>(finalColor, burnAlpha);

    let stateColor = vec4<f32>(charLevel, cooledHeat, emberLevel, burnAlpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), outputColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), stateColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
