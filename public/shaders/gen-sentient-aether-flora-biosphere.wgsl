// ----------------------------------------------------------------
// Sentient Aether-Flora Biosphere
// Category: generative
// Features: raymarched twisted flora, KIFS petals, bioluminescent
//   spore swarm with spring cursor-pursuit, bass-kick bloom shockwave,
//   self-organizing fast growth fronts along feedback history,
//   velocity-advected HDR trails, audio-reactive, generated depth,
//   semantic alpha
// Interactivist pass (batch 38, FAST MOTION): fixed uniform-truth
//   violations (click count was used as an audio proxy; p1/p2 sliders
//   were declared but never used), wired all 4 sliders live, spores
//   became a fast flying swarm with clamped-velocity cursor chase,
//   kick-triggered bloom bursts with bounded exp decay, growth fronts
//   that propagate fast along their own feedback history, real depth
//   + semantic alpha.
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
  config: vec4<f32>,       // x=time (s), y=rippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=time, yz=mouse uv (0-1 canvas, y=0 top), w=mouseDown (>0.5 pressed)
  zoom_params: vec4<f32>,  // x=Intensity, y=Speed, z=Scale, w=Mouse Influence
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const HDR_CEIL: f32 = 6.0;      // feedback energy ceiling
const TRAIL_DECAY: f32 = 0.85;  // velocity-advected trail persistence
const MAX_MOUSE_VEL: f32 = 8.0; // cursor pursuit velocity clamp (uv/s)

// Per-pixel flora context (computed once, threaded through map calls)
struct FloraCtx {
  time: f32,      // seconds
  bloom: f32,     // kick/click bloom impulse (bounded exp decay)
  growth: f32,    // feedback growth-front energy (self-organizing)
  twist_k: f32,   // stem twist (sway + mouse + bass)
  spacing: f32,   // flora domain repetition (Scale slider)
  bloom_amp: f32, // petal radius pulse amplitude (Speed slider)
};

// --- Helper Functions ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// 3D Noise, SDF Primitives (sdCylinder, sdSphere), opTwist, opRep
fn sdCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn opTwist(p: vec3<f32>, k: f32) -> vec3<f32> {
    let c = cos(k * p.y);
    let s = sin(k * p.y);
    let m = mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
    let xz = m * p.xz;
    return vec3<f32>(xz.x, p.y, xz.y);
}

// --- Raymarching ---
// map(pos): returns vec2 (distance, material_id)
fn map(pos: vec3<f32>, ctx: FloraCtx) -> vec2<f32> {
    // Domain Repetition (Scale slider governs flora density)
    let c = vec3<f32>(ctx.spacing, 0.0, ctx.spacing);
    let rep_pos = vec3<f32>(pos.x - c.x * floor(pos.x / c.x), pos.y, pos.z - c.z * floor(pos.z / c.z)) - vec3<f32>(c.x * 0.5, 0.0, c.z * 0.5);

    // Flora stems (twisted cylinders) — fast whip sway
    let twisted_pos = opTwist(rep_pos, ctx.twist_k);
    let stem_d = sdCylinder(twisted_pos, 4.0, 0.2);

    // Petals (KIFS-like folded planes + spheres)
    var petal_pos = rep_pos;
    petal_pos.y -= 3.0; // move up
    petal_pos.x = abs(petal_pos.x) - 0.5;
    petal_pos.z = abs(petal_pos.z) - 0.5;

    // Fast growth front: petal pulse phase is advanced by the feedback
    // growth energy, so bloom waves travel along the flora's own
    // history (self-organizing); kick impulse whips petals open.
    let petal_r = 1.0
        + ctx.bloom_amp * sin(ctx.time * 3.0 + ctx.growth * 2.5 + pos.x * 0.35 + pos.z * 0.35)
        + ctx.bloom * 0.6;
    let petal_d = sdSphere(petal_pos, petal_r);

    let d = smin(stem_d, petal_d, 0.5);

    var mat_id = 1.0;
    if (petal_d < stem_d) { mat_id = 2.0; }

    return vec2<f32>(d, mat_id);
}

// calcNormal(pos): returns vec3 normal
fn calcNormal(p: vec3<f32>, ctx: FloraCtx) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy, ctx).x +
        e.yyx * map(p + e.yyx, ctx).x +
        e.yxy * map(p + e.yxy, ctx).x +
        e.xxx * map(p + e.xxx, ctx).x
    );
}

// --- Main Compute Shader ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // 1. Setup UVs and Ray (Camera)
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(global_id.xy);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;
    let uv01 = vec2<f32>(coords) / res;
    let time = u.config.x;

    // ── Live sliders (updatedParams contract, byte-exact) ─────────
    let intensity = clamp(u.zoom_params.x, 0.0, 1.0); // p1 — bloom emission / SSS strength
    let speed     = clamp(u.zoom_params.y, 0.0, 1.0); // p2 — flythrough + sway + growth + spore flight speed
    let scaleP    = clamp(u.zoom_params.z, 0.0, 1.0); // p3 — flora domain scale
    let mouseInf  = clamp(u.zoom_params.w, 0.0, 1.0); // p4 — cursor well / chase / twist strength

    // ── Audio: ONLY plasmaBuffer[0].xyz + guarded FFT bins 1–8 ────
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fft = 0.0;
    if (arrayLength(&extraBuffer) > 13u) {
        for (var k = 1u; k <= 8u; k = k + 1u) {
            fft += extraBuffer[4u + k];
        }
        fft *= 0.125;
    }

    // Mouse (zoom_config.yz already 0–1, y=0 top); centered coords
    let mouseC = (u.zoom_config.yz - 0.5) * 2.0;
    let mouseDown = u.zoom_config.w > 0.5;

    // ── Persistent state (extraBuffer[133..137], single writer) ───
    // [133] bass envelope   [134] last kick time
    // [135..136] spring-smoothed cursor   [137] prev time (dt)
    var bassEnv = bass;
    var lastKick = time - 10.0;
    var smoothMouse = mouseC;
    var dt = 0.016;
    if (arrayLength(&extraBuffer) >= 139u) {
        bassEnv = extraBuffer[133];
        lastKick = extraBuffer[134];
        smoothMouse = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        dt = clamp(time - extraBuffer[137], 0.001, 0.1);
        if (global_id.x == 0u && global_id.y == 0u) {
            var be = bassEnv;
            be = mix(be, bass, select(0.06, 0.4, bass > be));
            var lk = lastKick;
            if (bass > be * 1.25 + 0.12 && time - lk > 0.3) { lk = time; }
            let sm = mix(smoothMouse, mouseC, vec2<f32>(1.0 - exp(-dt * 12.0)));
            extraBuffer[133] = be;
            extraBuffer[134] = lk;
            extraBuffer[135] = sm.x;
            extraBuffer[136] = sm.y;
            extraBuffer[137] = time;
        }
    }

    // ── Bass-kick bloom shockwave (bounded exp decay) ─────────────
    let kickAge = time - lastKick;
    let kickEnv = exp(-kickAge * 2.5);

    // ── Cursor pursuit with velocity lead (clamped) ───────────────
    var mVel = (mouseC - smoothMouse) / dt;
    mVel *= min(1.0, MAX_MOUSE_VEL / max(length(mVel), 0.001));
    let lead = clamp(mVel * 0.12, vec2<f32>(-0.5), vec2<f32>(0.5));
    let chaseC = mix(mouseC, smoothMouse, 0.35) + lead;

    // ── Click growth-seed shockwaves (guarded ripple loop) ────────
    var shockFlash = 0.0;
    var shockVec = vec2<f32>(0.0);
    let nRip = min(u32(u.config.y), 50u);
    for (var i = 0u; i < nRip; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age > 0.0 && age < 3.0) {
            let rc = (rp.xy - 0.5) * 2.0 * vec2<f32>(res.x / res.y, 1.0);
            let dvec = uv - rc;
            let dist = length(dvec);
            let ring = exp(-pow((dist - age * 2.6) * 7.0, 2.0)) * exp(-age * 2.0);
            shockVec += (dvec / max(dist, 0.05)) * ring;
            shockFlash += ring;
        }
    }
    shockFlash = min(shockFlash, 2.0);
    let bloomImpulse = min(kickEnv + shockFlash * 0.6 + select(0.0, 0.35, mouseDown), 1.5);

    // ── Velocity-advected feedback: growth memory field ───────────
    // Forward flythrough ⇒ content flows radially outward on screen;
    // fetch upstream (clamped), decay, and reuse its energy as the
    // growth-front driver so bloom waves self-organize along history.
    let camSpeed = 1.0 + speed * 3.0;
    let radLen = max(length(uv), 0.05);
    let flowVel = (uv / radLen) * camSpeed * 0.012 + shockVec * 0.08;
    let advPx = clamp(
        vec2<i32>(vec2<f32>(coords) - flowVel * res.y),
        vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)
    );
    let prev = textureLoad(dataTextureC, advPx, 0).rgb;
    let growthEnergy = clamp(luma(prev) * 1.2, 0.0, 1.5);

    // ── Flora context ─────────────────────────────────────────────
    var ctx: FloraCtx;
    ctx.time = time * (0.7 + speed * 1.3);
    ctx.bloom = bloomImpulse;
    ctx.growth = growthEnergy;
    ctx.twist_k = 0.5
        + 0.3 * sin(time * (1.5 + speed * 3.0))
        + chaseC.x * 0.8 * mouseInf
        + bass * 0.3;
    ctx.spacing = mix(7.0, 3.5, scaleP);
    ctx.bloom_amp = 0.3 + speed * 0.4;

    // ── Camera: fast flythrough with smooth (non-strobing) sway ────
    var ro = vec3<f32>(
        time * camSpeed,
        2.0 + sin(time * 1.3) * 0.3 * (0.5 + speed),
        time * camSpeed - 5.0
    );
    ro += vec3<f32>(shockVec * 0.4, 0.0);
    var rd = normalize(vec3<f32>(uv + shockVec * 0.2, 1.0));

    // camera pitch from cursor (Mouse Influence scales the look range)
    let rot = rotate2D(chaseC.y * (0.25 + mouseInf * 0.75));
    rd = vec3<f32>(rd.x, rot[0][0]*rd.y + rot[0][1]*rd.z, rot[1][0]*rd.y + rot[1][1]*rd.z);

    // 2. Raymarch loop
    var t = 0.0;
    let max_t = 50.0;
    var d = 0.0;
    var mat_id = 0.0;

    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let map_res = map(p, ctx);
        d = map_res.x;
        mat_id = map_res.y;
        if(d < 0.001 || t > max_t) { break; }
        t += d;
    }

    // 3. Shading & Subsurface Scattering approximation
    var color = vec3<f32>(0.0);

    if (t < max_t) {
        let p = ro + rd * t;
        let n = calcNormal(p, ctx);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));

        let diff = max(dot(n, l), 0.0);
        let amb = 0.2 + 0.8 * clamp(0.5 + 0.5 * n.y, 0.0, 1.0);

        // base color
        var base_color = vec3<f32>(0.1, 0.8, 0.3); // stem
        if (mat_id == 2.0) {
            base_color = vec3<f32>(0.8, 0.2, 0.6); // petal
        }

        // subsurface scattering approximation
        let sss_sample_dist = 0.5;
        let sss_d = map(p + rd * sss_sample_dist, ctx).x;
        let sss = smoothstep(0.0, sss_sample_dist, sss_sample_dist - sss_d);

        // Audio-reactive color shifting (real audio, not click count)
        let color_shift = vec3<f32>(
            0.5 + 0.5 * sin(time + p.x + fft * 2.0),
            0.5 + 0.5 * sin(time + p.y + mids),
            0.5 + 0.5 * sin(time + p.z + treble)
        );
        let shifted_color = mix(base_color, color_shift, clamp(0.15 + (bass + mids) * 0.25 + bloomImpulse * 0.3, 0.0, 0.8));

        color = shifted_color * diff + shifted_color * amb + shifted_color * sss * (0.3 + intensity * 0.9);

        // Bloom flash: petals glow hot on kicks / growth fronts
        let bloomGlow = (bloomImpulse + growthEnergy * 0.4) * intensity;
        color += vec3<f32>(0.9, 0.4, 1.0) * bloomGlow * select(0.15, 0.6, mat_id == 2.0);

        // fog
        let fog = exp(-0.02 * t * t);
        color = mix(vec3<f32>(0.05, 0.0, 0.1), color, fog);
    } else {
        // background
        color = vec3<f32>(0.05, 0.0, 0.1);
    }

    // 4. Volumetric spore swarm: fast flight + cursor chase + kick burst
    let spore_count = mix(20.0, 160.0, intensity); // p1 also boosts spore emission
    var spore_color = vec3<f32>(0.0);

    let spore_freq = mix(1.2, 3.5, scaleP); // p3 scales spore field too
    // Cursor gravity well rides ahead of the camera at the pursuit point
    let mouse_pos_3d = ro + normalize(vec3<f32>(chaseC * vec2<f32>(res.x / res.y, 1.0), 1.2)) * 5.0;
    let chaseAmt = 0.25 + mouseInf * 0.75 + select(0.0, 0.4, mouseDown);
    var st = 0.0;
    for(var j = 0; j < 20; j++) {
        let sp = ro + rd * st;
        let csp = vec3<f32>(spore_freq);
        let cell3 = floor(sp / csp);
        let h = hash3(cell3);

        // Fast closed-form flight (smooth sin — temporal-coherent)
        let spd = (1.5 + speed * 3.5) * (0.7 + h.z * 0.6);
        let fly = vec3<f32>(
            sin(time * spd + h.x * TAU),
            cos(time * (spd * 0.8) + h.y * TAU),
            sin(time * (spd * 0.6) + h.z * TAU)
        ) * 0.3;

        // Spring-damped pursuit of the cursor well (clamped = velocity clamp)
        let chase = clamp(mouse_pos_3d - sp, vec3<f32>(-0.4), vec3<f32>(0.4)) * chaseAmt * 0.3;
        // Bass-kick burst launch: radial pop from cell center, exp decay
        let launch = (h - vec3<f32>(0.5)) * kickEnv * 0.8;

        let rep_sp = sp - csp * cell3 - csp * 0.5 - fly - chase - launch;

        // mouse gravity well: spores swell near the cursor
        let dist_to_mouse = length(sp - mouse_pos_3d);
        let gravity = mouseInf / (1.0 + dist_to_mouse * dist_to_mouse);

        let sd = length(rep_sp) - (0.05 + 0.05 * gravity + bloomImpulse * 0.04);

        if (sd < 0.1) {
            spore_color += vec3<f32>(0.5, 0.8, 1.0) * (0.5 + treble * 0.6) * 0.1 * spore_count / 100.0;
        }
        st += 0.5;
    }

    color += spore_color;
    color = max(color, vec3<f32>(0.0));

    // 5. Velocity-advected HDR feedback trails (bounded energy)
    var hdr = min(color, vec3<f32>(8.0)) * 0.85 + prev * TRAIL_DECAY * 0.5;
    hdr = min(hdr, vec3<f32>(HDR_CEIL));

    // ── Semantic alpha: bioluminescent emission intensity ─────────
    let alpha = clamp(luma(hdr) * 0.7 + bloomImpulse * 0.2, 0.04, 0.95);

    // ── Real generated depth: raymarched flora hit distance ───────
    let depthVal = clamp(t / max_t, 0.0, 1.0);

    // 6. Outputs — history (A), presentation, depth
    textureStore(dataTextureA, coords, vec4<f32>(hdr, alpha));
    let ldr = acesToneMap(hdr * (0.9 + mids * 0.2));
    textureStore(writeTexture, coords, vec4<f32>(ldr, alpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
