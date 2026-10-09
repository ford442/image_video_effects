// ═══════════════════════════════════════════════════════════════════
//  Ethereal Cyber-Chrono Nebula-Phoenix
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: wing feather filaments along SDF edge; tail ember convection streaks;
//         2nd pass: molting sparks peel off the wing edge and drift upward;
//         ash-to-flame rebirth cycle (bass re-ignites); three-feather head crest
//  A packing: raw telemetry in A (trap, d, nebula, alpha) — C reads fields
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
const PI: f32 = 3.14159265359;
// Stateless: no extraBuffer state (the engine re-uploads extraBuffer every
// frame, so the old [133..137] halo spring was dead and tore across workgroups).
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}
fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
    return p + 0.25 * q;
}
// Hue-preserving clamp: scale by the brightest channel so hue survives.
fn huePreserveClamp(c: vec3<f32>, maxC: f32) -> vec3<f32> {
    let peak = max(c.r, max(c.g, c.b));
    let scale = min(1.0, maxC / max(peak, 1e-4));
    return c * scale;
}
// ACES filmic tonemap (Narkowicz approximation).
fn acesTonemap(x: vec3<f32>) -> vec3<f32> {
    let num = x * (2.51 * x + vec3<f32>(0.03));
    let den = x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14);
    return clamp(num / den, vec3<f32>(0.0), vec3<f32>(1.0));
}
// Clifford-like strange attractor used as a chrono-orbit trap.
// Constants (-1.4, 1.6, 1.0, 0.7, 24 iters) preserved verbatim.
fn attractorTrap(p: vec2<f32>, t: f32, bass: f32) -> f32 {
    var z = p * 2.0;
    var trap = 100.0;
    let a = -1.4 + bass * 0.3;
    let b = 1.6 + sin(t * 0.2) * 0.1;
    let c = 1.0;
    let d = 0.7;
    let orbitTarget = vec2<f32>(0.4 * sin(t), 0.3 * cos(t));
    for (var i = 0; i < 24; i = i + 1) {
        let nx = sin(a * z.y) + c * cos(a * z.x);
        let ny = sin(b * z.x) + d * cos(b * z.y);
        z = vec2<f32>(nx, ny);
        trap = min(trap, length(z - orbitTarget));
    }
    return trap;
}

// SDF silhouette: cybernetic phoenix body, wings and tail.
// Hand-tuned constants preserved verbatim.
// Tapered feather: segment a->b whose radius narrows from ra to rb.
fn sdTaperedFeather(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, ra: f32, rb: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - mix(ra, rb, h);
}

// Idea: head crest plume — three tapered feathers fanning from the crown
// (the head is the +p.y end of the body; the tail runs toward -p.y).
fn sdHeadCrest(p: vec2<f32>) -> f32 {
    let crown = vec2<f32>(0.0, 0.25);
    var dc = 1e3;
    for (var k = -1; k <= 1; k = k + 1) {
        let ang = f32(k) * 0.42;
        let len = 0.15 - abs(f32(k)) * 0.035;
        let tip = crown + len * vec2<f32>(sin(ang), cos(ang));
        // Slight outward curl: sample the feather in a gently bent frame.
        let bend = vec2<f32>(f32(k) * 0.03 * smoothstep(0.25, 0.4, p.y), 0.0);
        dc = min(dc, sdTaperedFeather(p - bend, crown, tip, 0.022, 0.003));
    }
    return dc;
}

fn sdPhoenix(p: vec2<f32>, wingspan: f32) -> f32 {
    let body = length(vec2<f32>(p.x * 4.0, max(0.0, abs(p.y) - 0.22))) - 0.06;
    let wingY = p.y - 0.12;
    let wingX = abs(p.x) - 0.06;
    // Sweep angle saturates at the old 0.5 clamp (identical look for
    // wingspan <= 0.5); above that the slider keeps lengthening the wing so
    // the saved 0.1–1.0 range is fully live.
    let wingUV = rot(0.25 + min(wingspan, 0.5) * 2.0) * vec2<f32>(wingX, wingY);
    let wing = length(vec2<f32>(wingUV.x * 0.35 / wingspan, wingUV.y * 2.5)) - 0.12;
    let tailUV = vec2<f32>(p.x * 2.0, p.y + 0.35);
    let tail = length(vec2<f32>(tailUV.x, max(0.0, -tailUV.y))) - 0.1 + 0.08 * sin(p.y * 20.0);
    return min(min(min(body, wing), tail), sdHeadCrest(p));
}

fn sdPhoenixGrad(p: vec2<f32>, wingspan: f32) -> vec2<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let dx = sdPhoenix(p + e.xy, wingspan) - sdPhoenix(p - e.xy, wingspan);
    let dy = sdPhoenix(p + e.yx, wingspan) - sdPhoenix(p - e.yx, wingspan);
    return normalize(vec2<f32>(dx, dy) + vec2<f32>(0.0001));
}

// Native idea 1: phoenix plumage filaments along wing SDF edges.
fn wingFeatherFilaments(p: vec2<f32>, wingspan: f32, edge: f32, t: f32) -> f32 {
    let onWing = smoothstep(0.0, 0.1, abs(p.x) - 0.05) * smoothstep(-0.15, 0.2, p.y - 0.12);
    let grad = sdPhoenixGrad(p, wingspan);
    let tangent = vec2<f32>(-grad.y, grad.x);
    let featherCoord = dot(p, tangent) * 90.0 + edge * 140.0;
    let barb = 0.5 + 0.5 * sin(featherCoord + t * 2.2);
    let barbFine = 0.5 + 0.5 * sin(featherCoord * 3.9 - t * 1.4);
    let edgeBand = smoothstep(0.1, 0.0, edge);
    return onWing * edgeBand * barb * barbFine;
}

// Native idea 2: rising ember convection along the tail SDF axis.
fn tailEmberConvection(p: vec2<f32>, t: f32, bass: f32) -> f32 {
    let tailUV = vec2<f32>(p.x * 2.0, p.y + 0.35);
    let inTail = smoothstep(0.18, 0.0, length(vec2<f32>(tailUV.x, max(0.0, -tailUV.y))));
    let axisPhase = -tailUV.y * 20.0 - t * (2.8 + bass * 1.8);
    let streak = 0.5 + 0.5 * sin(axisPhase + sin(tailUV.x * 32.0) * 2.5);
    let streakFine = pow(0.5 + 0.5 * sin(axisPhase * 2.4 + tailUV.x * 48.0), 3.0);
    return inTail * streak * streakFine;
}
// Idea: molting sparks — stateless particles born on the wing edge.
// Each of three staggered life layers back-traces the pixel along the
// spark's drift (outward along sdPhoenixGrad + screen-up) to a birth cell;
// a hashed epoch decides whether that edge cell molts this cycle.
fn moltingSparks(p: vec2<f32>, grad: vec2<f32>, upP: vec2<f32>, wingspan: f32, t: f32, treble: f32) -> f32 {
    let cellN = 36.0;
    var acc = 0.0;
    for (var k = 0; k < 3; k = k + 1) {
        let life = t * 0.45 + f32(k) / 3.0;
        let tau = fract(life);
        let epoch = floor(life);
        let drift = grad * 0.06 * tau + upP * 0.22 * tau * tau
                  + vec2<f32>(sin(tau * 9.0 + f32(k) * 2.1), 0.0) * 0.01 * tau;
        let q = p - drift;
        let cell = floor(q * cellN);
        let h = hash21(cell + vec2<f32>(epoch * 17.31, f32(k) * 41.7));
        let born = step(0.8 - treble * 0.15, h);
        let birth = (cell + 0.5) / cellN;
        let edgeAtBirth = exp(-abs(sdPhoenix(birth, wingspan)) * 45.0);
        let onWing = smoothstep(0.02, 0.08, abs(birth.x) - 0.05);
        let sparkPos = birth + drift;
        let r = length(p - sparkPos) * cellN;
        let fade = (1.0 - tau) * smoothstep(0.0, 0.08, tau);
        acc += born * edgeAtBirth * onWing * exp(-r * r * 9.0) * fade;
    }
    return acc;
}

// Idea: ash-to-flame rebirth — once per 26 s cycle the body crumbles to ash
// through a nebula-fbm dissolve threshold, then reforms. Bass re-ignites it
// immediately. Returns (solid, fireFront).
fn rebirthDissolve(p: vec2<f32>, nebula: f32, t: f32, bass: f32) -> vec2<f32> {
    let cyc = fract(t / 26.0);
    // Fully formed for ~78% of the cycle; ash peaks near cyc = 0.9.
    var ash = smoothstep(0.78, 0.88, cyc) * (1.0 - smoothstep(0.92, 1.0, cyc));
    ash *= 1.0 - smoothstep(0.25, 0.6, bass);
    let n = clamp(0.5 * fbm(p * 7.0 + vec2<f32>(0.0, t * 0.3), 3) + 0.4 * clamp(nebula / 1.4, 0.0, 1.0) + 0.1, 0.0, 1.0);
    let thr = ash * 1.05;
    let solid = smoothstep(thr - 0.04, thr + 0.02, n);
    let front = exp(-abs(n - thr) * 40.0) * smoothstep(0.0, 0.05, ash);
    return vec2<f32>(solid, front);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }

    let res = vec2<f32>(dims);
    let uv01 = (vec2<f32>(id.xy) + 0.5) / res;
    let uv = (vec2<f32>(id.xy) + 0.5 - 0.5 * res) / min(res.x, res.y);

    let time = u.config.x;
    // LIVE AUDIO: plasmaBuffer[0] = [bass, mid, treble, level] FFT bands.
    // u.config.y is the ripple COUNT (near-constant), not sound — the old
    // "audio" read was dead; bass/treble now drive the reaction for real.
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    // Mouse used directly (uv, y=0 top): stateless, identical in every workgroup.
    let mouse = u.zoom_config.yz;
    let wingspan = clamp(u.zoom_params.x, 0.1, 1.0);
    let plasma = clamp(u.zoom_params.y, 0.0, 1.0);
    let chronoMix = clamp(u.zoom_params.z, 0.0, 1.0);
    let spinRate = clamp(u.zoom_params.w, 0.0, 1.0);

    let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);
    let inDepthUV = clamp(uv01, vec2<f32>(0.0), vec2<f32>(1.0));
    let inDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, inDepthUV, 0.0).r;

    // Domain-warped FBM nebula background; bass breathes through the gas.
    let warp = domainWarp(uv * 2.0 + vec2<f32>(time * 0.02), time * 0.05);
    let previous = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);
    var nebula = fbm(warp * 3.0, 5);
    nebula += 0.5 * fbm(warp * 6.0 + bass + mids * 0.4, 4);
    nebula = mix(previous.b, nebula, 0.32 + mids * 0.18);
    let bgColor = vec3<f32>(0.08, 0.05, 0.15) * nebula * (1.0 + bass * 2.0);

    // Strange-attractor chrono fractal: bass wobbles the orbit constant,
    // treble drives the shimmer of the chrono glow.
    let trapNow = attractorTrap(uv * 1.5, time, bass);
    let trap = mix(previous.r, trapNow, 0.65 + treble * 0.2);
    let shimmer = 0.85 + 0.3 * sin(time * 9.0 + trap * 14.0) * treble;
    let chronoGlow = exp(-trap * 6.0) * (0.5 + 0.5 * treble) * shimmer * (0.35 + chronoMix * 0.65);

    // Phoenix SDF and orbit-trap coloring.
    let R = rot(mouse.x * 2.0 + time * (0.05 + spinRate * 0.35));
    let p = R * uv;
    let dNow = sdPhoenix(p, wingspan);
    let d = mix(previous.g, dNow, 0.78 + mids * 0.12);
    let edge = abs(d);
    let baseDensity = smoothstep(0.12, 0.0, d);
    let rebirth = rebirthDissolve(p, nebula, time, bass);
    let density = baseDensity * rebirth.x;
    let shell = exp(-edge * 12.0) * mix(0.35, 1.0, rebirth.x);
    // Ash flakes linger where the body has crumbled; the fire front burns
    // along the dissolve threshold.
    let ashAmt = baseDensity * (1.0 - rebirth.x);
    let fireFront = baseDensity * rebirth.y;

    // Click ripple rings: expanding shockwaves that momentarily flare
    // the wing plasma as the ring sweeps across it.
    let rippleCount = min(u32(u.config.y), 50u);
    var rippleFlare = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        let ringRadius = age * 0.7;
        let ringDist = length(uv01 - rp.xy);
        let ring = exp(-abs(ringDist - ringRadius) * 28.0) * exp(-age * 2.2) * step(0.0, age);
        rippleFlare += ring;
    }
    rippleFlare = min(rippleFlare, 1.5);

    // Bass-driven wing plasma pulse, kicked harder by click ripples.
    let wingPulse = 1.0 + bass * 1.6 + rippleFlare * 2.0 * plasma;

    // Cosmic palette driven by orbit traps and audio.
    let pal = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(0.0, 0.33, 0.67) * PI * 2.0 + time * 0.5 - trap * 2.0);
    var phoenixColor = pal * (density + shell * 0.6 * wingPulse);
    phoenixColor += vec3<f32>(1.0, 0.4, 0.1) * chronoGlow * plasma;
    phoenixColor += vec3<f32>(1.0, 0.55, 0.2) * rippleFlare * shell * plasma * 1.5;

    let featherFilaments = wingFeatherFilaments(p, wingspan, edge, time);
    phoenixColor += vec3<f32>(1.0, 0.75, 0.45) * featherFilaments * shell * (0.6 + treble * 0.5);

    let emberStreaks = tailEmberConvection(p, time, bass);
    phoenixColor += vec3<f32>(1.0, 0.35, 0.05) * emberStreaks * plasma * (0.5 + bass);

    phoenixColor += vec3<f32>(0.16, 0.14, 0.13) * ashAmt;
    phoenixColor += vec3<f32>(1.0, 0.45, 0.08) * fireFront * (1.0 + plasma);

    // Idea: molting sparks drift up off the wing edge (screen-up mapped into
    // the rotated phoenix frame).
    let gradP = sdPhoenixGrad(p, wingspan);
    let upP = R * vec2<f32>(0.0, -1.0);
    let sparks = moltingSparks(p, gradP, upP, wingspan, time, treble);
    phoenixColor += vec3<f32>(1.0, 0.62, 0.25) * sparks * (0.8 + plasma * 1.2 + bass);

    // Phoenix attention halo at the cursor.
    let mouseDist = length(uv01 - mouse);
    let mouseGlow = exp(-mouseDist * 20.0) * (0.3 + bass);
    phoenixColor += vec3<f32>(0.4, 0.8, 1.0) * mouseGlow;

    // Composite over video background.
    var color = mix(video.rgb, phoenixColor, clamp(density + shell * 0.5 + ashAmt * 0.5 + sparks + fireFront, 0.0, 1.0));
    color = mix(color, bgColor, 0.35 * (1.0 - density));

    // HDR taming: hue-preserving clamp at ~2.0, then ACES before store.
    color = huePreserveClamp(color, 2.0);
    color = acesTonemap(max(color, vec3<f32>(0.0)));

    // Meaningful alpha: emission + occlusion, not forced to 1.0.
    let alpha = clamp(density + shell * 0.4 + chronoGlow * 0.2 + ashAmt * 0.4 + min(sparks, 1.0) * 0.6, 0.0, 1.0);

    // Depth: phoenix in front, input depth preserved where transparent.
    let depth = mix(inDepth, 0.2 + density * 0.6, clamp(density + shell * 0.5, 0.0, 1.0));

    textureStore(writeTexture, id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(trap, d, nebula, alpha));
}
