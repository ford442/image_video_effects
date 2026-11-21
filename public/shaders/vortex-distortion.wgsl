// ═══════════════════════════════════════════════════════════════════════════════
//  Lamb-Oseen Vortex Fluid with Kelvin-Helmholtz Shear Instability
//  Category: distortion
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-08, 2026-11-21
//  Ideas: streamline smear along velocity; source-tied vorticity overlay; vorticity confinement (§12.2D); MacCormack backtrace correction (§12.2D)
//  A packing: raw field (vel.xy, vorticity, speed) — never ACES
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Circulation, y=Viscosity, z=KHAmplitude, w=Aberration

// Lamb-Oseen azimuthal velocity: u_θ = Γ/(2πr) · (1 − exp(−r²/(4νt)))
fn lambOseen(p: vec2<f32>, center: vec2<f32>, circulation: f32, nu: f32, age: f32) -> vec2<f32> {
    let d    = p - center;
    let r    = length(d);
    if (r < 0.0001) { return vec2<f32>(0.0); }
    let r2   = r * r;
    let t    = max(age, 0.001);
    // Azimuthal velocity magnitude
    let uTheta = (circulation / (6.28318 * r)) * (1.0 - exp(-r2 / (4.0 * nu * t)));
    // Tangential direction (perpendicular to radial)
    let tangent = vec2<f32>(-d.y, d.x) / r;
    return tangent * uTheta;
}

// ── Idea 1 helper: closed-form Lamb-Oseen vorticity, promoted from the same Gaussian lambOseen uses ──
//   rc² = 4νt,  ω = Γ/(π rc²)·exp(−r²/rc²),  ∇ω = −2·d·ω/rc².   Returns (ω, ω·rc, ∇ω.x, ∇ω.y).
fn lambOseenOmega(p: vec2<f32>, center: vec2<f32>, circulation: f32, nu: f32, age: f32) -> vec4<f32> {
    let d   = p - center;
    let rc2 = 4.0 * nu * max(age, 0.001);
    let w   = circulation / (3.14159265 * rc2) * exp(-dot(d, d) / rc2);
    return vec4<f32>(w, w * sqrt(rc2), d * (-2.0 * w / rc2));
}

// Rescue R1: HEAD fed the mouse vortex `time*0.1` on the app's global clock, so its viscous core
// sqrt(4νt) grew without bound and the pointer vortex spun down to nothing within minutes. Axial strain
// (Burgers vortex, a = 0.4) arrests the spreading: t_eff = (1 − e^(−2at)) / (2a). ≈ HEAD for t ≲ 0.5,
// saturates at 1.25, so the core stays finite and the swirl keeps its strength.
fn burgersAge(t: f32) -> f32 {
    return (1.0 - exp(-0.8 * t)) / 0.8;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Kelvin-Helmholtz sinusoidal perturbation at shear radius
fn khPerturbation(p: vec2<f32>, center: vec2<f32>, shearR: f32, amplitude: f32, time: f32) -> vec2<f32> {
    let d  = p - center;
    let r  = length(d);
    // KH instability is strongest at the viscous core radius
    let envelope = exp(-abs(r - shearR) * abs(r - shearR) / (shearR * shearR * 0.1));
    let angle    = atan2(d.y, d.x);
    // Sinusoidal instability at azimuthal wavenumber m=6
    let perturb  = amplitude * envelope * sin(angle * 6.0 + time * 3.0) * 0.01;
    return normalize(d + vec2<f32>(0.0001)) * perturb;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let aspect = resolution.x / resolution.y;
    let bass   = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;

    let circulation = mix(-8.0, 8.0, u.zoom_params.x);  // Γ, signed (CW vs CCW)
    let nu          = mix(0.0005, 0.02, u.zoom_params.y); // kinematic viscosity
    let khAmp       = mix(0.0, 1.0, u.zoom_params.z) * (1.0 + bass * 0.5);
    let aberration  = u.zoom_params.w * 0.03;

    var p = vec2<f32>(uv.x * aspect, uv.y);

    // ─── Sum velocity from all active vortices (ripple history) ───
    var vel      = vec2<f32>(0.0);
    var vorticity = 0.0;
    let numV     = min(i32(u.config.y), 20);   // cap at 20 vortices for performance

    // Always include mouse vortex
    var mouseCenter = u.zoom_config.yz;
    mouseCenter.x *= aspect;
    let mouseAge  = burgersAge(time * 0.1);
    let mouseCirc = circulation * (1.0 + bass * 0.3);
    let mouseV = lambOseen(p, mouseCenter, mouseCirc, nu, mouseAge + 0.001);
    vel += mouseV;
    // KH instability at viscous core
    let coreR = sqrt(4.0 * nu * max(mouseAge, 0.001));
    vel += khPerturbation(p, mouseCenter, coreR, khAmp, time);

    // Idea 1 accumulators: Σω (signed), Σ∇ω, Σ|ω|, Σ|ω|·rc over the SAME vortices as the velocity sum.
    let mouseO = lambOseenOmega(p, mouseCenter, mouseCirc, nu, mouseAge + 0.001);
    var omegaSum   = mouseO.x;
    var omegaAbs   = abs(mouseO.x);
    var omegaAbsRc = abs(mouseO.y);
    var gradOmega  = mouseO.zw;

    for (var i = 0; i < 20; i++) {
        if (i >= numV) { break; }
        let rip = u.ripples[i];
        let src = vec2<f32>(rip.x * aspect, rip.y);
        let age = time - rip.z;
        if (age < 0.0 || age > 6.0) { continue; }
        // Alternate CW / CCW for visual variety
        let circ = circulation * select(-0.6, 0.6, (i & 1) == 0) * exp(-age * 0.3);
        vel += lambOseen(p, src, circ, nu, age + 0.001);
        let vcore = sqrt(4.0 * nu * (age + 0.001));
        vel += khPerturbation(p, src, vcore, khAmp * exp(-age * 0.4), time);
        let o = lambOseenOmega(p, src, circ, nu, age + 0.001);
        omegaSum   += o.x;
        omegaAbs   += abs(o.x);
        omegaAbsRc += abs(o.y);
        gradOmega  += o.zw;
    }

    // ── Idea 1: vorticity confinement (§12.2D) ────────────────────────────────
    // Viscosity smooths the vorticity peak; confinement re-injects the lost small-scale rotation:
    //   f = ε·h·(N × ω), N = ∇|ω|/|∇ω|.  ω·N = |ω|·∇ω/|∇ω| (no sign flip where opposite vortices meet).
    // h is the vorticity-weighted core radius; the normaliser ramps N linearly to 0 over r < rc and in
    // the far field (a steeper ramp left a thin chromatic fold sliver in a young click vortex's eye).
    // Per vortex this is a Gaussian core spin-up (~+20% at r = rc at the saved viscosity, far-field
    // circulation unchanged); because N comes from the SUM, overlapping click vortices bind.
    // Γ = 0 → ω = 0 → no change. ε rides the Viscosity role (more smoothing → more re-concentration).
    let confEps = mix(0.1, 0.35, u.zoom_params.y);
    let hBar    = omegaAbsRc / max(omegaAbs, 1e-9);
    let gLen    = length(gradOmega);
    let gHat    = gradOmega / max(max(gLen, 2.0 * abs(omegaSum) / max(hBar, 1e-4)), 1e-9);
    vel += confEps * abs(omegaSum) * hBar * vec2<f32>(gHat.y, -gHat.x);

    // Approximate vorticity: ω ≈ |∇×v| from circulation strength
    vorticity = length(vel) * sign(circulation);

    // ─── Displace sample UV ───
    let speed  = length(vel);
    let uvOff = vec2<f32>(vel.x / aspect, vel.y) * 0.04;

    // ── Idea 2: MacCormack round-trip correction of the backtrace (§12.2D) ────────
    // One Euler step along the tangent drifts outward from the arc a real rotation follows
    // (|x_d| = |x|·√(1+θ²) for a turn of θ per step). MacCormack estimates the advection error by running
    // the step back from the forward point and halving it. Applied to the trajectory (the value form
    // ½(S(uv) − S(round trip)) on a STATIC source image only adds ghost edges of the undisplaced picture
    // where the round-trip error is large, and nothing where it is small), the corrected departure point is
    //   x_d = uv − off(v(uv)) + ½·(off(v(uv + off)) − off(v(uv)))   ≈  x − v + ½(∇v)v   (RK2),
    // which cancels the outward drift (|x_d|² = |x|²(1 + θ⁴/4)). v at the forward point is an EXACT load of
    // last frame's raw field (C = this shader's own A: .xy = vel, .w = speed), so no second vortex sum and
    // no extra texture tap. No history (frame 0 / cleared C) → uniform-velocity fallback → correction 0.
    let uvFwd  = uv + uvOff;
    let maxPx  = vec2<i32>(resolution) - vec2<i32>(1);
    let histY  = textureLoad(dataTextureC, clamp(vec2<i32>(clamp(uvFwd, vec2<f32>(0.0), vec2<f32>(0.999999)) * resolution), vec2<i32>(0), maxPx), 0);
    let velY   = mix(vel, histY.xy, select(0.0, 1.0, histY.w > 1.0e-4));
    let uvOffY = vec2<f32>(velY.x / aspect, velY.y) * 0.04;
    var rtCorr = 0.5 * (uvOffY - uvOff);
    // Never move the departure point by more than half the Euler step (stale C after a pointer jump).
    rtCorr = rtCorr * min(1.0, 0.5 * length(uvOff) / max(length(rtCorr), 1.0e-9));
    let uvBase = uv - uvOff + rtCorr;

    // Streamline smear: a few taps along velocity (advection, not a new solver).
    let stepV = uvOff * 0.45;
    // Tap 0 of the smear is the same texel as sG (both at clamp(uvBase)); HEAD fetched it twice. Fetch once.
    let sG  = textureSampleLevel(readTexture, u_sampler, clamp(uvBase, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
    var smear = sG.rgb;
    for (var s = 1; s < 4; s++) {
        let suv = clamp(uvBase - stepV * f32(s), vec2<f32>(0.001), vec2<f32>(0.999));
        smear += textureSampleLevel(readTexture, u_sampler, suv, 0.0).rgb;
    }
    smear = smear * 0.25;
    let uvR    = uvBase + vec2<f32>(aberration, 0.0);
    let uvB    = uvBase - vec2<f32>(aberration, 0.0);
    let sR  = textureSampleLevel(readTexture, u_sampler, clamp(uvR, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
    let sB  = textureSampleLevel(readTexture, u_sampler, clamp(uvB, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
    var color = mix(vec3<f32>(sR.r, sG.g, sB.b), smear, clamp(speed * 0.55, 0.0, 0.65));

    let vNorm = clamp(vorticity, -1.0, 1.0);
    let vCol  = mix(
        mix(vec3<f32>(0.1, 0.3, 1.0), vec3<f32>(0.0, 0.8, 0.3), 0.5 + vNorm * 0.5),
        vec3<f32>(1.0, 0.15, 0.05),
        clamp(vNorm, 0.0, 1.0)
    );
    let sourceLuma = dot(sG.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let vIntensity = smoothstep(0.0, 0.5, speed) * 0.35 * mix(0.35, 1.0, sourceLuma);
    color = mix(color, vCol, vIntensity);

    color += vec3<f32>(1.0, 0.8, 0.5) * clamp(speed - 0.3, 0.0, 0.5) * 0.4;

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthUncertainty = speed * 0.08;
    let alpha = clamp(0.2 + speed * 0.7 + abs(vorticity) * 0.15, 0.12, 1.0);
    let pixel = vec2<i32>(global_id.xy);
    textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(vel.x, vel.y, vorticity, speed));
    textureStore(writeDepthTexture, pixel,
        vec4<f32>(d * (1.0 + depthUncertainty), 0.0, 0.0, 0.0));
}

