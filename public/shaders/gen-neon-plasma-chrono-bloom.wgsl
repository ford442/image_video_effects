// ═══════════════════════════════════════════════════════════════════
//  Neon Plasma Chrono-Bloom
//  Category: generative
//  Features: raymarched, volumetric, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: radial time lag (the bloom opens from the centre); sheet-intersection filaments
//  A packing: ACES display RGBA (rgb = toned + gamma-encoded colour, a = density/filament coverage); C not read
// ═══════════════════════════════════════════════════════════════════
//  Kept verbatim: 64-step march through the unbounded, domain-warped 3-octave simplex field
//  whose thin sheets are |noise| < 0.3*Intensity; cosine neon palette indexed by accumulated
//  density (+ Hue Shift); threshold bloom above Bloom Threshold; purple fog; held-mouse
//  gravity well + time dilation (HEAD behaviour, now projected under the cursor).
//  Sliders: x Intensity (sheet thickness + gravity pull), y Distortion Speed (field time rate,
//  also scales the radial lag and dilation), z Bloom Threshold, w Hue Shift.
//  Audio (plasmaBuffer[0]): bass -> density gain, mids -> filament thickness, treble -> filament heat.
//  Idea 1  radial time lag     — map(): t_local = t - r*CHRONO_LAG, r = radius from the bloom axis.
//  Idea 2  sheet filaments     — map(): second phase-offset sheet n2; exp(-(d1^2+n2^2)/w^2) tube
//                                where both sheets cross; accumulated in main() as hot lines.
//  HEAD fixes: y was upside down; mouse well used sign-flipped y and a ±aspect scale vs the
//  ±2.25*aspect z=2 plane; audio read extraBuffer[133] (always 0); Reinhard -> ACES; alpha
//  1.0 -> coverage; depth + dataTextureA now written.
// ═══════════════════════════════════════════════════════════════════
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Intensity, .y = Distortion Speed, .z = Bloom Threshold, .w = Hue Shift
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS = 64;
const MAX_DIST = 10.0;
// Camera: ro.z = -2.5, focal 1 -> the z = 2 well plane sits 4.5 units out (spans ±2.25*aspect x ±2.25).
const WELL_PLANE_Z = 2.0;
const WELL_PLANE_SCALE = 4.5;
// Idea 1: seconds of field-time lag per world unit of radius from the bloom axis.
const CHRONO_LAG = 1.6;
// Idea 2: filament tube half-width in (sheet1, sheet2) noise units, and its glow gain.
const FIL_WIDTH = 0.045;
const FIL_GAIN = 2.6;

// 3D Simplex noise
fn mod289(x: vec4<f32>) -> vec4<f32> { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn permute(x: vec4<f32>) -> vec4<f32> { return mod289(((x * 34.0) + 1.0) * x); }
fn taylorInvSqrt(r: vec4<f32>) -> vec4<f32> { return 1.79284291400159 - 0.85373472095314 * r; }

fn snoise(v: vec3<f32>) -> f32 {
    let C = vec2<f32>(1.0 / 6.0, 1.0 / 3.0);
    let D = vec4<f32>(0.0, 0.5, 1.0, 2.0);

    // First corner
    var i = floor(v + dot(v, C.yyy));
    let x0 = v - i + dot(i, C.xxx);

    // Other corners
    let g = step(x0.yzx, x0.xyz);
    let l = 1.0 - g;
    let i1 = min(g.xyz, l.zxy);
    let i2 = max(g.xyz, l.zxy);

    let x1 = x0 - i1 + C.xxx;
    let x2 = x0 - i2 + C.yyy;
    let x3 = x0 - D.yyy;

    // Permutations
    i = mod289(vec4<f32>(i.x, i.y, i.z, 0.0)).xyz;
    let p = permute(permute(permute(
             i.z + vec4<f32>(0.0, i1.z, i2.z, 1.0))
           + i.y + vec4<f32>(0.0, i1.y, i2.y, 1.0))
           + i.x + vec4<f32>(0.0, i1.x, i2.x, 1.0));

    // Gradients: 7x7 points over a square, mapped onto an octahedron.
    // The ring size 17*17 = 289 is close to a multiple of 49 (49*6 = 294)
    let n_ = 0.142857142857; // 1.0/7.0
    let ns = n_ * D.wyz - D.xzx;

    let j = p - 49.0 * floor(p * ns.z * ns.z); // mod(p,7*7)

    let x_ = floor(j * ns.z);
    let y_ = floor(j - 7.0 * x_); // mod(j,N)

    let x = x_ * ns.x + ns.yyyy;
    let y = y_ * ns.x + ns.yyyy;
    let h = 1.0 - abs(x) - abs(y);

    let b0 = vec4<f32>(x.xy, y.xy);
    let b1 = vec4<f32>(x.zw, y.zw);

    let s0 = floor(b0) * 2.0 + 1.0;
    let s1 = floor(b1) * 2.0 + 1.0;
    let sh = -step(h, vec4<f32>(0.0));

    let a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    let a1 = b1.xzyw + s1.xzyw * sh.zzww;

    var p0 = vec3<f32>(a0.xy, h.x);
    var p1 = vec3<f32>(a0.zw, h.y);
    var p2 = vec3<f32>(a1.xy, h.z);
    var p3 = vec3<f32>(a1.zw, h.w);

    let norm = taylorInvSqrt(vec4<f32>(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    var m = max(0.6 - vec4<f32>(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), vec4<f32>(0.0));
    m = m * m;
    return 42.0 * dot(m * m, vec4<f32>(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// Returns (sheet distance, filament strength).
fn map(p: vec3<f32>, t: f32, filWidth: f32) -> vec2<f32> {
    let intensity = u.zoom_params.x;
    let distortionSpeed = u.zoom_params.y;

    // Time dilation and gravity based on mouse (HEAD behaviour; projection fixed)
    var localP = p;
    var localT = t;
    if (u.zoom_config.w > 0.5) { // Mouse down
        let mouseUv = u.zoom_config.yz;
        let aspect = u.config.z / u.config.w;
        // Screen uv (y up) of the cursor, pushed out along its ray to the z = 2 plane.
        let mouseScreen = vec2<f32>((mouseUv.x - 0.5) * aspect, 0.5 - mouseUv.y);
        let mouseWorld = vec3<f32>(mouseScreen * WELL_PLANE_SCALE, WELL_PLANE_Z);
        let dToMouse = length(localP - mouseWorld);

        let gravityRadius = 2.0;
        let pull = smoothstep(gravityRadius, 0.0, dToMouse);

        // Gravity pull
        localP = mix(localP, mouseWorld, pull * 0.5 * u.zoom_params.x);

        // Time dilation
        localT -= pull * 2.0 * distortionSpeed;
    }

    // ── Idea 1: radial time lag ──────────────────────────────────────
    // The field clock trails with radius from the bloom axis (screen centre), so each
    // shell of radius r replays what the centre did CHRONO_LAG*r seconds ago: structure
    // is born on the axis and its phase fronts travel outward like an opening bloom.
    // Soft radius avoids a crease along the axis; the well above bends the fronts.
    let rBloom = sqrt(dot(localP.xy, localP.xy) + 0.09);
    localT -= rBloom * CHRONO_LAG;

    // Domain warp
    var q = localP;

    let baseTime = localT * 0.2 * distortionSpeed;

    var d = 0.0;

    // Multi-octave 3D noise for plasma density
    d += snoise(q * 1.0 + baseTime) * 0.5;
    q.x += d * 0.5;
    d += snoise(q * 2.0 - baseTime * 1.2) * 0.25;
    q.y += d * 0.5;
    let fine = snoise(q * 4.0 + baseTime * 1.5) * 0.125;
    d += fine;

    // Create branching tendrils by absolute value and subtracting from a base density
    let tendrils = abs(d);

    // Surface is where density crosses a threshold
    let baseRadius = 0.3 * intensity;

    // ── Idea 2: sheet-intersection filaments ─────────────────────────
    // A second sheet family: one fresh low octave on the SAME warped domain (so it bends
    // with the plasma), swizzled and phase-offset in space and time, plus the fine octave
    // reused counter-phased. Sheet 1's mid-surface is d = 0, sheet 2's is n2 = 0; the
    // Gaussian in (d, n2) is a thin tube around the curve where the two sheets cross.
    let n2 = snoise(q.yzx * 1.0 + vec3<f32>(3.7, 1.9, 5.3) - baseTime * 0.9) * 0.5 - fine;
    let fil = exp(-(d * d + n2 * n2) / (filWidth * filWidth));

    return vec2<f32>(tendrils - baseRadius, fil);
}

// Palette for neon colors
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    // Oscillating between electric pink, cyan, deep purple
    // Hue shift added
    let hueOffset = u.zoom_params.w;
    let d = vec3<f32>(0.263, 0.416, 0.557) + hueOffset;
    return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<f32>(f32(global_id.x), f32(global_id.y));

    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }
    let pixel = vec2<i32>(global_id.xy);

    // Audio reactivity (plasmaBuffer[0] = bass / mids / treble)
    let audio = plasmaBuffer[0].xyz;
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;
    let audioMod = 1.0 + bass * 0.5;
    let filWidth = FIL_WIDTH * (1.0 + mids * 0.5);
    let filHeat = 1.0 + treble * 2.0;

    // Screen y grows downward; flip so +uv.y is world up.
    let uv = vec2<f32>(coords.x - 0.5 * res.x, 0.5 * res.y - coords.y) / res.y;
    let t = u.config.x;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -2.5);
    let lookAt = vec3<f32>(0.0, 0.0, 0.0);
    let fwd = normalize(lookAt - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let rd = normalize(uv.x * right + uv.y * up + 1.0 * fwd);

    // Raymarching variables
    var p = ro;
    var totalDist = 0.0;
    var accumulatedDensity = 0.0;
    var emissiveGlow = 0.0;
    var filamentGlow = 0.0;
    var firstHit = MAX_DIST;

    let bloomThreshold = u.zoom_params.z;

    // Volumetric raymarching
    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * totalDist;

        let m = map(p, t, filWidth);
        let d = m.x;

        // If inside the volume (distance is negative or very small)
        if (d < 0.05) {
            firstHit = min(firstHit, totalDist);
            // Accumulate density
            let density = smoothstep(0.05, -0.1, d);
            accumulatedDensity += density * 0.05 * audioMod; // Boosted by audio

            // Bloom accumulation for bright parts
            if (density > bloomThreshold) {
                emissiveGlow += (density - bloomThreshold) * 0.1;
            }

            // Idea 2: filament ignition, front-to-back weighted so filaments behind
            // an already-dense sheet stay hidden.
            filamentGlow += m.y * 0.05 * filHeat * max(1.0 - accumulatedDensity, 0.0);

            // Step forward by a small amount to march through the volume
            totalDist += 0.02;
        } else {
            // Step forward by the distance to the surface
            totalDist += d;
        }

        if (totalDist > MAX_DIST || accumulatedDensity > 0.95) {
            break;
        }
    }

    // Color mapping
    let colorT = accumulatedDensity * 2.0 - t * 0.1;
    var col = palette(colorT);

    // Apply accumulated density as opacity
    col *= accumulatedDensity;

    // Add procedural bloom
    col += col * emissiveGlow * 2.0;

    // Idea 2: filaments burn hotter than the sheets they live in — the same neon palette
    // half a cycle on, pushed toward white-hot.
    let filCol = mix(palette(colorT + 0.5), vec3<f32>(1.0, 0.96, 1.0), 0.45);
    col += filCol * filamentGlow * FIL_GAIN;

    // Background fade (fog)
    let fog = 1.0 - exp(-0.1 * totalDist);
    col = mix(col, vec3<f32>(0.02, 0.0, 0.05), fog); // Deep dark purple bg

    // Tonemapping: ACES on display RGB, then HEAD's gamma encode (base clamped >= 0).
    col = acesToneMap(max(col, vec3<f32>(0.0)));
    col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));

    // Semantic alpha: plasma coverage along the ray plus filament glow.
    let alpha = clamp(accumulatedDensity * 1.05 + filamentGlow * 0.5, 0.1, 1.0);
    // Depth: near = 1 at the first sheet entry, 0 where the ray found nothing.
    let depth = 1.0 - clamp(firstHit / MAX_DIST, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    // A = ACES display RGBA (not read back; no trail).
    textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
}
