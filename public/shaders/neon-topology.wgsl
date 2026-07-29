// ═══════════════════════════════════════════════════════════════════
//  Neon Topology
//  Category: visual-effects
//  Features: advanced-alpha, topology, neon, contours, mouse-driven, audio-reactive, depth-haze, upgraded-rgba
//  Complexity: High
//  Chunks From: neon-topology, bass_env, depth-aware-fog
//  Upgraded: 2026-05-31
//  Swarm Upgrade: 2026-07-30 (batch 18, Algorithmist)
//    - Wired the mouse: lens bumps the depth field under the cursor.
//    - Honest sliders: y = Height Scale (contour field), w = Glow Strength.
//    - Click contour quakes: ripples[] drop decaying rings into the topology.
//    - Removed the dead `alpha` variable; folded its terms into finalAlpha.
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=LineDensity, y=HeightScale, z=MouseForce, w=GlowStrength
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// Legacy default of the retired edge-threshold slider (0.5 * 0.1 + 0.02).
const EDGE_THRESHOLD: f32 = 0.07;
// Aspect-corrected mouse lens falloff radius.
const LENS_RADIUS: f32 = 0.35;
// Click-quake lifetime in seconds (~1.5s decaying ring).
const QUAKE_LIFE: f32 = 1.5;

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn edgePreserveAlpha(uv: vec2<f32>, pixelSize: vec2<f32>, edgeThreshold: f32) -> f32 {
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold, depthEdge);
    return mix(0.2, 1.0, edgeMask);
}

// Mouse lens: aspect-corrected smoothstep falloff, 1.0 at cursor -> 0.0 at ~0.35.
fn mouseLensMask(uv: vec2<f32>, mouse: vec2<f32>, aspect: f32) -> f32 {
    let delta = (uv - mouse) * vec2<f32>(aspect, 1.0);
    return smoothstep(LENS_RADIUS, 0.0, length(delta));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let audioBass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Honest slider contract (matches JSON param order) ────────────
    let density = u.zoom_params.x;                          // Line Density
    let heightScale = mix(0.5, 2.0, u.zoom_params.y);       // Height Scale
    let mouseForce = u.zoom_params.z;                       // Mouse Force
    let glow = u.zoom_params.w;                             // Glow Strength

    let contourLevels = density * 10.0 + 3.0 + audioBass * 4.0;
    let intensity = glow * 2.0 * bass_env(audioBass, mids);

    // ── Mouse lens: bump the sampled depth near the cursor ───────────
    let mouse = u.zoom_config.yz;
    let lensMask = mouseLensMask(uv, mouse, aspect);
    let mouseDownBoost = 1.0 + u.zoom_config.w * 0.5;

    // ── Click contour quakes: pebbles dropped into the topology ──────
    var quake = 0.0;
    var quakeGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        let live = step(0.0, age) * (1.0 - smoothstep(0.0, QUAKE_LIFE, age));
        let rDelta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
        let rDist = length(rDelta);
        let ring = sin(rDist * 24.0 - age * 8.0) * exp(-rDist * 5.0) * exp(-age * 2.5);
        quake += ring * live;
        quakeGlow += abs(ring) * live;
    }

    // Depth field warped by the mouse lens and click quakes.
    var depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    depth += lensMask * mouseForce * 0.25 * mouseDownBoost;
    depth += quake * 0.1;

    // Branchless contour lines (height scale stretches the contour field).
    let contourPhase = depth * heightScale * contourLevels;
    let contour = fract(contourPhase);
    let line = smoothstep(0.05, 0.0, contour);
    let major = step(0.95, fract(contourPhase * 0.2));
    let lineWithMajor = line * (1.0 + major * 0.6);

    // Audio elevation: bass adds phantom contours above actual depth
    let phantomPhase = (depth + audioBass * 0.1) * contourLevels * 0.5;
    let phantomLine = smoothstep(0.03, 0.0, fract(phantomPhase)) * audioBass * 0.5;

    // Neon color with treble shimmer — hue now on a slow constant drift
    // (time * 0.15 * TAU ~= old 1 rad/s drift), color identity preserved.
    let hueDrift = time * 0.15;
    let phase = depth * 10.0 + hueDrift * TAU + PI + treble * 2.0;
    let neonColor = 0.5 + 0.5 * sin(vec3<f32>(phase, phase + 2.094, phase + 4.188));

    // Lens rim: a faint ring tracing the mouse lens radius.
    let rim = smoothstep(0.04, 0.0, abs(length((uv - mouse) * vec2<f32>(aspect, 1.0)) - LENS_RADIUS)) * mouseForce * 0.35;

    // Depth atmospheric haze
    let haze = exp(-depth * 3.0) * 0.3;

    let bgSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let bg = bgSample.rgb;
    let bgGray = vec3<f32>(dot(bg, vec3<f32>(0.299, 0.587, 0.114))) * 0.4;
    let emission = neonColor * (lineWithMajor + phantomLine + quakeGlow * 0.6 + rim) * intensity;
    let final_color = mix(bgGray + emission, vec3<f32>(0.1, 0.15, 0.25), haze);

    // Edge-aware alpha: folds in the useful terms of the removed dead `alpha`.
    let edgeMask = edgePreserveAlpha(uv, pixelSize, EDGE_THRESHOLD);
    let finalAlpha = clamp(mix(bgSample.a, 1.0, intensity * lineWithMajor * 0.7) * edgeMask
                           + phantomLine * 0.2 + quakeGlow * 0.3, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(final_color, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
