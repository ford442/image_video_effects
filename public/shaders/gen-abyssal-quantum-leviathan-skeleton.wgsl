// ----------------------------------------------------------------
// Abyssal Quantum-Leviathan Skeleton
// Category: generative
// Batch 38 (Algorithmist): FAST MOTION upgrade —
//   * fast undulating spine kinematics: closed-form traveling wave with
//     tail-growing whip amplitude + incommensurate second harmonic
//     (sub-frame stable, no hash strobing)
//   * ballistic lunge dynamics: periodic dart-forward surge with
//     exp-decay envelope; bass-transient kick (rising-edge, dt-integrated
//     in extraBuffer[133..135]) triggers extra lunges + rib flares
//   * high-speed aether-current advection: noise field streamed at high
//     flow speed, anisotropically stretched along the flow direction
//     (speed-streak / speed-line currents), Current Turbulence slider
//     governs flow rate
//   * velocity-advected motion-blur trails via dataTextureC feedback
//     (textureLoad only, HDR history clamped <= 6.0)
//   * uniform-truth rewrite, plasmaBuffer audio (was fake: rippleCount!),
//     ACES, semantic alpha, real generated depth.
// ----------------------------------------------------------------

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
    config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active), .zw = resolution (width, height)
    zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
    zoom_params: vec4<f32>,  // .x = Bone Density, .y = Marrow Glow, .z = Current Turbulence, .w = Audio Reactivity
    ripples: array<vec4<f32>, 50>, // .xy = ripple uv, .z = startTime (seconds), .w = padding
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const HDR_CLAMP: f32 = 6.0;    // feedback energy bound (Batch 36 lesson)
const MAX_D: f32 = 40.0;

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn acesTone(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + vec3<f32>(0.03))) /
                 (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)),
                 vec3<f32>(0.0), vec3<f32>(1.0));
}

// Hash function for noise
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

// 3D gradient noise for Aether Currents (kept from original — smooth)
fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u_f = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);

    return mix(
        mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u_f.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u_f.x), u_f.y),
        mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u_f.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u_f.x), u_f.y), u_f.z);
}

// Per-frame scene constants (built once in main, passed by value)
struct SceneCtx {
    animTime: f32,        // time * turbulence-driven rate
    waveSpeed: f32,       // spine traveling-wave speed (fast, kick-boosted)
    lungeOffset: f32,     // ballistic dart-forward surge (bounded)
    pulseZ: f32,          // racing shock-pulse position along the spine
    pulseEnv: f32,        // shock-pulse brightness envelope (bounded)
    boneDensity: f32,     // Bone Density slider
    audioReact: f32,      // Audio Reactivity slider
    bass: f32,
    mouseWorld: vec3<f32>,// cursor gravity-well position (uniform truth)
};

// SDF for the leviathan skeleton
fn map(pos_in: vec3<f32>, ctx: SceneCtx) -> vec2<f32> {
    var p = pos_in;

    // Ballistic lunge: the whole skeleton darts along its spine axis
    p.z += ctx.lungeOffset;

    // Mouse interaction as a gravity well (uniform-truth mouse uv, y=0 top)
    let dist_to_mouse = length(p - ctx.mouseWorld);
    if (dist_to_mouse < 5.0) {
        let pull = smoothstep(5.0, 0.0, dist_to_mouse) * 2.0;
        p = mix(p, ctx.mouseWorld, pull * 0.1);
    }

    // Fast undulating spine kinematics: closed-form traveling wave
    // (phase = k*z - w*t) with tail-growing WHIP amplitude plus a second
    // incommensurate harmonic — smooth at any speed, never strobes.
    let whip = 1.4 + 0.9 * smoothstep(0.0, 12.0, abs(p.z));
    let ph1 = p.z * 0.30 - ctx.animTime * ctx.waveSpeed;
    let ph2 = p.z * 0.22 - ctx.animTime * ctx.waveSpeed * 0.77;
    p.x += (sin(ph1) + 0.35 * sin(ph1 * 2.17 + 1.3)) * whip * 1.3;
    p.y += cos(ph2) * whip * 0.8;

    // Spine core
    let spine_dist = length(p.xy) - 0.5 * ctx.boneDensity;
    var d = spine_dist;
    var material = 1.0; // 1.0 for bone

    // Ribs (domain repetition along Z)
    let rib_spacing = 1.5 / max(ctx.boneDensity, 0.05);
    let p_z_mod = p.z - rib_spacing * floor(p.z / rib_spacing) - rib_spacing * 0.5;
    var p_rib = vec3<f32>(p.x, p.y, p_z_mod);

    // Rib shape (arcing outwards from spine)
    p_rib.x = abs(p_rib.x) - 1.0; // mirror symmetry
    p_rib.y -= 0.5;

    // Audio reactivity bulges the ribs (real bass + racing pulse flare)
    let flare = exp(-abs(pos_in.z - ctx.pulseZ) * 0.6) * ctx.pulseEnv;
    let bulge = sin(ctx.animTime * 6.0 + p.z * 0.5) * ctx.audioReact * ctx.bass * 0.25 + flare * 0.15;
    let rib_thickness = max(0.2 * ctx.boneDensity + bulge, 0.03);

    // Torus-like ribs curving downwards
    let q = vec2<f32>(length(p_rib.xy) - 3.0, p_rib.z);
    let rib_dist = length(q) - rib_thickness;

    d = smin(d, rib_dist, 0.8);

    return vec2<f32>(d, material);
}

fn calcNormal(p: vec3<f32>, ctx: SceneCtx) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, ctx).x - map(p - e.xyy, ctx).x,
        map(p + e.yxy, ctx).x - map(p - e.yxy, ctx).x,
        map(p + e.yyx, ctx).x - map(p - e.yyx, ctx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) {
        return;
    }

    let time = u.config.x;

    // ---- Audio: plasma bands + guarded engine FFT bins 1-4 ----------------
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fftPulse = 0.0;
    if (arrayLength(&extraBuffer) > 9u) {
        fftPulse = (extraBuffer[6] + extraBuffer[7] + extraBuffer[8] + extraBuffer[9]) * 0.25;
    }

    // ---- Bass-transient kick: rising-edge detect, dt-integrated decay ----
    // Persistent state ONLY in [133..135], single writer thread.
    if (global_id.x == 0u && global_id.y == 0u && arrayLength(&extraBuffer) > 135u) {
        let prevT = extraBuffer[134];
        let dt = clamp(time - prevT, 0.0, 0.1); // frame-rate independent
        let prevBass = extraBuffer[133];
        var kickE = extraBuffer[135] * exp(-dt * 4.0);
        let rising = max(bass - prevBass, 0.0);
        kickE = min(kickE + rising * 2.5, 2.0); // bounded burst energy
        extraBuffer[133] = bass;
        extraBuffer[134] = time;
        extraBuffer[135] = kickE;
    }
    var kick = 0.0;
    if (arrayLength(&extraBuffer) > 135u) {
        kick = extraBuffer[135];
    }

    // ---- Live slider wiring ------------------------------------------------
    let boneDensity = mix(0.25, 1.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let marrowGlow = mix(0.1, 1.6, clamp(u.zoom_params.y, 0.0, 1.0));
    let turb = clamp(u.zoom_params.z, 0.0, 1.0);          // Current Turbulence
    let audioReact = mix(0.0, 2.0, clamp(u.zoom_params.w, 0.0, 1.0));

    // ---- Closed-form fast motion (all analytic in time: fps-independent) --
    let rate = mix(0.7, 2.2, turb);                       // currents drive pace
    let animTime = time * rate;

    // Ballistic lunge cycle: fast attack (dart), smooth exponential recovery
    let lungePhase = fract(animTime * 0.45);
    let lungeEnv = exp(-lungePhase * 3.5);
    let lungeOffset = lungeEnv * (2.5 + kick * 3.0 * audioReact);

    var ctx: SceneCtx;
    ctx.animTime = animTime;
    ctx.waveSpeed = mix(2.5, 9.0, turb) * (1.0 + kick * 0.4 * audioReact);
    ctx.lungeOffset = lungeOffset;
    ctx.pulseZ = mix(-14.0, 14.0, 1.0 - lungePhase);      // shock races head->tail
    ctx.pulseEnv = (lungeEnv + kick * 0.8) * audioReact;
    ctx.boneDensity = boneDensity;
    ctx.audioReact = audioReact;
    ctx.bass = bass;
    let mouseUv = u.zoom_config.yz;
    ctx.mouseWorld = vec3<f32>((mouseUv.x - 0.5) * 10.0, (mouseUv.y - 0.5) * 10.0, 0.0); // top-down mouse: screen top = -cv (world -y), so no y-flip

    // ---- Camera: fast pursuit orbit with lunge follow-through -------------
    let orbA = animTime * mix(0.3, 0.8, turb);
    var ro = vec3<f32>(sin(orbA) * 12.0, sin(orbA * 0.5 + 1.3) * 5.0, cos(orbA) * 12.0);
    ro.z += lungeOffset * 0.4; // camera gets dragged by the dart
    let ta = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));

    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // ---- Raymarching -------------------------------------------------------
    var t = 0.0;
    var hit = false;
    var res2 = vec2<f32>(0.0);
    var p = ro;

    for (var i = 0; i < 80; i++) {
        p = ro + rd * t;
        res2 = map(p, ctx);
        if (res2.x < 0.01) {
            hit = true;
            break;
        }
        if (t > MAX_D) {
            break;
        }
        t += res2.x * 0.8;
    }

    var color = vec3<f32>(0.0);

    if (hit) {
        let n = calcNormal(p, ctx);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let amb = 0.1;

        // Base bone color
        color = vec3<f32>(0.2, 0.4, 0.5) * diff + vec3<f32>(0.05, 0.1, 0.15) * amb;

        // Rim light
        let rim = 1.0 - max(dot(n, -rd), 0.0);
        color += vec3<f32>(0.1, 0.8, 1.0) * pow(rim, 3.0);

        // Marrow glow inside bones (real audio pulse: mids/treble + FFT)
        let dist_to_center = length(p.xy);
        let marrow_intensity = smoothstep(2.0, 0.0, dist_to_center) * marrowGlow;
        let audio_pulse = (sin(animTime * 8.0 + p.z) * 0.5 + 0.5) * (mids + fftPulse) * audioReact;
        color += vec3<f32>(0.5, 0.0, 1.0) * marrow_intensity * (0.6 + audio_pulse);

        // Racing shock-pulse lights the bones as it passes (kick/lunge)
        let pulseHere = exp(-abs(p.z + ctx.lungeOffset - ctx.pulseZ) * 0.6) * ctx.pulseEnv;
        color += vec3<f32>(0.2, 1.0, 0.9) * pulseHere * 0.8;

        // Simple fog
        color = mix(color, vec3<f32>(0.0, 0.02, 0.05), smoothstep(10.0, MAX_D, t));
    } else {
        // Background volumetric deep-sea aether currents, HIGH-SPEED:
        // the noise field is streamed fast along -z and anisotropically
        // stretched along the flow direction -> speed-streak currents.
        var vol_acc = 0.0;
        var vol_t = 0.0;
        let step_size = 0.6;
        let flowSpeed = mix(2.0, 10.0, turb) + kick * 3.0 * audioReact;
        let freq = mix(0.35, 0.9, turb);
        for (var i = 0; i < 24; i++) {
            let vp = ro + rd * vol_t;
            // Stretch z (flow axis): elongates eddies into speed lines
            let sp = vec3<f32>(vp.x * 2.0, vp.y * 2.0, vp.z * 0.35 - animTime * flowSpeed) * freq;
            let n_val = noise3(sp);
            let n_det = noise3(sp * 2.3 + vec3<f32>(0.0, animTime * flowSpeed * 0.35, 0.0));
            vol_acc += smoothstep(0.15, 0.45, n_val + 0.4 * n_det) * 0.06;
            vol_t += step_size;
            if (vol_t > MAX_D) { break; }
        }
        let bg_color = vec3<f32>(0.0, 0.05, 0.1);
        let aether_color = vec3<f32>(0.0, 0.5, 0.8) + vec3<f32>(0.3, 0.1, 0.6) * sin(animTime * 2.0);
        color = bg_color + aether_color * vol_acc * (0.7 + treble * 0.4 * audioReact);
    }

    // ---- Velocity-advected motion-blur trails (feedback, textureLoad) -----
    // Camera tangential velocity (analytic derivative of the orbit) gives a
    // stable screen-space streak direction; clamped to +-4 px.
    let camVel = cos(orbA) * mix(0.3, 0.8, turb) * rate; // d(ro.x phase)/dt sign
    let streakX = clamp(-camVel * 6.0, -4.0, 4.0);
    let advect = vec2<i32>(i32(streakX), 0);
    let prevPx = clamp(coords - advect, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
    let prev = textureLoad(dataTextureC, prevPx, 0);

    let decay = 0.85;
    var history = prev.rgb * decay + color * 0.35;
    history = clamp(history, vec3<f32>(0.0), vec3<f32>(HDR_CLAMP)); // energy bound

    // ---- HDR -> ACES, semantic alpha, real generated depth -----------------
    let tone = acesTone(history * 1.1);
    let alpha = clamp(select(0.08 + luma(color) * 0.4, 0.92, hit), 0.0, 0.97);
    let depth = select(0.05, clamp(1.0 - t / MAX_D, 0.0, 1.0), hit); // near-is-one

    textureStore(dataTextureA, coords, vec4<f32>(history, alpha));
    textureStore(writeTexture, coords, vec4<f32>(tone, alpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}
