// ═══════════════════════════════════════════════════════════════════════════════
//  Gravitational Lens
//  Category: artistic
//  Features: mouse-driven, audio-reactive, relativistic, hdr
//  Complexity: High
//  Upgraded: 2026-11-20
//  Ideas: critical-curve magnification glow (§12.2F); Doppler-beamed accretion disk (§12.2F blackbody)
//  A packing: display RGBA (tone-mapped; alpha = lens coverage / emission)
// ═══════════════════════════════════════════════════════════════════════════════
//  distortion_gravitational_lens.wgsl - Einstein Ring Gravitational Lensing
//
//  Agent: Algorithmist + Visualist
//  Techniques:
//    - Schwarzschild metric ray deflection
//    - Einstein ring formation
//    - Multiple mass points (galaxy cluster)
//    - Accretion disk visualization
//
//  Target: 4.7★ rating
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

// Mass structure for lensing
struct Mass {
    pos: vec2<f32>,
    mass: f32,
    radius: f32, // Schwarzschild radius proxy
};

// Gravitational deflection angle
// Simplified Schwarzschild deflection: alpha = 4GM/(c^2 * b)
// where b is impact parameter:  alpha = -normalize(delta) * M R / (dist + 0.001),
// zero inside 0.1 R (singularity cutoff). Written below as alpha = -delta * g(r),
// g = K / (r (r + 0.001)), K = M R - the identical law, in a form whose derivative
// is free (Idea 1) so one sqrt / reciprocal serves both (HEAD paid sqrt + normalize).
struct LensTerm {
    alpha: vec2<f32>,   // deflection (toward the mass), HEAD's deflectionAngle
    jac: vec3<f32>,     // d alpha / d theta as (Axx, Axy, Ayy)
};

// ── Idea 1 helper: lens Jacobian of one mass ───────────────────────────────
// d alpha / d theta = -(g I + (g'/r) delta delta^T); its determinant combination
// det(I - A/2) = 0 is the critical curve (the Einstein ring).
fn lensAt(rayPos: vec2<f32>, mass: Mass) -> LensTerm {
    let delta = rayPos - mass.pos;
    let dist = sqrt(dot(delta, delta));
    let live = step(mass.radius * 0.1, dist);          // HEAD's singularity cutoff
    let r = max(dist, 1e-4);
    let K = mass.mass * mass.radius;
    let inv = 1.0 / (r * (r + 0.001));
    let g = K * inv;
    let c = -K * (2.0 * r + 0.001) * inv * inv / r;    // g'(r) / r
    var t: LensTerm;
    t.alpha = -delta * (g * live);
    t.jac = live * vec3<f32>(-(g + c * delta.x * delta.x),
                             -(c * delta.x * delta.y),
                             -(g + c * delta.y * delta.y));
    return t;
}

// One bounds-masked tap (HEAD returned black outside the image; same result, branchless,
// and the mask doubles as lens coverage for the alpha)
fn lensTap(p: vec2<f32>) -> vec4<f32> {
    let inb = f32(all(p >= vec2<f32>(0.0)) && all(p <= vec2<f32>(1.0)));
    let rgb = textureSampleLevel(readTexture, u_sampler, clamp(p, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    return vec4<f32>(rgb * inb, inb);
}

// Accretion disk temperature coloring (blackbody)
fn accretionDiskColor(radius: f32, innerRadius: f32, doppler: f32) -> vec3<f32> {
    // Temperature falls off as r^(-3/4) for thin disk
    // ── Idea 2: observed T = D * T_emitted (doppler = 1 reproduces the symmetric disk)
    let temp = pow(innerRadius / radius, 0.75) * doppler;
    
    // Blackbody approximation
    var color: vec3<f32>;
    if (temp > 0.8) {
        color = vec3<f32>(1.0, 0.9, 0.8); // White-hot
    } else if (temp > 0.6) {
        color = vec3<f32>(1.0, 0.6, 0.3); // Orange
    } else if (temp > 0.4) {
        color = vec3<f32>(0.8, 0.2, 0.1); // Red
    } else {
        color = vec3<f32>(0.3, 0.05, 0.05); // Dark red
    }
    
    // Intensity ~ T^2 (Stefan-Boltzmann-ish); the extra D makes it I_obs = D^3 I_em
    return color * temp * temp * doppler;
}

// Tone mapping
fn toneMap(x: vec3<f32>) -> vec3<f32> {
    return x / (1.0 + x * 0.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let lensStrength = 0.5 + u.zoom_params.x;         // 0.5-1.5
    let numMasses = i32(u.zoom_params.y * 4.0) + 1;   // 1-5
    let diskIntensity = u.zoom_params.z;              // 0-1
    let aberration = u.zoom_params.w * 0.05;          // 0-0.05 (chromatic)
    
    // Mouse position as primary mass
    let mousePos = u.zoom_config.yz;
    // Rescue: HEAD read zoom_config.w (mouse_down) as "audioPulse". The click
    // keeps its HEAD role (feeds the hole, pumps the disk); audio is bass now.
    let held = u.zoom_config.w;
    let bass = plasmaBuffer[0].x;

    // Define masses
    var masses: array<Mass, 5>;
    masses[0] = Mass(mousePos, 2.0 + held * 2.0 + bass * 0.8, 0.02 * lensStrength);

    // Additional orbiting masses
    for (var i: i32 = 1; i < 5; i = i + 1) {
        if (i < numMasses) {
            let fi = f32(i);
            let angle = time * 0.2 + fi * (2.0 * PI / f32(numMasses - 1));
            let radius = 0.2 + fi * 0.1;
            masses[i] = Mass(
                vec2<f32>(
                    mousePos.x + cos(angle) * radius,
                    mousePos.y + sin(angle) * radius
                ),
                0.5,
                0.01 * lensStrength
            );
        }
    }

    // Ray starting position (screen space)
    var rayPos = uv;

    // Accumulate deflections from all masses (+ the Jacobian they imply)
    var totalDeflection = vec2<f32>(0.0);
    var jac = vec3<f32>(0.0);
    for (var i: i32 = 0; i < numMasses; i = i + 1) {
        let term = lensAt(rayPos, masses[i]);
        totalDeflection += term.alpha;
        jac += term.jac;
    }

    // Apply deflection to get source position
    let sourcePos = rayPos - totalDeflection * 0.5;

    // Chromatic aberration: different deflection per channel
    let deflectionR = totalDeflection * (1.0 + aberration);
    let deflectionB = totalDeflection * (1.0 - aberration);
    let sourcePosR = rayPos - deflectionR * 0.5;
    let sourcePosG = sourcePos;
    let sourcePosB = rayPos - deflectionB * 0.5;

    // d(sourcePos)/d(uv) = I - 0.5 A, the lens Jacobian (symmetric) used by Idea 1
    let jxx = 1.0 - 0.5 * jac.x;
    let jxy = -0.5 * jac.y;
    let jyy = 1.0 - 0.5 * jac.z;

    // Sample background with lensing
    let tapR = lensTap(sourcePosR);
    let tapG = lensTap(sourcePosG);
    let tapB = lensTap(sourcePosB);
    var color = vec3<f32>(tapR.r, tapG.g, tapB.b);
    let coverage = (tapR.a + tapG.a + tapB.a) / 3.0;

    // ── Idea 1: critical-curve magnification (§12.2F) ───────────────────────
    // Flux per pixel goes as mu = 1/|det J|; it diverges where det J = 0 - the
    // Einstein ring of the primary and the distorted curves of the cluster masses.
    // (Rescue: HEAD's ring highlight fed einsteinRadius() the pixel's own distance,
    // so it only ever drew a dot at the cursor.)
    let detJ = clamp(jxx * jyy - jxy * jxy, -50.0, 50.0);
    let crit = exp(-(detJ / 0.2) * (detJ / 0.2));
    let ringGain = crit * lensStrength;
    color *= 1.0 + ringGain * 0.8;                         // magnified background light

    // Add accretion disk around primary mass
    let toPrimary = uv - masses[0].pos;
    let distPrimary = length(toPrimary);
    let innerDisk = masses[0].radius * 3.0;
    let outerDisk = masses[0].radius * 15.0;
    var diskEmit = 0.0;

    if (distPrimary > innerDisk && distPrimary < outerDisk) {
        // ── Idea 2: Doppler-beamed disk (§12.2F blackbody + beaming) ────────
        // Keplerian speed beta ~ r^-1/2; an inclined disk shows the approaching
        // side (left) hotter and brighter: D = 1/(1 - beta_los), T_obs = D T,
        // I_obs = D^3 I. Divided by the angular mean of D^3 so the ring-average
        // brightness stays at HEAD's.
        let phi = atan2(toPrimary.y, toPrimary.x);
        let orbitBeta = 0.38 * sqrt(innerDisk / distPrimary);
        let betaLos = -0.8 * orbitBeta * (toPrimary.x / distPrimary);   // cos(phi)
        let dop = 1.0 / (1.0 - betaLos);
        let b2 = 0.64 * orbitBeta * orbitBeta;
        let omb = 1.0 - b2;
        let dopNorm = omb * omb * sqrt(omb) / (1.0 + 0.5 * b2);   // (1-b^2)^2.5 / (1+b^2/2)

        let diskTemp = accretionDiskColor(distPrimary, innerDisk, dop) * dopNorm;
        let diskPattern = sin(phi * 20.0 + time * 2.0);
        let diskGlow = smoothstep(outerDisk, innerDisk, distPrimary) *
                       (0.7 + diskPattern * 0.3);

        let diskGain = diskIntensity * (1.0 + held * 2.0 + bass * 1.5);
        color += diskTemp * diskGlow * diskGain;
        diskEmit = diskGlow * diskIntensity;
    }

    // Einstein ring highlight (cool tint along the critical curve)
    color += vec3<f32>(0.8, 0.9, 1.0) * ringGain * 0.5;

    // Gravitational redshift near mass
    let redshift = smoothstep(masses[0].radius * 10.0, masses[0].radius, distPrimary);
    color.r += color.r * redshift * 0.3;
    color.b -= color.b * redshift * 0.2;
    
    // Tone mapping
    color = toneMap(color);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    color *= vignette;
    
    // Semantic alpha: lens coverage (void where rays leave the frame), lifted by emission
    let alpha = clamp(mix(0.55, 1.0, coverage) + max(ringGain, diskEmit) * 0.5, 0.0, 1.0);
    let finalOut = vec4<f32>(color, alpha);

    textureStore(writeTexture, coord, finalOut);
    textureStore(dataTextureA, coord, finalOut);
    textureStore(writeDepthTexture, coord, vec4<f32>(length(totalDeflection), 0.0, 0.0, 1.0));
}
