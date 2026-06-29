// ═══════════════════════════════════════════════════════════════════
//  Holographic Flicker
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, temporal-flicker,
//            depth-rainbow, chromatic-ghosting, interference-fringes,
//            scanline-jitter, temporal-rgb-offset, upgraded-rgba
//  Complexity: High
//  Chunks From: holographic-flicker, hash, bass_env
//  Created: 2024-01-01
//  Upgraded: 2026-06-28
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

// ── Thin-film interference fringe pattern ────────────────────────
fn interferenceFringes(uv: vec2<f32>, time: f32, freq: f32, strength: f32) -> f32 {
    let phase = uv.y * freq + uv.x * freq * 0.5 - time * 6.0;
    return pow(0.5 + 0.5 * cos(phase), 6.0) * strength;
}

// ── Scanline jitter: per-row horizontal displacement ─────────────
fn scanlineJitter(uv: vec2<f32>, resolution: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
    let line = floor(uv.y * resolution.y);
    let jitter = (hash21(vec2<f32>(line, time * 60.0)) - 0.5) * intensity * 0.04;
    return uv + vec2<f32>(jitter, 0.0);
}

// ── Temporal RGB channel offset ──────────────────────────────────
fn temporalRGBOffset(uv: vec2<f32>, time: f32, amount: f32) -> vec3<f32> {
    let r = textureSampleLevel(readTexture, u_sampler,
                               uv + vec2<f32>(sin(time * 4.0) * amount, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler,
                               uv + vec2<f32>(cos(time * 3.0) * amount * 0.6, 0.0), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler,
                               uv - vec2<f32>(sin(time * 5.0) * amount, 0.0), 0.0).b;
    return vec3<f32>(r, g, b);
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
    let mousePos = u.zoom_config.yz;

    let nParams = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
    let flickerSpeed = nParams.x * bass_env(bass, mids);
    let glitchAmt = nParams.y;
    let hologramIntensity = nParams.z;
    let ghostAmt = nParams.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthHue = mix(0.0, 1.0, depth);

    let dToMouse = uv - mousePos;
    let mouseDist = length(dToMouse);
    let mouseInfluence = smoothstep(0.4, 0.0, mouseDist);

    // Scanline jitter + temporal RGB channel offset
    let jitteredUV = scanlineJitter(uv, resolution, time, glitchAmt);
    let offsetAmount = (glitchAmt + ghostAmt) * 0.01 * (1.0 + treble * 0.5);
    let rgbOffset = temporalRGBOffset(jitteredUV, time, offsetAmount);
    let sourceColor = textureSampleLevel(readTexture, u_sampler, jitteredUV, 0.0);
    let rgb = mix(sourceColor.rgb, rgbOffset, 0.5);

    // Temporal ghosting: previous frame offset by velocity
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    let ghost = prev * 0.7 * ghostAmt;

    // Audio-reactive flicker: bass drives blackout probability, treble drives micro-glitch
    let flicker = hash21(vec2<f32>(floor(time * flickerSpeed * 10.0), uv.y * resolution.y));
    let blackout = step(1.0 - bass * 0.2, flicker) * 0.5;
    let microGlitch = (hash21(vec2<f32>(time * 500.0, uv.y * 2000.0)) - 0.5) * glitchAmt * treble * 0.02;

    let luma = dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

    // Depth rainbow: hue shifts with depth + bass
    let hue = fract(depthHue + time * 0.05 + bass * 0.1 + mouseInfluence * 0.1);
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
    let rainbow = clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));

    // Chromatic ghosting: R and B from different temporal offsets
    let rGhost = textureSampleLevel(dataTextureC, non_filtering_sampler,
                                    uv + vec2<f32>(ghostAmt * 0.01 + microGlitch, 0.0), 0.0).r;
    let bGhost = textureSampleLevel(dataTextureC, non_filtering_sampler,
                                    uv - vec2<f32>(ghostAmt * 0.01 + microGlitch, 0.0), 0.0).b;
    let gGhost = ghost.g;

    // Interference fringes layered over the hologram
    let fringes = interferenceFringes(uv, time, 120.0 + mids * 120.0, hologramIntensity);

    let hologram = vec3<f32>(rGhost, gGhost, bGhost) * (0.5 + luma * 0.5) +
                   rainbow * hologramIntensity * 0.3 +
                   fringes;
    let finalRGB = mix(rgb + hologram, vec3<f32>(0.0), blackout);

    // Preserve input alpha, boosted by hologram brightness
    let alpha = clamp(sourceColor.a * 0.9 + luma * 0.1 + hologramIntensity * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
