// ═══════════════════════════════════════════════════════════════════
//  Neon Edge Reveal
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  Swarm upgrade: 2026-07-31 (Batch 20, Algorithmist)
//   - Slider roles rewired (ids/names/defaults unchanged — preset contract):
//       x Intensity -> emission/glow intensity (x * 2.0, default = x1.0)
//       y Speed     -> neon hue-cycle speed (mix(0.0, 4.0, y), default = 2.0)
//       z Scale     -> reveal radius scale (0.2 + z * 0.3, default = 0.35)
//       w Detail    -> Sobel smoothstep window (default = 0.06/0.325)
//   - HDR emission (~19.8x peak) tamed by a hue-preserving soft-knee that
//     compresses the per-channel max above 1.5 and asymptotes near 2.0.
//   - Click ripples ignite the reveal at their click point (~1.2s fade).
//   - Flashlight beam glides via a critically-damped spring
//     (extraBuffer[133..136] = pos.xy/vel.xy, init flag [137]).
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Intensity, y=Speed, z=Scale, w=Detail
  ripples: array<vec4<f32>, 50>,
};

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

// Critically-damped spring step toward the beam aim point.
// State lives in extraBuffer[133..136] (pos.xy, vel.xy), init flag [137].
fn springStep(pos: vec2<f32>, vel: vec2<f32>, aim: vec2<f32>, omega: f32, dt: f32) -> vec4<f32> {
    let accel = omega * omega * (aim - pos) - 2.0 * omega * vel;
    let newVel = vel + accel * dt;
    let newPos = pos + newVel * dt;
    return vec4<f32>(newPos, newVel);
}

// Hue-preserving soft-knee: compresses the per-channel max above the knee
// (peak / (1 + max(peak - knee, 0) * 0.5), asymptote ~2.0 at knee 1.5) and
// rescales the whole color by that ratio, so hue and saturation survive the
// blowout instead of clipping per-channel to white.
fn softKnee(c: vec3<f32>, knee: f32) -> vec3<f32> {
    let peak = max(c.r, max(c.g, c.b));
    let mapped = peak / (1.0 + max(peak - knee, 0.0) * 0.5);
    return c * (mapped / max(peak, 1e-5));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioReactivity = 1.0 + mids * 0.3;

    // Params (rewired roles — defaults reproduce the pre-upgrade look):
    // x 'Intensity' now drives emission/glow intensity (old glowIntensity role).
    // y 'Speed' now drives the neon hue-cycle speed (was hardcoded time * 2.0).
    // z 'Scale' now drives the reveal radius (old revealRadius role).
    // w 'Detail' now drives the Sobel edge window; old occlusionBalance alpha
    // role rides along on w (its 0.1 * 0.5 = 0.05 default factor is preserved).
    let glowIntensity = u.zoom_params.x * 2.0;
    let hueSpeed = mix(0.0, 4.0, u.zoom_params.y);
    let revealRadius = (0.2 + u.zoom_params.z * 0.3) * (1.0 + bass * 0.4);
    let detail = u.zoom_params.w;
    // Old edgeBoost folds into the emission chain as a constant 1.0 factor;
    // its (1.0 + treble * 0.3) audio term moves onto the emission below.
    let trebleBoost = 1.0 + treble * 0.3;

    let stepX = 1.0 / max(resolution.x, 1.0);
    let stepY = 1.0 / max(resolution.y, 1.0);

    // Sample neighbors as full vec4 (preserve alpha)
    let s_tl = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-stepX, -stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_tc = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, -stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_tr = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(stepX, -stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_ml = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-stepX, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_mc = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let s_mr = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(stepX, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_bl = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-stepX, stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_bc = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_br = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(stepX, stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // Sobel on luminance
    let gx = -getLuminance(s_tl.rgb) - 2.0 * getLuminance(s_ml.rgb) - getLuminance(s_bl.rgb)
           + getLuminance(s_tr.rgb) + 2.0 * getLuminance(s_mr.rgb) + getLuminance(s_br.rgb);
    let gy = -getLuminance(s_tl.rgb) - 2.0 * getLuminance(s_tc.rgb) - getLuminance(s_tr.rgb)
           + getLuminance(s_bl.rgb) + 2.0 * getLuminance(s_bc.rgb) + getLuminance(s_br.rgb);
    let edgeStrength = sqrt(gx * gx + gy * gy);

    // Mouse flashlight — spring-damped so the beam glides toward the cursor
    let mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    var springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        // First contact: snap the spring onto the cursor, zero velocity.
        springPos = mousePos;
        springVel = vec2<f32>(0.0, 0.0);
    }
    let springState = springStep(springPos, springVel, mousePos, 8.0, 0.016);
    let beamPos = springState.xy;
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = springState.x;
        extraBuffer[134] = springState.y;
        extraBuffer[135] = springState.z;
        extraBuffer[136] = springState.w;
        extraBuffer[137] = 1.0;
    }

    let aspect = resolution.x / resolution.y;
    let distToMouse = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(beamPos.x * aspect, beamPos.y));
    let revealFalloff = 1.0 - smoothstep(0.0, max(revealRadius, 0.0001), distToMouse);

    // Click flare bursts: each live ripple temporarily ignites the reveal at
    // its click point (~1.2s fade), so nearby edges flash awake on click.
    var clickFlare = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(ripple.x * aspect, ripple.y));
        let age = time - ripple.z;
        let fade = clamp(1.0 - age / 1.2, 0.0, 1.0);
        let flash = (1.0 - smoothstep(0.0, max(revealRadius, 0.0001), rDist)) * fade;
        clickFlare = max(clickFlare, flash);
    }
    let reveal = clamp(revealFalloff + clickFlare, 0.0, 1.0);

    // Neon color cycling (mids drives hue speed)
    let neonColor1 = vec3<f32>(1.0, 0.0, 0.8);
    let neonColor2 = vec3<f32>(0.0, 1.0, 1.0);
    let mixFactor = 0.5 + 0.5 * sin(time * hueSpeed * audioReactivity + uv.x * 3.0);
    let neonColor = mix(neonColor1, neonColor2, mixFactor);

    // Emission (branchless)
    let edge = smoothstep(mix(0.08, 0.02, detail), mix(0.5, 0.10, detail), edgeStrength);
    let glow = 0.3 + (2.0 + bass * 1.5) * reveal;
    let emissionRaw = neonColor * glow * edge * 1.0 * glowIntensity * trebleBoost;

    // Tame the HDR: hue-preserving soft-knee caps the neon gracefully
    // (knee 1.5, asymptotic peak ~2.0) instead of clipping to white.
    let emission = softKnee(emissionRaw, 1.5);

    let glowStrength = length(emission);

    // Meaningful alpha: edge strength + reveal + source alpha + audio sparkle
    let baseAlpha = s_mc.a;
    let alpha = clamp(edge * 0.5 + reveal * 0.3 + baseAlpha * 0.2 + glowStrength * 0.1 * detail + treble * 0.1, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(emission, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(emission, alpha));
}
