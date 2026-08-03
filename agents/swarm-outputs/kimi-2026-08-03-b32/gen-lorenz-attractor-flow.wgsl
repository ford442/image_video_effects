// ═══════════════════════════════════════════════════════════════════
//  Lorenz Attractor Flow
//  Category: generative
//  Features: generative, mouse-driven, temporal, chromatic, depth-aware,
//            sdf-tube, kaleidoscope, orbit-trap, orbit-camera,
//            ripple-deform, audio-reactive, fft-reactive
//  Complexity: High
//  Chunks From: none (original)
//  Created: 2026-05-09
//  Upgraded: 2026-05-31
//  b32 Interactivist: 2026-08-03 — SDF tube ray along the attractor
//    trajectory, kaleidoscopic orbit-trap backdrop, mouse orbit camera,
//    guarded ripple deformation, real depth (was flat 0.5 clobber)
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;
    let t = time * 0.05;
    let mouse = u.zoom_config.yz; // already normalized 0-1, y=0 top — used as-is
    let mouseDown = u.zoom_config.w;

    let dt = 0.002 + u.zoom_params.x * 0.012;
    let colorShift = u.zoom_params.y;
    let glowIntensity = u.zoom_params.z;
    let mouseInfluence = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Real FFT bins (read-only, length-guarded) + smoothed-bass persistent state
    var fftLow = 0.0;
    var fftHigh = 0.0;
    var bassS = bass;
    let ebLen = arrayLength(&extraBuffer);
    if (ebLen > 132u) {
        fftLow = extraBuffer[8u];
        fftHigh = extraBuffer[64u];
    }
    if (ebLen > 133u) {
        bassS = extraBuffer[133u];
        if (gid.x == 0u && gid.y == 0u) {
            extraBuffer[133u] = mix(bassS, bass, 0.12);
        }
    }

    // ═══ b32: guarded click ripples → per-pixel deformation wave ═══
    var rippleWave = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var r: u32 = 0u; r < rippleCount; r = r + 1u) {
        let rp = u.ripples[r];
        let age = time - rp.z;
        if (age > 0.0 && age < 4.0) {
            let rd2 = length(uv - rp.xy);
            rippleWave += exp(-rd2 * 8.0) * sin(rd2 * 36.0 - age * 9.0) * exp(-age * 1.5);
        }
    }
    rippleWave = clamp(rippleWave, -0.8, 1.5);

    // Map UV to phase space (scaled Lorenz coordinates)
    var p = vec3<f32>(
        (uv.x - 0.5) * 50.0 + sin(t * 0.3) * 2.0,
        (uv.y - 0.5) * 50.0 + cos(t * 0.4) * 2.0,
        20.0 + sin(t * 0.2) * 5.0
    );

    // Mouse interaction: perturb starting position
    p.x += (mouse.x - 0.5) * 20.0 * mouseInfluence;
    p.y += (mouse.y - 0.5) * 20.0 * mouseInfluence;

    // Lorenz parameters (classic chaotic values)
    let sigma: f32 = 10.0;
    let rho: f32 = 28.0;
    let beta: f32 = 8.0 / 3.0;

    var pathLength: f32 = 0.0;
    var prevP = p;
    // ═══ b32: orbit trap — closest approach to the two attractor lobes ═══
    var orbitTrap = 1e5;

    // Integrate Lorenz ODE (Euler method, 80 steps for smooth flow)
    for (var i: i32 = 0; i < 80; i = i + 1) {
        let dx = sigma * (p.y - p.x);
        let dy = p.x * (rho - p.z) - p.y;
        let dz = p.x * p.y - beta * p.z;

        p.x += dx * dt;
        p.y += dy * dt;
        p.z += dz * dt;

        pathLength += length(p - prevP);
        prevP = p;
        orbitTrap = min(orbitTrap, min(
            length(p.xy - vec2<f32>(8.5, 8.5)),
            length(p.xy - vec2<f32>(-8.5, -8.5))
        ));
    }

    // Color based on final position and trajectory
    let hue = fract(p.z * 0.015 + t * 0.1 + pathLength * 0.002 + colorShift);
    let sat = 0.85 + sin(p.x * 0.08 + t) * 0.15;
    let val = 0.55 + 0.45 * (sin(p.y * 0.06 + t * 1.5) * 0.5 + 0.5);

    var rgb = hsv2rgb(vec3<f32>(hue, sat, val));

    // Chromatic dispersion: offset lobe glow per channel by audio
    let lobeDistR = min(
        length(vec2<f32>(p.x + 8.0 + bass * 1.5, p.y + mids * 0.5) * 0.08),
        length(vec2<f32>(p.x - 8.0 + bass * 1.5, p.y + mids * 0.5) * 0.08)
    );
    let lobeDistG = min(
        length(vec2<f32>(p.x + 8.0 - treble * 1.0, p.y + bass * 1.0) * 0.08),
        length(vec2<f32>(p.x - 8.0 - treble * 1.0, p.y + bass * 1.0) * 0.08)
    );
    let lobeDistB = min(
        length(vec2<f32>(p.x + 8.0 + mids * 0.8, p.y - treble * 1.2) * 0.08),
        length(vec2<f32>(p.x - 8.0 + mids * 0.8, p.y - treble * 1.2) * 0.08)
    );
    let glowR = exp(-lobeDistR * 1.8) * 0.35 * glowIntensity;
    let glowG = exp(-lobeDistG * 1.8) * 0.35 * glowIntensity;
    let glowB = exp(-lobeDistB * 1.8) * 0.35 * glowIntensity;
    rgb = vec3<f32>(rgb.r * (0.85 + glowR), rgb.g * (0.85 + glowG), rgb.b * (0.85 + glowB));

    // ═══ b32: 3D SDF tube swept along the attractor trajectory ═══
    // Mouse orbit camera (zoom_config.yz used directly, no flip)
    let aspect = res.x / res.y;
    let camRot = rotY((mouse.x - 0.5) * PI * mouseInfluence * 2.0)
               * rotX((mouse.y - 0.5) * PI * 0.8 * mouseInfluence);
    let ndc = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let ro3 = camRot * vec3<f32>(0.0, 0.0, 62.0);
    let rd3 = camRot * normalize(vec3<f32>(ndc * 30.0, -60.0));

    // Swept tube: march the ODE once, glow-accumulate ray distance per node
    var tp = vec3<f32>(sin(t * 0.7) * 5.0, cos(t * 0.9) * 5.0, 27.0);
    let dtTraj = 0.008 + u.zoom_params.x * 0.004;
    let tubeR = max((1.1 + bassS * 1.4 + fftLow * 0.6) * (1.0 + rippleWave * 0.6), 0.08);
    let twistRate = mids * 0.35 + time * 0.05;
    var tubeGlow = 0.0;
    var tHit = 1e5;
    for (var i: i32 = 0; i < 44; i = i + 1) {
        let ddx = sigma * (tp.y - tp.x);
        let ddy = tp.x * (rho - tp.z) - tp.y;
        let ddz = tp.x * tp.y - beta * tp.z;
        tp += vec3<f32>(ddx, ddy, ddz) * dtTraj;
        // mids twist: progressive rotation of the swept path in the z-plane
        let ta = twistRate * f32(i) * 0.04;
        let tc = cos(ta); let ts = sin(ta);
        let tw = vec3<f32>(tp.x * tc - tp.y * ts, tp.x * ts + tp.y * tc, tp.z - 27.0);
        let tQ = dot(tw - ro3, rd3);
        let dQ = length(ro3 + rd3 * clamp(tQ, 0.0, 120.0) - tw) - rippleWave * 1.5;
        tubeGlow += exp(-max(dQ, 0.0) * max(dQ, 0.0) / (tubeR * tubeR)) * 0.05;
        if (dQ < tubeR && tQ > 0.0 && tQ < tHit) { tHit = tQ; }
    }
    let tubeHue = fract(colorShift + t * 0.15 + pathLength * 0.001);
    let tubeCol = hsv2rgb(vec3<f32>(tubeHue, 0.7, 1.0));
    rgb += tubeCol * tubeGlow * (0.4 + glowIntensity * 1.2);

    // ═══ b32: kaleidoscopic orbit-trap backdrop ═══
    let folds = 6.0 + floor(treble * 4.0 + fftHigh * 2.0);
    let kc = uv - 0.5;
    let ka = atan2(kc.y, kc.x);
    let kr = length(kc);
    let seg = TAU / folds;
    let fa = (abs(fract(ka / seg) - 0.5) + rippleWave * 0.15) * seg;
    let kuv = kr * vec2<f32>(cos(fa), sin(fa));
    let trapV = exp(-orbitTrap * 0.06);
    let trapHue = fract(colorShift * 0.7 + orbitTrap * 0.01 + t * 0.05 + kuv.x * 1.5);
    let kalMask = smoothstep(0.0, 0.45, 0.5 - length(kuv - vec2<f32>(0.18, 0.0)));
    let trapCol = hsv2rgb(vec3<f32>(trapHue, 0.8, trapV * (0.3 + glowIntensity * 0.5)));
    rgb = mix(rgb, rgb + trapCol * kalMask, 0.35 + mids * 0.15);

    // Mouse click ripple boost
    if (mouseDown > 0.5) {
        let rippleDist = length(uv - mouse);
        let ripple = exp(-rippleDist * 8.0) * sin(t * 20.0) * 0.4;
        rgb += vec3<f32>(0.3, 0.6, 1.0) * ripple;
    }

    // Gentle vignette for depth
    let vignette = 1.0 - length(uv - 0.5) * 0.6;
    rgb *= vignette;

    // Temporal feedback
    let prev = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
    rgb = mix(rgb, prev.rgb * 0.9, 0.03 + bass * 0.01);

    // Luminance-key alpha: brighter regions more opaque (+ 3D tube presence)
    let luma = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(mix(0.75, 1.0, smoothstep(0.2, 0.6, luma)) + tubeGlow * 0.1, 0.0, 1.0);

    // ═══ b32: real depth — tube surface distance + orbit-trap relief ═══
    // (b32 fix: was a flat 0.5 clobber)
    let tubeDepth = select(0.0, 1.0 - tHit / 120.0, tHit < 120.0);
    let trapDepth = trapV * 0.35;
    let outDepth = clamp(max(tubeDepth, trapDepth), 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(rgb, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(rgb, alpha));
}
