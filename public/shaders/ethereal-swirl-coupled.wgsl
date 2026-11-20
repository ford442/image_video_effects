// ═══════════════════════════════════════════════════════════════════
//  ethereal-swirl-coupled
//  Category: advanced-hybrid
//  Features: fluid-coupling, fractal-swirl, temporal, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Very High
//  Chunks From: ethereal-swirl.wgsl, mouse-fluid-coupling.wgsl
//  Created: 2026-04-18
//  By: Agent CB-19 — Lighting & Energy Enhancer
//  Upgraded: 2026-11-20
//  Ideas: two-way swirl-fluid coupling (swirl wind body force, cloud-seeded dye); dye-gradient refraction of the photo (§12.2F Snell); curl-tinted hue (§12.2D real vorticity)
//  A packing: A = (vel.x, vel.y, display-luma history, dye density); texel (0,0) = (mouse.xy, 0, 0). ACES display RGB, alpha = swirl/dye coverage
// ═══════════════════════════════════════════════════════════════════
//  Ethereal swirling clouds coupled with viscous fluid dynamics.
//  Mouse drags fluid that advects the fractal swirl field, creating
//  vortex streets and silky color-absorption trails in the dreamscape.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Smooth noise has less variance than white noise; this restores the swing the
// cloud thresholds below were tuned against.
const FBM_GAIN: f32 = 1.0;
// Idea 1: swirl wind body force and cloud->dye seeding rate.
const WIND: f32 = 0.05;
const DYE_SEED: f32 = 0.012;
// Idea 2: dye-gradient refraction, in pixels per unit of dye-density-per-pixel.
const REFRACT_PX: f32 = 90.0;

// ═══ CHUNK: hash2 (from ethereal-swirl.wgsl) ═══
fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(123.456, 789.012));
    p2 = p2 + dot(p2, p2 + 45.678);
    return fract(p2.x * p2.y);
}

// Rescue: HEAD hashed the continuous coordinate (per-pixel white noise, so the
// "clouds" were grain). Smooth value noise on an integer lattice instead —
// body-identical to ethereal-swirl.wgsl's vnoise.
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// ═══ CHUNK: fbm (from ethereal-swirl.wgsl) — centred on 0 like HEAD ═══
// Octave count is a per-call budget: the domain warps (baseFlow, turb) only need the
// low octaves, the cloud layers keep the full 5 / 4. Smooth noise costs more per octave
// than HEAD's single hash, so the warp octaves that nobody can see were trimmed.
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 2.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        let n = vnoise(p * freq + vec2<f32>(f32(i) * 17.3, f32(i) * 9.1));
        value = value + amp * (n - 0.5);
        freq = freq * 2.1;
        amp = amp * 0.5;
    }
    return value * FBM_GAIN;
}

// ═══ CHUNK: hsv2rgb (from ethereal-swirl.wgsl) ═══
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let c = max(x, vec3<f32>(0.0));
    return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Exact history read: bilinear by hand from four textureLoads (no sampler on rgba32float),
// so sub-pixel advection still moves the trail. Body-identical to ethereal-swirl.wgsl.
fn loadHistory(pos: vec2<f32>, dims: vec2<f32>) -> vec4<f32> {
    let maxC = vec2<i32>(dims) - vec2<i32>(1);
    let px = clamp(pos * dims - 0.5, vec2<f32>(0.0), dims - 1.0);
    let i0 = vec2<i32>(floor(px));
    let i1 = min(i0 + vec2<i32>(1), maxC);
    let f = px - floor(px);
    let c00 = textureLoad(dataTextureC, i0, 0);
    let c10 = textureLoad(dataTextureC, vec2<i32>(i1.x, i0.y), 0);
    let c01 = textureLoad(dataTextureC, vec2<i32>(i0.x, i1.y), 0);
    let c11 = textureLoad(dataTextureC, i1, 0);
    return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

// Fluid state of the stored field at an integer texel. Texel (0,0) of A holds the mouse
// history, not fluid, so it reads as still, dye-free water.
fn fluidAt(c: vec2<i32>, maxC: vec2<i32>) -> vec4<f32> {
    let cc = clamp(c, vec2<i32>(0), maxC);
    let v = textureLoad(dataTextureC, cc, 0);
    return select(v, vec4<f32>(0.0), all(cc == vec2<i32>(0)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let ci = vec2<i32>(gid.xy);
    let maxC = vec2<i32>(res) - vec2<i32>(1);
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let aspect = res.x / res.y;
    let asp = vec2<f32>(aspect, 1.0);   // noise lives in aspect-correct space
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Parameters
    let cloudScale = u.zoom_params.x * 7.0 + 1.0;
    let flowSpeed = u.zoom_params.y * 0.4;
    let colorSpeed = u.zoom_params.z * 0.2;
    let persistence = clamp(u.zoom_params.w * 0.95, 0.0, 0.95);
    let viscosity = mix(0.92, 0.99, u.zoom_params.x);
    let mouseRadius = mix(0.03, 0.15, u.zoom_params.y);
    let colorShift = u.zoom_params.z;
    let vortexStrength = u.zoom_params.w * 2.0 * (1.0 + bass * 0.4);   // bass kicks the stir harder
    // Mids push the flow phase forward additively (never scales absolute time).
    let flowT = time * flowSpeed + mids * 0.15;

    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // The four neighbours of the stored fluid field feed two ideas at once: the real curl of
    // the velocity (Idea 3) and the dye-density gradient (Idea 2). Exact loads.
    let nR = fluidAt(ci + vec2<i32>(1, 0), maxC);
    let nL = fluidAt(ci + vec2<i32>(-1, 0), maxC);
    let nT = fluidAt(ci + vec2<i32>(0, -1), maxC);
    let nB = fluidAt(ci + vec2<i32>(0, 1), maxC);
    let curl = 0.5 * ((nR.y - nL.y) - (nB.x - nT.x));                   // dv_y/dx - dv_x/dy
    let gradDye = 0.5 * vec2<f32>(nR.w - nL.w, nB.w - nT.w);            // per pixel

    // ── Idea 2: dye-gradient refraction (§12.2F Snell) ─────────────────
    // A dye filament is a refractive interface: the photo seen through it is bent along the
    // density gradient (schlieren at the filament edge). Reads the dye field already stored.
    let refrUV = clamp(uv - gradDye * REFRACT_PX / res, vec2<f32>(0.0), vec2<f32>(1.0));
    let srcColor = textureSampleLevel(readTexture, u_sampler, refrUV, 0.0).rgb;
    let luminance = dot(srcColor, vec3<f32>(0.2126, 0.7152, 0.0722));

    // ═══ Fluid coupling (from mouse-fluid-coupling) ═══
    // Texel (0,0) of A is the single-writer mouse history. HEAD overwrote it with fluid
    // state a few lines later, so prevMouse was always ~0 and the cursor injected maximum
    // velocity just by hovering. An all-zero history (first frame) means "no history".
    let mousePos = u.zoom_config.yz;
    let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
    let haveMouse = select(0.0, 1.0, dot(prevMouse, prevMouse) > 0.0);
    let mouseVel = (mousePos - prevMouse) * 60.0 * haveMouse;
    let mouseSpeed = length(mouseVel);

    let px = vec2<f32>(1.0) / res;
    let prevVel = textureLoad(dataTextureC, ci, 0).xy;

    let backUV = uv - prevVel * px * 2.0;
    let adv = loadHistory(backUV, res);

    var vel = adv.xy * viscosity;
    var dens = adv.w * viscosity;
    let histLuma = adv.z;   // display luma of the previous frame, advected with the fluid

    let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(toMouse);
    let influence = smoothstep(mouseRadius, 0.0, dist);
    vel = vel + mouseVel * influence * 0.5;

    let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
    vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;

    // Click ripples
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 2.0) {
            let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let rDist = length(rToMouse);
            let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
            let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
            vel = vel + outward * rInfluence * 0.3;
            dens = dens + rInfluence * 0.5;
        }
    }

    let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
    vel = vel * edgeDamp;
    vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
    dens = clamp(dens, 0.0, 2.0);

    // ═══ Ethereal swirl (from ethereal-swirl) ═══
    let baseFlow = vec2<f32>(
        fbm(uv * asp * cloudScale * 0.3 + vec2<f32>(flowT * 0.1, 0.0), 3),
        fbm(uv * asp * cloudScale * 0.3 + vec2<f32>(0.0, flowT * 0.15), 3)
    );
    let turb = vec2<f32>(
        fbm(uv * asp * cloudScale * 1.2 + baseFlow * 2.5 + vec2<f32>(flowT * 0.2, 0.0), 4),
        fbm(uv * asp * cloudScale * 1.2 + baseFlow * 2.5 + vec2<f32>(0.0, flowT * 0.25), 4)
    );
    let turbulenceAmt = 0.15;
    let flowVec = baseFlow * 0.2 + turb * turbulenceAmt;
    let depthWarp = depthVal * 0.05;
    let distortedUV = uv + flowVec + depthWarp * flowVec + vel * 0.5;

    let cloudBase = fbm(distortedUV * asp * cloudScale, 5);
    let cloudDetail = fbm(distortedUV * asp * cloudScale * 3.0 + vec2<f32>(time * 0.1, time * 0.07), 4);
    let cloudRaw = mix(cloudBase, cloudDetail, 0.5);
    let cloudDensity = smoothstep(0.2, 0.7, abs(cloudRaw) * 3.0);

    // ── Idea 3: curl-tinted hue (§12.2D) ──────────────────────────────
    // HEAD stored a fake "vorticity" (vel.x - vel.y) that nothing read. The real curl of the
    // stored velocity shifts the cloud hue, so vortex cores and streets read as colour.
    let curlTint = clamp(curl * res.y * 0.08, -0.15, 0.15);
    let baseHue = fract(distortedUV.x + distortedUV.y * 0.3 + time * colorSpeed);
    let hue = fract(baseHue + cloudDensity * 0.2 + curlTint);
    let sat = mix(0.6, 1.0, luminance);
    let val = mix(0.4, 1.0, luminance);
    let cloudColor = hsv2rgb(hue, sat, val);

    let blendStr = 0.5;
    let swirlCover = cloudDensity * smoothstep(0.1, 0.5, luminance);
    let blendFactor = swirlCover * blendStr;
    var blendedColor = mix(srcColor, cloudColor, blendFactor);

    // ── Idea 1: two-way coupling (swirl <-> fluid) ──────────────────────
    // HEAD only ever fed the fluid into the swirl. flowVec and cloudDensity are computed
    // every frame and thrown away: let the swirl's own wind stir the fluid and let the
    // visible cloud seed dye, so the "coupled" in the name holds with the cursor at rest.
    var velOut = vel + flowVec * WIND * edgeDamp;
    velOut = clamp(velOut, vec2<f32>(-0.5), vec2<f32>(0.5));
    let densOut = clamp(dens + swirlCover * DYE_SEED, 0.0, 2.0);

    // Fluid color absorption
    let blurAmount = densOut * colorShift * 0.02;
    let blurUV = uv + vel * blurAmount * 5.0;
    let fluidColor = textureSampleLevel(readTexture, u_sampler, blurUV, 0.0).rgb;
    let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), densOut * colorShift);
    blendedColor = mix(blendedColor, fluidColor * fluidTint, densOut * 0.3);

    // ACES on display RGB. Persistence trails the display luma along the flow (HEAD blended
    // the velocity field in as "previous colour", i.e. faded the picture toward black).
    let lumaW = vec3<f32>(0.2126, 0.7152, 0.0722);
    let display = acesToneMap(blendedColor * 1.1);
    let lumaNow = dot(display, lumaW);
    let trailLuma = select(mix(lumaNow, histLuma, persistence), lumaNow, histLuma <= 0.0);
    let finalColor = min(display * clamp(trailLuma / max(lumaNow, 0.04), 0.0, 3.0), vec3<f32>(1.0));
    let lumaOut = dot(finalColor, lumaW);

    // A = (vel, display-luma history, dye); texel (0,0) is the single-writer mouse history.
    if (gid.x == 0u && gid.y == 0u) {
        textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
    } else {
        textureStore(dataTextureA, ci, vec4<f32>(velOut, lumaOut, densOut));
    }

    let coverage = clamp(0.6 + 0.3 * swirlCover + 0.4 * densOut, 0.0, 1.0);
    textureStore(writeTexture, ci, vec4<f32>(finalColor, coverage));
    textureStore(writeDepthTexture, ci, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
