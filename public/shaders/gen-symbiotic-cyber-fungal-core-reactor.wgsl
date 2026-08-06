// ----------------------------------------------------------------
// Symbiotic Cyber-Fungal Core-Reactor
// Category: generative
// Features: spring-smoothed mouse gravity-well attractor, click
//   spore-burst shockwave (bounded energy), real audio reactivity
//   (bass/mids/treble + guarded FFT bins 1-8), engine-ripple nutrient
//   rings, temporal feedback memory (dataTextureA/C), generated
//   depth, semantic alpha, ACES tone map
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .xyzw = user params p1...p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn cellular(p: vec3<f32>) -> f32 {
    let pFloor = floor(p);
    let pFract = fract(p);
    var minDist = 1.0;

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let cell = vec3<f32>(f32(i), f32(j), f32(k));
                let h = hash33(pFloor + cell);
                let diff = cell + h - pFract;
                let dist = length(diff);
                minDist = min(minDist, dist);
            }
        }
    }
    return minDist;
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p;
    for(var i = 0; i < 4; i++) {
        f += cellular(pos) * amp;
        pos *= 2.0;
        amp *= 0.5;
    }
    return f;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// Frame context: input-reactivity state shared by the distance field
struct ReactorCtx {
    time: f32,
    core_pos: vec3<f32>,
    bass: f32,
    mids: f32,
    treble: f32,
    fft_lo: f32,
    fft_hi: f32,
    pulse: f32,      // click spore-burst energy (bounded 0..1)
    pulse_age: f32,  // seconds since click (scaled time)
    mutate: f32,     // hold-to-mutate surge (mouseDown)
};

fn map(p: vec3<f32>, c: ReactorCtx) -> f32 {
    let core_density = u.zoom_params.x;
    let mycelium_spread = u.zoom_params.y;
    let quantum_noise = u.zoom_params.z;

    var pos = p;

    // Core singularity at the gravity-well attractor (bass growth pulse)
    let core_radius = 0.5 * core_density * (1.0 + c.bass * 0.18);
    let d_core = length(pos - c.core_pos) - core_radius;

    // Gyroid structure for mycelium (mids morph the lattice phase)
    pos *= 1.5;
    pos += c.mids * vec3<f32>(0.35, 0.21, 0.42);
    var d_gyroid = dot(sin(pos), cos(pos.zxy)) - 0.1;

    // Quantum noise modification (mutation surges while mouse held)
    let noise = fbm(pos * 2.0 + c.time * (0.1 + c.mutate * 0.5)) * quantum_noise;
    d_gyroid += noise;

    // Attraction to core
    let dist_to_core = length(p - c.core_pos);
    let pull = smoothstep(2.0, 0.0, dist_to_core);
    d_gyroid -= pull * 0.5;

    // Click spore-burst: expanding shockwave swells the mycelium outward
    let ring = exp(-pow((dist_to_core - c.pulse_age * 2.2) * 3.0, 2.0));
    d_gyroid -= ring * c.pulse * 0.45;

    // Blend core and mycelium
    let d_mycelium = d_gyroid * 0.5 / (1.0 + mycelium_spread);

    return min(d_core, d_mycelium);
}

fn getNormal(p: vec3<f32>, c: ReactorCtx) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, c) - map(p - e.xyy, c),
        map(p + e.yxy, c) - map(p - e.yxy, c),
        map(p + e.yyx, c) - map(p - e.yyx, c)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = vec2<f32>(u.config.zw);
    let coord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    if (coord.x >= dimensions.x || coord.y >= dimensions.y) {
        return;
    }
    let px = vec2<i32>(global_id.xy);

    let uv = (coord - 0.5 * dimensions) / min(dimensions.x, dimensions.y);
    let uv01 = coord / dimensions;
    let tRaw = u.config.x;
    let time = tRaw * u.zoom_params.w; // Temporal Shift slider (live)

    // Real audio (canonical source)
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouseDown = u.zoom_config.w;

    // ── Persistent state: spring-smoothed nutrient attractor + click edge ──
    // extraBuffer[133..136] = attractor pos/vel (uv), [137] = prev mouseDown,
    // [138] = last click timestamp (scaled time; -10 = never fired)
    let sbLen = arrayLength(&extraBuffer);
    let canState = sbLen > 138u;
    let rawMouse = u.zoom_config.yz;
    if (global_id.x == 0u && global_id.y == 0u && canState) {
        let h = 0.016;
        let spx = extraBuffer[133];
        let spy = extraBuffer[134];
        let svx = extraBuffer[135];
        let svy = extraBuffer[136];
        let nvx = clamp(svx + ((rawMouse.x - spx) * 70.0 - svx * 10.0) * h, -4.0, 4.0);
        let nvy = clamp(svy + ((rawMouse.y - spy) * 70.0 - svy * 10.0) * h, -4.0, 4.0);
        extraBuffer[133] = clamp(spx + nvx * h, 0.0, 1.0);
        extraBuffer[134] = clamp(spy + nvy * h, 0.0, 1.0);
        extraBuffer[135] = nvx;
        extraBuffer[136] = nvy;
        let prevDown = extraBuffer[137];
        if (mouseDown > 0.5 && prevDown <= 0.5) {
            extraBuffer[138] = max(time, 0.001);
        } else if (extraBuffer[138] == 0.0) {
            extraBuffer[138] = -10.0;
        }
        extraBuffer[137] = mouseDown;
    }
    var sm = rawMouse;
    var shockT = -10.0;
    if (canState) {
        sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        shockT = extraBuffer[138];
    }

    // Gravity-well attractor + slow autonomous drift: the core hunts nutrients
    let drift = vec2<f32>(sin(time * 0.23), cos(time * 0.17)) * 0.04 * (1.0 + mids * 0.5);
    let core_uv = sm + drift;
    let core_pos = vec3<f32>((core_uv.x - 0.5) * 5.0, -(core_uv.y - 0.5) * 5.0, 0.0);

    // Click spore-burst energy (bounded, decaying)
    let pulse_age = max(time - shockT, 0.0);
    let pulse = select(0.0, exp(-pulse_age * 1.4), shockT > 0.0);
    let mutate = step(0.5, mouseDown);

    // ── Guarded FFT bands (engine bins 1-8 at extraBuffer[6..13], read-only) ──
    var fft_lo = 0.0;
    var fft_hi = 0.0;
    if (sbLen > 13u) {
        fft_lo = (extraBuffer[6] + extraBuffer[7] + extraBuffer[8]) * 0.3333;
        fft_hi = (extraBuffer[11] + extraBuffer[12] + extraBuffer[13]) * 0.3333;
    }

    let ctx = ReactorCtx(time, core_pos, bass, mids, treble, fft_lo, fft_hi, pulse, pulse_age, mutate);

    var ro = vec3<f32>(0.0, 0.0, -4.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slight camera rotation
    let rotMatrix = rot(time * 0.1);
    ro = vec3<f32>(rotMatrix * ro.xz, ro.y).xzy;
    rd = vec3<f32>(rotMatrix * rd.xz, rd.y).xzy;

    var t = 0.0;
    var col = vec3<f32>(0.0);
    var glow = 0.0;
    var hit = false;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p, ctx);

        // Volumetric glow accumulation (treble sparkle emission rate)
        glow += (0.01 + fft_hi * 0.004) / (0.01 + abs(d));

        if (d < 0.001 || t > 10.0) {
            if (d < 0.001) {
                hit = true;
                let n = getNormal(p, ctx);
                let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
                let diff = max(dot(n, l), 0.0);

                // Color mapping
                let dist_to_core = length(p - core_pos);
                let mycelium_color = mix(vec3<f32>(0.1, 0.8, 0.9), vec3<f32>(0.8, 0.1, 0.6), clamp(p.z * 0.5 + 0.5, 0.0, 1.0));
                let deep_crevice = vec3<f32>(0.2, 0.0, 0.4);

                var base_col = mix(deep_crevice, mycelium_color, diff);

                // Audio reactive spore emission (treble shimmer + FFT sparkle)
                base_col += vec3<f32>(0.1, 1.0, 0.5) * (treble * 0.12 + fft_hi * 0.25) * cellular(p * 5.0);
                // Bass growth pulse warms the mycelium veins
                base_col += vec3<f32>(0.5, 0.15, 0.05) * bass * 0.12 * cellular(p * 2.5 + 7.0);
                // Spore-burst ring flash sweeping the surface
                let ring = exp(-pow((dist_to_core - pulse_age * 2.2) * 3.0, 2.0));
                base_col += vec3<f32>(0.6, 1.0, 0.8) * ring * pulse * 0.8;

                // Negative color space near singularity
                if (dist_to_core < u.zoom_params.x * 0.55) {
                    base_col = 1.0 - base_col;
                    base_col *= vec3<f32>(1.0, 0.5, 0.2); // Chromatic aberration effect
                }

                col = base_col;
            }
            break;
        }
        t += d;
    }

    // Apply glow (bass-fed core luminescence)
    col += vec3<f32>(0.05, 0.4, 0.5) * glow * (0.04 + bass * 0.015);

    // Engine ripple shockwaves: nutrient rings that feed the bloom
    var rippleGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rp = u.ripples[i];
        let age = tRaw - rp.z;
        if (age > 0.0) {
            let rr = age * 0.6;
            let rd2 = abs(distance(uv01, rp.xy) - rr);
            rippleGlow += exp(-rd2 * 30.0) * exp(-age * 1.5);
        }
    }
    col += vec3<f32>(0.2, 0.9, 0.7) * rippleGlow * 0.35;

    // Subsurface scattering approximation (cheap distance based fog)
    col = mix(col, vec3<f32>(0.0, 0.05, 0.1), 1.0 - exp(-0.1 * t));

    // ── Temporal feedback memory: growth self-organizes along its history ──
    let prev = textureLoad(dataTextureC, px, 0); // non-filtering history read
    let decay = 0.90 + u.zoom_params.y * 0.06;   // Mycelium Spread = trail persistence
    var trail = prev.rgb * decay + col * (0.22 + bass * 0.08);
    trail = min(trail, vec3<f32>(3.0));
    let nutrient = clamp(mix(prev.a, glow * 0.05 + rippleGlow, 0.12), 0.0, 1.0);
    textureStore(dataTextureA, px, vec4<f32>(trail, nutrient));

    // History steers the live frame: established channels bioluminesce
    let hist = clamp(prev.a, 0.0, 1.0);
    col += prev.rgb * 0.10 * (0.4 + mids * 0.6);
    col += vec3<f32>(0.05, 0.25, 0.2) * hist * fft_lo * 0.3;

    col = acesToneMap(col * (0.95 + mids * 0.15));

    // Generated depth: raymarched hit distance (relief), miss = far plane
    let depth = select(1.0, clamp(t / 10.0, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, px, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Semantic alpha: reactor luminance density
    let alpha = clamp(luma(col) * 1.1 + glow * 0.004 + rippleGlow * 0.2, 0.06, 1.0);
    textureStore(writeTexture, px, vec4<f32>(col, alpha));
}
