// ═══════════════════════════════════════════════════════════════════
//  Clean Vortex
//  Category: image
//  Features: audio-reactive, audio-driven, upgraded-rgba
//  Complexity: High
//  Created: 2025-11-25
//  Upgraded: 2026-10-05
//  Ideas: 1) Lamb-Oseen vortex profile (solid core + 1/r free tail) 2) streamline streaks (LIC smear along the swirl) 3) bathtub dimple (pressure-drop funnel refracts, darkens the core, recesses depth)
//  A packing: ACES display RGBA (alpha = source alpha x funnel transmission)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
// Peak of the normalised Lamb-Oseen speed (1 - e^{-x^2}) / x, reached at x ~ 1.121.
const LAMB_PEAK: f32 = 0.6382;

fn hash2(p: vec2<f32>) -> vec2<f32> {
    let n = sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453;
    return fract(vec2<f32>(n, n * 1.618));
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    var f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a.x, b.x, f.x), mix(c.x, d.x, f.x), f.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * noise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let c = max(x, vec3<f32>(0.0));
    return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

struct Vortex {
    center: vec2<f32>,      // aspect-corrected space (x scaled by width/height)
    strength: f32,          // peak swirl speed
    coreRadius: f32,
    rotationDir: f32,
};

// Idea 1: Lamb-Oseen vorticity — w = G/(pi rc^2) e^{-r^2/rc^2}, normalised so its peak
// equals the vortex strength (same range HEAD's core term used). Compact: no far tail.
fn calculateVorticity(p: vec2<f32>, vortices: array<Vortex, 4>, time: f32, bass: f32) -> f32 {
    var vorticity = 0.0;
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let v = vortices[i];
        let toCenter = p - v.center;
        let r2 = dot(toCenter, toCenter);
        let core = exp(-r2 / (v.coreRadius * v.coreRadius));
        let pulse = 1.0 + 0.1 * sin(time * 2.0 + f32(i)) + 0.1 * bass;
        vorticity = vorticity + v.strength * v.rotationDir * core * pulse;
    }
    return vorticity;
}

// Idea 1: Lamb-Oseen velocity — v = G/(2 pi r) (1 - e^{-r^2/rc^2}). Solid-body rotation inside
// the core, 1/r free-vortex tail outside it, so the far field decays instead of the whole
// frame spinning. G is chosen so the peak speed (at r ~ 1.12 rc) equals v.strength.
fn calculateVelocity(p: vec2<f32>, vortices: array<Vortex, 4>) -> vec2<f32> {
    var velocity = vec2<f32>(0.0, 0.0);
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let v = vortices[i];
        let toCenter = p - v.center;
        let r = max(length(toCenter), 1e-5);
        let x = r / v.coreRadius;
        let speed = v.strength * (1.0 - exp(-x * x)) / (x * LAMB_PEAK);
        let tangent = vec2<f32>(-toCenter.y, toCenter.x) / r;
        velocity = velocity + v.rotationDir * speed * tangent;
        // Gentle inflow toward the drain, confined to the core region.
        let inflowStrength = 0.1 * v.strength * exp(-r / v.coreRadius);
        velocity = velocity - (toCenter / r) * inflowStrength;
    }
    return velocity;
}

fn vorticityConfinement(
    p: vec2<f32>,
    vortices: array<Vortex, 4>,
    time: f32,
    epsilon: f32,
    bass: f32
) -> vec2<f32> {
    let eps = 0.01;
    let w_xp = abs(calculateVorticity(p + vec2<f32>(eps, 0.0), vortices, time, bass));
    let w_xn = abs(calculateVorticity(p - vec2<f32>(eps, 0.0), vortices, time, bass));
    let w_yp = abs(calculateVorticity(p + vec2<f32>(0.0, eps), vortices, time, bass));
    let w_yn = abs(calculateVorticity(p - vec2<f32>(0.0, eps), vortices, time, bass));
    let gradW = vec2<f32>(w_xp - w_xn, w_yp - w_yn) / (2.0 * eps);
    let gradWMag = length(gradW) + 0.0001;
    let N = gradW / gradWMag;
    let w = calculateVorticity(p, vortices, time, bass);
    return epsilon * vec2<f32>(N.y * w, -N.x * w);
}

// Idea 3: bathtub dimple. Cyclostrophic pressure of each vortex, approximated by a
// Lorentzian funnel rc^2/(r^2+rc^2): it matches the Bernoulli far field (p ~ -|v|^2/2,
// v ~ 1/r) and stays finite in the core. Returns (depth 0..~1, gradient.xy in aspect space).
fn dimpleField(p: vec2<f32>, vortices: array<Vortex, 4>, refStrength: f32) -> vec3<f32> {
    var depth = 0.0;
    var grad = vec2<f32>(0.0);
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let v = vortices[i];
        let d = p - v.center;
        let rc2 = v.coreRadius * v.coreRadius;
        let den = dot(d, d) + rc2;
        let s = v.strength / max(refStrength, 1e-4);
        let w = s * s;                       // pressure drop ~ |v|^2
        depth = depth + w * rc2 / den;
        grad = grad - w * 2.0 * rc2 * d / (den * den);
    }
    return vec3<f32>(depth, grad);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 1.0);
    // Aspect-correct working space: circles stay circles on wide frames.
    let p = vec2<f32>(uv.x * aspect, uv.y);
    let toUV = vec2<f32>(1.0 / aspect, 1.0);

    let vortexStrength = u.zoom_params.x;
    let coreSizeParam = u.zoom_params.y;
    let rotationSpeed = u.zoom_params.z;
    let turbulence = u.zoom_params.w;

    let strengthScale = mix(0.05, 0.3, vortexStrength) * (1.0 + bass * 0.2);
    let coreScale = mix(0.03, 0.15, coreSizeParam);
    let speedScale = mix(0.2, 1.5, rotationSpeed);
    let turbAmount = turbulence * 0.02 * (1.0 + treble * 0.2);

    // Audio nudges phase additively (never multiplies absolute time → no jumps).
    let t1 = time * speedScale + bass * 0.3 + mids * 0.2;
    let cx = 0.5 * aspect;
    var vortices: array<Vortex, 4>;
    vortices[0] = Vortex(
        vec2<f32>(cx + 0.1 * sin(t1 * 0.3), 0.5 + 0.1 * cos(t1 * 0.4)),
        strengthScale, coreScale, 1.0);
    let orbitAngle = t1 * 0.5;
    vortices[1] = Vortex(
        vec2<f32>(cx + 0.25 * cos(orbitAngle), 0.5 + 0.25 * sin(orbitAngle)),
        strengthScale * 0.7, coreScale * 0.8, -1.0);
    vortices[2] = Vortex(
        vec2<f32>(cx - 0.2 + 0.15 * sin(t1 * 0.2 + 1.0), 0.7 + 0.1 * cos(t1 * 0.25)),
        strengthScale * 0.5, coreScale * 0.6, 1.0);
    vortices[3] = Vortex(
        vec2<f32>(cx + 0.2 + 0.08 * sin(t1 * 0.8), 0.3 + 0.08 * cos(t1 * 0.7)),
        strengthScale * 0.4, coreScale * 0.5, -1.0);

    var velocity = calculateVelocity(p, vortices);
    velocity = velocity + vorticityConfinement(p, vortices, time, 0.02 * vortexStrength, bass);

    let turbUV = p * 3.0 + time * 0.1 + bass * 0.05;
    let turbulenceNoise = vec2<f32>(
        fbm(turbUV + vec2<f32>(0.0, time * 0.05), 3),
        fbm(turbUV + vec2<f32>(100.0, time * 0.05), 3)
    ) - 0.5;
    velocity = velocity + turbulenceNoise * turbAmount;

    let vorticity = calculateVorticity(p, vortices, time, bass);

    let displacementScale = mix(0.02, 0.15, vortexStrength);
    var displaced = p + velocity * displacementScale;

    // Local swirl: rotate around each vortex's own centre by its local vorticity.
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let v = vortices[i];
        let d = p - v.center;
        let core = exp(-dot(d, d) / (v.coreRadius * v.coreRadius));
        let ang = v.rotationDir * v.strength * core * 0.6 * vortexStrength;
        let cs = cos(ang);
        let sn = sin(ang);
        displaced = displaced + (vec2<f32>(cs * d.x - sn * d.y, sn * d.x + cs * d.y) - d);
    }

    // Idea 3: the funnel surface refracts the image toward each drain.
    let dimple = dimpleField(p, vortices, strengthScale);
    let dimpleDepth = dimple.x;
    displaced = displaced + dimple.yz * coreScale * coreScale * 0.35 * vortexStrength;

    let finalUV = displaced * toUV;
    let safeUV = clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0));
    let src = textureSampleLevel(readTexture, u_sampler, safeUV, 0.0);

    // Idea 2: streamline streaks (line-integral convolution). March backward along the
    // local velocity from the warped sample and average, so the picture motion-blurs
    // along the swirl where it is fast and stays crisp in the calm far field.
    let velMag = length(velocity);
    var lic = src.rgb;
    var licW = 1.0;
    var q = displaced;
    let stepLen = (0.012 + 0.03 * vortexStrength) / max(strengthScale, 1e-4);
    for (var k: i32 = 1; k <= 5; k = k + 1) {
        let vk = calculateVelocity(q, vortices);
        q = q - vk * stepLen * 0.2;
        let wk = 1.0 - f32(k) * 0.15;
        lic = lic + textureSampleLevel(readTexture, u_sampler, clamp(q * toUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * wk;
        licW = licW + wk;
    }
    lic = lic / licW;
    let streakMix = smoothstep(0.15, 0.7, velMag / max(strengthScale, 1e-4));
    var col = mix(src.rgb, lic, streakMix);

    let velocityGlow = smoothstep(0.0, 0.5, velMag) * 0.1 * vortexStrength;
    let vorticityColor = vec3<f32>(
        1.0 + sign(vorticity) * 0.1,
        1.0,
        1.0 - sign(vorticity) * 0.1
    );
    col = col * mix(vec3<f32>(1.0), vorticityColor, velMag * 0.3);
    col = col * (1.0 + velocityGlow);

    // Idea 3: core darkening — light falls off down the throat of the funnel.
    let throat = clamp(dimpleDepth, 0.0, 1.5);
    col = col * (1.0 - 0.35 * vortexStrength * smoothstep(0.2, 1.2, throat));

    // ACES on display RGB only (negatives clamped inside acesToneMap).
    let display = acesToneMap(col * 1.1);

    // Semantic alpha: source coverage × funnel transmission × scattering loss.
    let scatteringLoss = (velMag + abs(vorticity) * 0.1) * 0.3 * vortexStrength;
    let funnelT = 1.0 - 0.25 * vortexStrength * smoothstep(0.3, 1.2, throat);
    let finalAlpha = clamp(src.a * funnelT * (1.0 - scatteringLoss * 0.5), 0.2, 1.0);

    let finalColor = vec4<f32>(display, finalAlpha);
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);

    // Idea 3: the dimple is written to depth — the funnel recedes from the viewer.
    let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, safeUV, 0.0).r;
    let depthOut = clamp(depthSample - 0.15 * vortexStrength * min(throat, 1.0), 0.0, 1.0);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
