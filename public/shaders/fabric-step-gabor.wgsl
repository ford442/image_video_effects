// ═══════════════════════════════════════════════════════════════════
//  Fabric Step Gabor
//  Category: advanced-hybrid
//  Features: fabric-simulation, gabor-filter, texture-analysis, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Chunks From: fabric-step.wgsl, conv-gabor-texture-analyzer.wgsl
//  Created: 2026-04-18
//  By: Agent CB-22 — Artistic & Texture Enhancer
//  Upgraded: 2026-11-09
//  Ideas: principal-strain orientation (Cauchy-Green structure tensor of the cloth rotates the Gabor bank, §12.2A); plain-weave thread lattice in material space (the bank detects thread direction, folds become visible); compression buckling shade (det J)
//  Rescue: cloth is now a coupled mass-spring displacement field (tether + isotropic 9-point Laplacian §12.2D, stretch-gated healing tear) instead of per-pixel oscillators that tore permanently
//  A packing: raw sim state — A = (d.xy, dPrev.xy) displacement OFFSETS from the rest uv (f16-safe); the pinned top rows (d = 0) carry (0, 0, 0.7371, 0.7371) as the state sentinel (inherited C is treated as an undisturbed sheet); NOT tone-mapped, ACES only on writeTexture. B = (strain, vel.xy, 1) as before
// ═══════════════════════════════════════════════════════════════════
//  Mass-spring cloth simulation deforms the image into flowing fabric
//  folds, then Gabor filter banks detect oriented texture patterns at
//  0, 45, 90, and 135 degrees across the deformed fabric. Strain
//  creates visual texture that the Gabor bank picks up as vivid
//  psychedelic orientation maps. Mouse pulls and tears the fabric.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.2831853;
const DMAX: f32 = 0.15;          // bound on the cloth displacement (also guards a previous shader's A on switch)
const GABOR_R: i32 = 4;          // Gabor support radius (HEAD: min(ceil(3*sigma), 4) = 4 at sigma 2.1)
const SIM_CELLS: f32 = 180.0;    // the cloth lives on a ~180-cell grid at every resolution
const THREAD_PX: f32 = 9.0;      // Idea 2: thread-pair period in SOURCE pixels (inside the Gabor band)
const WIND_GAIN: f32 = 0.0006;   // wind acceleration (HEAD: 0.001 as a velocity kick; the sheet is now held, so this is an acceleration)
const PUSH_GAIN: f32 = 0.0006;   // cursor push acceleration at the cursor (linear falloff to r = 0.15, as HEAD)
const STRAIN_GAIN: f32 = 2.0;    // stretch ratio - 1 that maps to full strain colour (a 50 % stretch)
const SENT: f32 = 0.7371;        // sentinel in the pinned rows' (z, w): marks A as THIS shader's cloth state

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2D(p: vec2<f32>) -> f32 {
  var i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var freq = 1.0;
  var pos = p;
  for (var i = 0; i < 4; i = i + 1) {
    value = value + amplitude * noise2D(pos * freq + vec2<f32>(time * 0.1, time * 0.15));
    freq = freq * 2.0;
    amplitude = amplitude * 0.5;
  }
  return value;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let v = max(x, vec3<f32>(0.0));
  return clamp((v * (2.51 * v + 0.03)) / (v * (2.43 * v + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Idea 2: plain-weave luminance in thread-pair units (m = material position / thread period).
// Over/under checker (diagonal energy) + round thread crowns along each axis (axis energy), so the
// four-orientation Gabor bank has real 0/45/90/135 structure to detect. Range ~0.25..1.05.
fn weaveLum(m: vec2<f32>) -> f32 {
  let c = cos(TAU * m);
  return 0.5 + 0.25 * c.x * c.y + 0.15 * (c.x + c.y);
}

// Previous cloth state at a texel: exact load, clamped to the frame and to the physical bound.
// k = 0 when C is not this shader's own state (first frame, or inherited from the previous shader):
// the sheet then starts at rest instead of reading someone else's display RGBA as displacement.
fn clothAt(c: vec2<i32>, maxC: vec2<i32>, k: f32) -> vec4<f32> {
  let t = textureLoad(dataTextureC, clamp(c, vec2<i32>(0), maxC), 0);
  return k * clamp(t, vec4<f32>(-DMAX), vec4<f32>(DMAX));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
    let coord = gid.xy;
    if (coord.x >= size.x || coord.y >= size.y) { return; }

    let res = vec2<f32>(f32(size.x), f32(size.y));
    let aspect = res.x / res.y;
    let ic = vec2<i32>(coord);
    let maxC = vec2<i32>(size) - vec2<i32>(1);
    var uv = vec2<f32>(f32(coord.x), f32(coord.y)) / res;
    let time = u.config.x;
    let dt = 0.016;

    let stiffness = mix(0.1, 0.99, u.zoom_params.x);
    let tearThreshold = mix(1.5, 4.0, u.zoom_params.y);
    let gravity = mix(0.0, 0.02, u.zoom_params.z);
    let damping = mix(0.95, 0.999, u.zoom_params.w);

    // ── Cloth state: displacement OFFSETS from the rest uv (zero state = at rest, no init branch).
    // A = (d.xy, dPrev.xy); the neighbourhood is read at a fixed ~SIM_CELLS-cell stride so the cloth
    // is the same sheet at 192 px and 1080 px (HEAD's rules were measured in texels).
    let stride = max(1, i32(round(res.y / SIM_CELLS)));
    // Rows < stride are pinned (d = 0 forever), so their (z, w) channels are free: they carry SENT.
    let tag = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let k = select(0.0, 1.0, abs(tag.z - SENT) < 0.001 && abs(tag.w - SENT) < 0.001);
    let s0 = clothAt(ic, maxC, k);
    let sE = clothAt(ic + vec2<i32>(stride, 0), maxC, k);
    let sW = clothAt(ic - vec2<i32>(stride, 0), maxC, k);
    let sS = clothAt(ic + vec2<i32>(0, stride), maxC, k);
    let sN = clothAt(ic - vec2<i32>(0, stride), maxC, k);
    let sSE = clothAt(ic + vec2<i32>(stride, stride), maxC, k);
    let sSW = clothAt(ic + vec2<i32>(-stride, stride), maxC, k);
    let sNE = clothAt(ic + vec2<i32>(stride, -stride), maxC, k);
    let sNW = clothAt(ic - vec2<i32>(stride, stride), maxC, k);
    let d = s0.xy;
    let dPrev = s0.zw;

    // Isotropic 9-point Laplacian of the displacement (§12.2D): the neighbour coupling HEAD never had.
    let lap = 0.2 * (sE.xy + sW.xy + sS.xy + sN.xy) + 0.05 * (sSE.xy + sSW.xy + sNE.xy + sNW.xy) - d;

    // ── Idea 1 input: deformation gradient J = I + grad(d) in aspect-corrected (physical) axes,
    // from the same neighbours (central differences over 2*stride cells).
    let invStep = vec2<f32>(res.x, res.y) / (2.0 * f32(stride));
    let dDx = (sE.xy - sW.xy) * invStep.x;                  // d(d)/d(uv.x)
    let dDy = (sS.xy - sN.xy) * invStep.y;                  // d(d)/d(uv.y)
    let J11 = 1.0 + dDx.x;
    let J12 = aspect * dDy.x;
    let J21 = dDx.y / aspect;
    let J22 = 1.0 + dDy.y;
    // Cauchy-Green tensor C = J^T J: its principal stretch / axis / coherence (structure-tensor row, §12.2A)
    let C11 = J11 * J11 + J21 * J21;
    let C22 = J12 * J12 + J22 * J22;
    let C12 = J11 * J12 + J21 * J22;
    let disc = sqrt(max(0.25 * (C11 - C22) * (C11 - C22) + C12 * C12, 0.0));
    let lam1 = 0.5 * (C11 + C22) + disc;
    let lam2 = max(0.5 * (C11 + C22) - disc, 0.0);
    let sMax = sqrt(max(lam1, 0.0));
    let sMin = sqrt(lam2);
    let thetaP = 0.5 * atan2(2.0 * C12, C11 - C22 + 1e-6);   // principal stretch axis
    let coherence = (lam1 - lam2) / (lam1 + lam2 + 1e-5);    // 0 = isotropic, 1 = pure uniaxial stretch
    let area = J11 * J22 - J12 * J21;                        // det J: < 1 compressed, > 1 stretched

    // Tear: where the local stretch exceeds tearThreshold (now a stretch RATIO, range kept) the tether
    // and the coupling let go. They weaken, never vanish, so a tear heals once the sheet relaxes.
    let tearW = 1.0 - smoothstep(tearThreshold, tearThreshold * 1.3, sMax);
    let hold = mix(0.15, 1.0, tearW);

    // Stiffness: how strongly the sheet holds to rest (tether) and to its neighbours (coupling).
    let kRest = 0.004 + 0.016 * stiffness;
    let kStruct = 0.5 * stiffness;          // <= 0.5: explicit Verlet with the 9-point stencil stays stable
    var acc = (-kRest * d + kStruct * lap) * hold;

    // Gravity (acceleration, as HEAD: gravity * dt per frame)
    acc.y = acc.y + gravity * dt;

    // Mouse interaction: the cursor pushes the cloth away inside r = 0.15 (aspect-corrected, HEAD's was elliptical)
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let posNow = uv + d;
    let toMouseA = (posNow - mouse) * vec2<f32>(aspect, 1.0);
    let mouseDist = length(toMouseA);
    let mouseInfluenceRadius = 0.15;
    if (mouseDist < mouseInfluenceRadius && mouseDist > 0.001) {
        let force = (1.0 - mouseDist / mouseInfluenceRadius) * PUSH_GAIN;
        acc = acc + (toMouseA / mouseDist) / vec2<f32>(aspect, 1.0) * force;
    }

    // Wind force
    let windX = fbm(posNow * 4.0 + vec2<f32>(time * 0.5, 0.0), time) - 0.5;
    let windY = fbm(posNow * 4.0 + vec2<f32>(0.0, time * 0.5), time) - 0.5;
    acc = acc + vec2<f32>(windX, windY) * WIND_GAIN;

    // Verlet step
    var dNew = d + (d - dPrev) * damping + acc;
    dNew = clamp(dNew, vec2<f32>(-DMAX), vec2<f32>(DMAX));

    // Pin top edge
    if (ic.y < stride) {
        dNew = vec2<f32>(0.0);
    }
    var pos = clamp(uv + dNew, vec2<f32>(0.0), vec2<f32>(1.0));
    let vel = dNew - d;

    // Store state (raw offsets: never tone-mapped)
    textureStore(dataTextureA, ic, select(vec4<f32>(dNew, d), vec4<f32>(0.0, 0.0, SENT, SENT), ic.y < stride));

    // Strain: real stretch / compression of the sheet (HEAD used |pos - uv| * 50, i.e. displacement,
    // which saturated everywhere and painted the whole frame)
    let strain = clamp(max(sMax - 1.0, 1.0 - sMin) * STRAIN_GAIN, 0.0, 1.0);
    textureStore(dataTextureB, ic, vec4<f32>(strain, vel, 1.0));

    // Sample source at deformed position
    let sourceColor = textureSampleLevel(readTexture, u_sampler, pos, 0.0);

    // ═══ GABOR TEXTURE ANALYSIS ON FABRIC ═══
    let pixelSize = 1.0 / res;
    let freq = mix(0.05, 0.25, 0.3 + strain * 0.4);
    let sigma = mix(1.5f, 3.0f, 0.4f);
    let responseScale = mix(0.5, 2.0, 0.5 + strain);

    // ── Idea 1: the bank is rotated onto the cloth's principal stretch axis (weighted by how uniaxial
    // the stretch is and by the strain itself). HEAD: atan2(vel) * strain * 2 — a velocity angle.
    // sin(2*theta) has the old slope (2) at small angles but is pi-periodic like the stretch AXIS itself:
    // the bank no longer jumps where atan2 wraps from +pi/2 to -pi/2.
    let strainAngle = sin(2.0 * thetaP) * coherence * strain;
    let rotationOffset = strainAngle + time * 0.05;

    let th0 = rotationOffset;
    let th1 = 0.785398 + rotationOffset;
    let th2 = 1.570796 + rotationOffset;
    let th3 = 2.356194 + rotationOffset;
    let cs0 = vec2<f32>(cos(th0), sin(th0));
    let cs1 = vec2<f32>(cos(th1), sin(th1));
    let cs2 = vec2<f32>(cos(th2), sin(th2));
    let cs3 = vec2<f32>(cos(th3), sin(th3));
    let twoSig2 = 2.0 * sigma * sigma + 0.001;
    let wFreq = TAU * freq;
    let mScale = res / THREAD_PX;

    // Same 9x9 kernels as HEAD (gaussian * cosine, luma taps) but the neighbourhood is fetched ONCE and
    // shared by the four orientations (HEAD re-fetched it per orientation: 4x the texture samples).
    var g0 = 0.0;
    var g1 = 0.0;
    var g2 = 0.0;
    var g3 = 0.0;
    for (var dy = -GABOR_R; dy <= GABOR_R; dy = dy + 1) {
        for (var dx = -GABOR_R; dx <= GABOR_R; dx = dx + 1) {
            let x = f32(dx);
            let y = f32(dy);
            let gaussian = exp(-(x * x + y * y) / twoSig2);
            let tapUV = pos + vec2<f32>(x, y) * pixelSize;
            var luma = dot(textureSampleLevel(readTexture, u_sampler, tapUV, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
            // Idea 2: the thread lattice is part of what the bank sees (material coords = source position)
            luma = luma * (1.0 + (weaveLum(tapUV * mScale) - 0.55) * 0.3);
            let lg = luma * gaussian;
            g0 = g0 + lg * cos(wFreq * (x * cs0.x + y * cs0.y));
            g1 = g1 + lg * cos(wFreq * (x * cs1.x + y * cs1.y));
            g2 = g2 + lg * cos(wFreq * (x * cs2.x + y * cs2.y));
            g3 = g3 + lg * cos(wFreq * (x * cs3.x + y * cs3.y));
        }
    }
    let r0 = g0 * responseScale;
    let r45 = g1 * responseScale;
    let r90 = g2 * responseScale;
    let r135 = g3 * responseScale;

    // Psychedelic palette mapping
    let pal0 = palette(r0 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    let pal45 = palette(r45 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0));
    let pal90 = palette(r90 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33));
    let pal135 = palette(r135 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.67, 0.33));

    var gaborColor = vec3<f32>(0.0);
    gaborColor += pal0 * abs(r0);
    gaborColor += pal45 * abs(r45);
    gaborColor += pal90 * abs(r90);
    gaborColor += pal135 * abs(r135);
    let totalResponse = abs(r0) + abs(r45) + abs(r90) + abs(r135) + 0.001;
    gaborColor = gaborColor / totalResponse;
    gaborColor = gaborColor * 1.3;

    // Idea 2: the cloth itself shows its threads (material coords again), more openly where it is
    // stretched (threads spread) — the folds of a smooth photo are otherwise nearly invisible.
    let weaveHere = weaveLum(pos * mScale);
    let threadShade = 1.0 + (weaveHere - 0.55) * mix(0.14, 0.30, strain);
    let clothColor = sourceColor.rgb * threadShade;

    // Blend Gabor analysis with source color based on strain
    let fabricColor = mix(clothColor, gaborColor, strain * 0.7);

    // Strain color visualization
    let strainColor = mix(
        vec3<f32>(0.2, 0.4, 0.8),
        vec3<f32>(1.0, 0.3, 0.1),
        strain
    );
    var finalColor = mix(fabricColor, strainColor, strain * 0.2);

    // ── Idea 3: compression buckling. Where the sheet is squeezed (det J < 1) it bunches into a
    // wrinkle valley (darker); where it is pulled open (det J > 1) the threads spread and let light
    // through (slightly lifted). Both come from the same J, no new state.
    let buckle = clamp((1.0 - area) * 2.5, 0.0, 1.0);
    let spread = clamp((area - 1.0) * 2.5, 0.0, 1.0);
    finalColor = finalColor * (1.0 - 0.38 * buckle + 0.12 * spread);

    // Fabric alpha based on strain
    let fabricAlpha = mix(0.9, 0.7, strain * 0.5);

    textureStore(writeTexture, ic, vec4<f32>(aces(finalColor), fabricAlpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, pos, 0.0).r;
    textureStore(writeDepthTexture, ic, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
