// ═══════════════════════════════════════════════════════════════════
//  Topological Acoustic Knots
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15, 2026-11-20
//  Ideas: opposite-charge pair annihilation; Schlieren brushes from |∇θ|; Frank splay/bend tint of the defect glow (head vs tail of each ±½ comet); Landau–de Gennes order-parameter core melt of the stripes
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Orientational director field inspired by liquid crystals.
//  Audio frequencies drive topological defect creation, motion, and
//  annihilation. Mouse can pin or create defects. Iridescent oil-slick coloring.

#include "_prelude.wgsl"
// zoom_params: x=Defect Density, y=Defect Speed, z=Iridescence, w=Flow Strength

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const CORE_GAIN: f32 = 0.7;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn defectOrbit(fi: f32, t: f32, bass: f32, treble: f32, numDefects: f32, defectSpeed: f32) -> vec2<f32> {
    let seed = hash22(vec2<f32>(fi, fi * 1.7 + 3.1));
    let orbitRadius = 0.2 + seed.x * 0.3;
    let orbitSpeed = defectSpeed * (0.5 + fi * 0.13);
    let audioMod = mix(bass, treble, fi / max(numDefects, 1.0));
    let px = seed.x * 0.6 + 0.2 + orbitRadius * cos(t * orbitSpeed + seed.y * TAU + audioMod * 0.5);
    let py = seed.y * 0.6 + 0.2 + orbitRadius * sin(t * orbitSpeed * 0.7 + seed.x * TAU + audioMod * 0.3);
    return vec2<f32>(px, py);
}

fn directorAngle(uv: vec2<f32>, t: f32, bass: f32, mids: f32, treble: f32,
                 mousePos: vec2<f32>, defectDensity: f32, defectSpeed: f32, aspect: f32) -> f32 {
    var angle = 0.0;
    let numDefects = i32(clamp(defectDensity * 8.0 + 2.0, 2.0, 12.0));
    let nF = f32(numDefects);
    let toA = vec2<f32>(aspect, 1.0);  // defects live in uv; uv here is aspect-scaled (like the mouse)

    for (var i = 0; i < numDefects; i++) {
        let fi = f32(i);
        let defectPos = defectOrbit(fi, t, bass, treble, nF, defectSpeed) * toA;

        // Idea 1 — pair annihilation: opposite-charge neighbors fade when close.
        let partnerIdx = select(i + 1, i - 1, (i % 2) == 1);
        let unpaired = (i == numDefects - 1) && ((numDefects % 2) == 1);
        let partnerPos = defectOrbit(f32(partnerIdx), t, bass, treble, nF, defectSpeed) * toA;
        let live = select(smoothstep(0.04, 0.16, length(defectPos - partnerPos)), 1.0, unpaired);

        let charge = select(-0.5, 0.5, (i % 2) == 0) * live;
        let delta = uv - defectPos;
        angle += atan2(delta.y, delta.x) * charge;
    }

    let mouseDelta = uv - mousePos;
    let mouseDist = length(mouseDelta);
    let mouseInfluence = exp(-mouseDist * mouseDist * 20.0);
    let mouseDefectAngle = atan2(mouseDelta.y, mouseDelta.x) * 0.5;
    angle += mouseDefectAngle * mouseInfluence * (1.0 + mids * 2.0);

    return angle;
}

fn iridescent(angle: f32, dist: f32, mids: f32, treble: f32) -> vec3<f32> {
    let norm = fract(angle / PI);
    let r = 0.5 + 0.5 * cos(norm * TAU + mids * 2.0);
    let g = 0.5 + 0.5 * cos(norm * TAU + 2.094 + treble * 1.5);
    let b = 0.5 + 0.5 * cos(norm * TAU + 4.189 + mids * 1.0);
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let coord = vec2<i32>(global_id.xy);

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / max(res.y, 1.0);
    let uvA = vec2<f32>(uv.x * aspect, uv.y);

    let t = u.config.x;
    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let defectDensity = u.zoom_params.x;
    let defectSpeed   = u.zoom_params.y * 0.8 + 0.1;
    let irisIntensity = u.zoom_params.z * 1.5 + 0.5;
    let flowStrength  = u.zoom_params.w * 2.0 + 0.5;

    let mousePos = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);

    let theta = directorAngle(uvA, t, bass, mids, treble,
                               mousePos, defectDensity, defectSpeed, aspect);
    let dir = vec2<f32>(cos(theta), sin(theta));

    let eps = 0.008;
    let thetaDx = directorAngle(uvA + vec2<f32>(eps, 0.0), t, bass, mids, treble,
                                  mousePos, defectDensity, defectSpeed, aspect);
    let thetaDy = directorAngle(uvA + vec2<f32>(0.0, eps), t, bass, mids, treble,
                                  mousePos, defectDensity, defectSpeed, aspect);

    // Rescue: a director is pi-periodic (n == -n), so wrap the finite
    // difference; the raw difference spikes to +-pi/eps on every atan2 cut.
    let dX = thetaDx - theta;
    let dY = thetaDy - theta;
    let dTheta = vec2<f32>(dX - PI * round(dX / PI), dY - PI * round(dY / PI)) / eps;
    let gradMag = length(dTheta);
    let defectStrength = gradMag * 0.15;

    // ── Idea 2: Landau–de Gennes order-parameter core melt ──────────
    // A +-1/2 defect has |grad theta| = 1/(2r), so r ~ 0.5/|grad theta|. The
    // scalar order S -> 0 at the core (nematic melts to isotropic), so the
    // director texture dissolves there instead of aliasing to fine stripes.
    let rCore = 0.5 / max(gradMag, 1.0e-3);
    let orderS = rCore * inverseSqrt(rCore * rCore + 0.18 * 0.18);

    // ── Idea 1: Frank splay / bend decomposition ────────────────────
    // splay = div n = grad(theta) . n_perp, bend = |n x curl n| = grad(theta) . n.
    // For a +1/2 comet the head is splay and the tail is bend.
    let splayK = abs(dot(dTheta, vec2<f32>(-dir.y, dir.x)));
    let bendK = abs(dot(dTheta, dir));
    let splayFrac = splayK / max(splayK + bendK, 1.0e-4);
    let glowTint = mix(vec3<f32>(0.35, 0.75, 1.0), vec3<f32>(1.0, 0.8, 0.4), splayFrac);

    let irisColor = iridescent(theta, length(uvA - 0.5), mids, treble);
    var color = irisColor * (0.12 + bass * 0.08);

    let stripe = sin(dot(uvA, dir) * 30.0 * flowStrength + t * 0.5) * 0.5 + 0.5;
    color += irisColor * stripe * (0.25 + mids * 0.15) * irisIntensity * orderS;  // Idea 2: melts at cores

    // Rescue: HEAD's smoothstep(0.3, 0.0, ds - 0.5) was inverted (a flat veil away from cores, dark at them).
    let defectGlow = smoothstep(0.3, 0.8, defectStrength);
    color += glowTint * defectGlow * (0.5 + treble * 0.5);  // Idea 1: splay warm / bend cool

    // Rescue R4: HEAD saturated this at |grad theta| >= 3.3 (r <= ~0.15 per defect, summing over
    // 2-12 defects) so white blobs engulfed ~half the frame and hid the director texture.
    // CORE_GAIN 2.0 restores HEAD; 0.7 keeps the core a hot spot (|grad theta| >= 9.5).
    let singularCore = pow(clamp(defectStrength * CORE_GAIN, 0.0, 1.0), 3.0);
    color += vec3<f32>(1.0, 1.0, 0.9) * singularCore * 2.0;

    let shimmer = sin(theta * 4.0 + t * 2.0 + bass * PI) * 0.5 + 0.5;
    color += irisColor * shimmer * treble * 0.3 * orderS;  // Idea 2

    // Idea 2 — Schlieren brushes from |∇θ| along the director.
    let schlieren = abs(sin(theta * 2.0)) * smoothstep(0.08, 0.45, defectStrength);
    color = color * (1.0 - schlieren * 0.4) + irisColor * schlieren * 0.12;

    let v = 1.0 - smoothstep(0.3, 0.8, length(uv - 0.5));
    color *= v;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let presence = clamp(length(color) * 1.5, 0.0, 1.0);
    let alpha = clamp(presence * (0.7 + depth * 0.3) + schlieren * 0.15, 0.2, 0.95);

    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);
    color = acesToneMap(color * 1.1);

    let prev = textureLoad(dataTextureC, coord, 0);
    color = mix(prev.rgb * 0.97, color, 0.2 + bass * 0.1);

    let outCol = vec4<f32>(color, alpha);
    textureStore(writeTexture, coord, outCol);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outCol);
}
