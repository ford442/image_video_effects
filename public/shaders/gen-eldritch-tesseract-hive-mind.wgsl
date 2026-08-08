// ----------------------------------------------------------------
// Eldritch Tesseract-Hive Mind
// Category: generative
// Features: 4d-tesseract-raymarch, thin-film-iridescence, voxel-tearing,
//           sentinel-swarm, hdr-feedback-trails, speed-streaks,
//           audio-transient-burst, audio-color-temperature,
//           aces-tone-map, semantic-alpha, generated-depth, fast-motion
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0–1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

// --- CONSTANTS & HELPERS ---
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;
const HDR_CLAMP: f32 = 6.0; // feedback history energy ceiling (stability at speed)

// 4D Rotation matrix helper (any 2-plane)
fn rot4D(theta: f32) -> mat2x2<f32> {
    let c = cos(theta);
    let s = sin(theta);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + vec3<f32>(dot(p3, p3.yxz + vec3<f32>(33.33)));
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// 3D Value Noise for "boolean carving" (temporally coherent — no strobing)
fn vnoise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    let res = mix(
        mix(mix(hash33(p).x, hash33(p + vec3<f32>(1.0, 0.0, 0.0)).x, f2.x),
            mix(hash33(p + vec3<f32>(0.0, 1.0, 0.0)).x, hash33(p + vec3<f32>(1.0, 1.0, 0.0)).x, f2.x), f2.y),
        mix(mix(hash33(p + vec3<f32>(0.0, 0.0, 1.0)).x, hash33(p + vec3<f32>(1.0, 0.0, 1.0)).x, f2.x),
            mix(hash33(p + vec3<f32>(0.0, 1.0, 1.0)).x, hash33(p + vec3<f32>(1.0, 1.0, 1.0)).x, f2.x), f2.y), f2.z
    );
    return res;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// Map function evaluating the 4D Tesseract SDF
fn map(p: vec3<f32>, time: f32, bass: f32) -> vec2<f32> {
    // 4D coordinate initialization (w component dynamically adjusted by mouse)
    let w_offset = (u.zoom_config.z - 0.5) * 2.0; // Mouse Y drives 4th dimension
    var p4 = vec4<f32>(p, w_offset);

    let rotation_speed = u.zoom_params.x;

    // Rotate in 4D space — primary x-z plane, now ~2x faster at default
    let r1 = rot4D(time * (0.25 + rotation_speed * 1.5));
    let x_new = r1[0][0]*p4.x + r1[0][1]*p4.z;
    let z_new = r1[1][0]*p4.x + r1[1][1]*p4.z;
    p4.x = x_new;
    p4.z = z_new;

    // Secondary y-w plane tumble — the hypercube visibly unfolds through itself
    let r2 = rot4D(time * (0.31 + rotation_speed * 0.9) + 1.3);
    let y_new = r2[0][0]*p4.y + r2[0][1]*p4.w;
    let w_new = r2[1][0]*p4.y + r2[1][1]*p4.w;
    p4.y = y_new;
    p4.w = w_new;

    // Core tesseract SDF evaluation
    var d1 = length(max(abs(p4) - vec4<f32>(1.0), vec4<f32>(0.0))) - 0.1;

    // Boolean Carving using noise to create veins
    let carve = vnoise3(p * vec3<f32>(2.0) + vec3<f32>(time * 0.6)) * 0.3;
    d1 = max(d1, -carve);

    // Add voxel tearing based on audio
    let tearing_intensity = u.zoom_params.z;
    let voxel_scale = vec3<f32>(10.0 + (bass * tearing_intensity) * 20.0);
    let voxel_p = floor(p * voxel_scale) / voxel_scale;
    let d2 = length(p - voxel_p) - 0.05;

    // Material ID mix
    // 1.0: Structure, 2.0: Voxel Glitch
    if (d2 < d1 && bass > 0.1 * (1.0 - tearing_intensity)) {
        return vec2<f32>(d2, 2.0);
    }

    return vec2<f32>(d1, 1.0);
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, bass: f32) -> vec2<f32> {
    var dO: f32 = 0.0;
    var mat_id: f32 = 0.0;
    for(var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * vec3<f32>(dO);
        let dS = map(p, time, bass);
        dO += dS.x;
        mat_id = dS.y;
        if(dS.x < SURF_DIST || dO > MAX_DIST) { break; }
    }
    return vec2<f32>(dO, mat_id);
}

// Normal Calculation
fn get_normal(p: vec3<f32>, time: f32, bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, bass).x;
    let n = vec3<f32>(d) - vec3<f32>(
        map(p - e.xyy, time, bass).x,
        map(p - e.yxy, time, bass).x,
        map(p - e.yyx, time, bass).x
    );
    return normalize(n);
}

// Thin film iridescence helper
fn iridescence(view_dir: vec3<f32>, normal: vec3<f32>, shift: f32) -> vec3<f32> {
    let ndotv = max(dot(normal, view_dir), 0.0);
    let t = ndotv + shift;
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(vec3<f32>(6.28318) * (c * vec3<f32>(t) + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let fragCoord = vec2<f32>(pixel);
    var uv = (fragCoord - vec2<f32>(0.5) * resolution) / resolution.y;
    let time = u.config.x;

    // Audio (plasmaBuffer only) — bass/mids/treble
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Audio transient burst envelope (rising-edge on bass, bounded decay) ──
    // extraBuffer[133] = previous bass, [134] = burst envelope. Single writer.
    let bufLen = arrayLength(&extraBuffer);
    if (global_id.x == 0u && global_id.y == 0u && bufLen > 135u) {
        let prevBass = extraBuffer[133];
        var env = extraBuffer[134] * 0.90; // smooth exp decay
        env = max(env, min((bass - prevBass) * 5.0, 2.0)); // rising-edge launch
        extraBuffer[133] = bass;
        extraBuffer[134] = clamp(env, 0.0, 2.0);
    }
    var burst = 0.0;
    if (bufLen > 135u) { burst = extraBuffer[134]; }

    // Parameters (all four sliders LIVE)
    let rotation_speed = u.zoom_params.x;    // p1 — governs 4D spin AND motion energy
    let swarm_density = u.zoom_params.y;     // p2 — sentinel swarm density
    let iridescence_shift = u.zoom_params.w; // p4 — thin-film phase shift

    // Time-warp easing: fast surges, smooth settle — no strobing
    let warpT = time + 0.4 * sin(time * 0.31) * (0.5 + rotation_speed * 0.5);

    // Mouse Interaction (Gravity Well) — mouse_uv is 0–1, y=0 top
    let mouse01 = u.zoom_config.yz;
    let mouse_uv = (mouse01 - vec2<f32>(0.5)) * resolution / resolution.y;
    let mouse_dist = length(uv - mouse_uv);
    if (u.zoom_config.w > 0.5) { // If clicking, distort space
        let pull = 0.5 / (mouse_dist + 0.1);
        uv = uv - (uv - mouse_uv) * pull * 0.05;
    }

    // Camera setup — slow orbit scaled by the speed slider for kinetic framing
    let camA = time * (0.10 + rotation_speed * 0.15);
    let camR = rot4D(camA);
    var ro = vec3<f32>(0.0, 0.0, -3.0);
    let roxz = camR * ro.xz;
    ro = vec3<f32>(roxz.x, 0.0, roxz.y);
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));
    let rdxz = camR * rd.xz;
    rd = normalize(vec3<f32>(rdxz.x, rd.y, rdxz.y));

    // Raymarch
    let rm = raymarch(ro, rd, warpT, bass);
    let d = rm.x;
    let mat_id = rm.y;

    // Audio-reactive color temperature: mids swing the hive cool→warm
    let tempMix = clamp(mids * 0.45, 0.0, 1.0);
    let coolTint = vec3<f32>(0.25, 0.75, 1.0);
    let warmTint = vec3<f32>(1.0, 0.55, 0.25);
    let tempTint = mix(coolTint, warmTint, tempMix);

    var col = vec3<f32>(0.0);

    if (d < MAX_DIST) {
        let p = ro + rd * vec3<f32>(d);
        let n = get_normal(p, warpT, bass);

        if (mat_id == 1.0) {
            // Tesseract Structure - Iridescent Quantum-Slick
            col = iridescence(-rd, n, iridescence_shift + warpT * 0.05);
            // Diffuse lighting
            let light_dir = normalize(vec3<f32>(1.0, 2.0, -1.0));
            let diff = max(dot(n, light_dir), 0.0);
            col = col * diff;

            // Neon glow in the veins — HDR (>1.0), temperature-shifted, burst-flashed
            let glow_factor = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            let huePhase = sin(warpT * 1.7 + p.y) * 0.5 + 0.5; // fast smooth hue cycle
            let glow_color = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), huePhase) * tempTint;
            col += glow_color * vec3<f32>(glow_factor * (1.2 + 2.0 * bass + 2.5 * burst));

        } else if (mat_id == 2.0) {
            // Voxel Tearing — hot HDR glitch, flashes harder on transients
            col = vec3<f32>(1.0, 0.2, 0.5) * vec3<f32>(1.5 + 4.0 * bass + 3.0 * burst);
        }
    }

    // ── Sentinel Swarms: velocity-stretched SPEED STREAKS ─────────────
    // Particles are elongated along their orbital (tangential) velocity and
    // scrolled fast — smooth value noise only, so no per-frame hash strobe.
    let rad = max(length(uv), 0.001);
    let tangential = vec2<f32>(-uv.y, uv.x) / rad;
    let radialDir = uv / rad;
    let swarmSpeed = 4.0 + rotation_speed * 4.0 + bass * 5.0;
    let along = dot(uv, tangential) * 2.5 - warpT * swarmSpeed * 0.28;
    let across = dot(uv, radialDir) * 12.0;
    let n1 = vnoise3(vec3<f32>(along * 2.0, across, warpT * 0.7));
    let n2 = vnoise3(vec3<f32>(along * 5.0 + 31.7, across * 2.0 + 11.3, warpT * 1.3));
    let swarmNoise = n1 * 0.65 + n2 * 0.35;
    let thresh = 0.94 - swarm_density * 0.055;
    let swarm_val = smoothstep(thresh, thresh + 0.06, swarmNoise);

    // Mask swarms to only appear near the structure using depth
    let depth_mask = 1.0 - smoothstep(0.0, 12.0, d);
    let swarm_color = vec3<f32>(0.1, 1.0, 0.55) * tempTint * vec3<f32>(swarm_val * depth_mask * (2.2 + burst * 2.0));
    col += swarm_color;

    // Atmospheric Fog — depth atmosphere, temperature-tinted shadows
    let fogCol = mix(vec3<f32>(0.02, 0.0, 0.05), vec3<f32>(0.05, 0.025, 0.0), tempMix * 0.5);
    col = mix(col, fogCol, 1.0 - exp(-0.02 * d * d));

    // ── HDR velocity feedback trails (dataTextureC → dataTextureA) ────
    // Fast 4D spins and swarm streaks leave decaying light-trails. History is
    // clamped to HDR_CLAMP so speed can never blow up the feedback loop.
    let prev = textureLoad(dataTextureC, pixel, 0);
    let trailDecay = 0.84 + clamp(rotation_speed, 0.0, 2.0) * 0.045; // faster spin → longer streaks
    let history = min(prev.rgb * trailDecay, vec3<f32>(HDR_CLAMP));
    var hdr = col + history;
    hdr = min(hdr, vec3<f32>(HDR_CLAMP));

    // Real generated depth (raymarch hit distance, normalized)
    let depthOut = clamp(d / 12.0, 0.0, 1.0);
    textureStore(dataTextureA, pixel, vec4<f32>(hdr, depthOut));

    // ── ACES tone map (linear HDR workflow, exposure rides audio) ─────
    let exposure = 1.15 + mids * 0.25 + burst * 0.35 + treble * 0.1;
    let outCol = acesToneMap(hdr * exposure);

    // Semantic alpha: luminous intensity + structural hit, never flat 1.0
    let hitMask = 1.0 - f32(d > MAX_DIST);
    let alpha = clamp(0.18 + luma(outCol) * 1.2 + swarm_val * depth_mask * 0.3 + hitMask * 0.15, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(outCol, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
