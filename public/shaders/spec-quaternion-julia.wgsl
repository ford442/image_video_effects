// ═══════════════════════════════════════════════════════════════════
//  spec-quaternion-julia
//  Category: generative
//  Features: quaternion, 4D, raymarching, fractal, audio-reactive
//  Complexity: Very High
//  Chunks From: chunk-library (hash22)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
//  Upgraded: 2026-07-26 (Batch 16 — Optimizer pass)
// ═══════════════════════════════════════════════════════════════════
//  4D Quaternion Julia Set Raymarched
//  Raymarches a 4D quaternion Julia set projected into 3D and then
//  to screen. The 4th dimension animates over time creating organic
//  morphing fractal forms.
//
//  Upgrade notes:
//   - 'Detail Level' slider now truly drives the DE iteration count.
//   - Background alpha is clamped to [0,1] (rgba32float contract).
//   - Bass multiplies morph speed, mids drift the 4D constant c.w.
//   - IQ cosine palette keyed on the minimum orbit-trap distance
//     accumulated over the whole march (classic Julia glow bands).
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Sacred quaternion algebra — component order must never change.
fn quaternionMul(a: vec4<f32>, b: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(
        a.x*b.x - a.y*b.y - a.z*b.z - a.w*b.w,
        a.x*b.y + a.y*b.x + a.z*b.w - a.w*b.z,
        a.x*b.z - a.y*b.w + a.z*b.x + a.w*b.y,
        a.x*b.w + a.y*b.z - a.z*b.y + a.w*b.x
    );
}

// Distance estimator for the 4D quaternion Julia set.
// Returns: x = distance estimate, y = orbit trap (min |q| over iteration).
// The escape radius (256.0) and the 0.5 * r * log(r) / dr estimator are
// preserved verbatim — fractal correctness depends on them. r is clamped
// away from 0 before log() to avoid a first-iteration -inf.
fn quaternionJuliaDE(p: vec3<f32>, c: vec4<f32>, iters: i32) -> vec2<f32> {
    var q = vec4<f32>(p, 0.0);
    var dq = vec4<f32>(1.0, 0.0, 0.0, 0.0);
    var trap = 1000.0;

    for (var i: i32 = 0; i < iters; i = i + 1) {
        dq = 2.0 * quaternionMul(q, dq);
        q = quaternionMul(q, q) + c;
        trap = min(trap, length(q));
        if (dot(q, q) > 256.0) { break; }
    }

    let r = max(length(q), 0.0001);
    let dr = length(dq);
    let dist = 0.5 * r * log(r) / max(dr, 0.001);
    return vec2<f32>(dist, trap);
}

// Classic IQ cosine palette: a + b*cos(2*pi*(c*t+d)).
fn iqCosinePalette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let cp = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(6.28318 * (cp * t + d));
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    // ── Slider wiring (saved-preset contract: zoom_params.x/y/z/w) ──
    let zoom = mix(1.5, 4.0, u.zoom_params.x);          // Fractal Zoom
    let morphSpeedBase = mix(0.1, 1.0, u.zoom_params.y); // Morph Speed
    let colorCycles = mix(0.5, 3.0, u.zoom_params.z);    // Color Cycles
    // Detail Level: PRIMARY role is the DE iteration count (8..16).
    let iters = 8 + i32(u.zoom_params.w * 8.0);
    // Secondary role retained: hue divisor for iteration colouring.
    let detailHue = mix(6.0, 12.0, u.zoom_params.w);

    // ── Audio reactivity (engine FFT: x = bass, y = mids) ──
    let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
    let morphSpeed = morphSpeedBase * (1.0 + bass * 1.5);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Camera setup (aspect-corrected)
    let aspect = res.x / max(res.y, 1.0);
    var ro = vec3<f32>(0.0, 0.0, -2.5);
    var rd = normalize(vec3<f32>((uv - 0.5) * 2.0 * vec2<f32>(aspect, 1.0), 1.0));

    // Mouse orbit (zoom_config.w gating semantics preserved)
    if (isMouseDown) {
        let rotY = (mousePos.x - 0.5) * 3.14;
        let rotX = (mousePos.y - 0.5) * 1.57;
        let cy = cos(rotY);
        let sy = sin(rotY);
        let cx = cos(rotX);
        let sx = sin(rotX);
        ro = vec3<f32>(
            ro.x * cy + ro.z * sy,
            ro.y,
            -ro.x * sy + ro.z * cy
        );
        rd = vec3<f32>(
            rd.x * cy + rd.z * sy,
            rd.y,
            -rd.x * sy + rd.z * cy
        );
        rd = vec3<f32>(
            rd.x,
            rd.y * cx - rd.z * sx,
            rd.y * sx + rd.z * cx
        );
    } else {
        // Auto rotation
        let autoRot = time * 0.1;
        let ca = cos(autoRot);
        let sa = sin(autoRot);
        ro = vec3<f32>(ro.x * ca + ro.z * sa, ro.y, -ro.x * sa + ro.z * ca);
        rd = vec3<f32>(rd.x * ca + rd.z * sa, rd.y, -rd.x * sa + rd.z * ca);
    }

    // Animate 4D Julia constant; mids drift the 4th dimension (c.w).
    let t = time * morphSpeed;
    let c = vec4<f32>(
        -0.2 + 0.1 * sin(t * 0.7),
        0.6 + 0.15 * cos(t * 0.5),
        0.1 * sin(t * 0.3),
        0.2 * cos(t * 0.4) + mids * 0.15
    );

    // Raymarch — track min DE (for alpha) and min orbit trap (for palette).
    var t_dist = 0.0;
    var hit = false;
    var orbitTrap = 1000.0;
    var trapMin = 1000.0;
    var steps = 0;

    for (var i: i32 = 0; i < 64; i = i + 1) {
        let p = ro + rd * t_dist;
        let de = quaternionJuliaDE(p * zoom, c, iters);
        let d = de.x / zoom;
        orbitTrap = min(orbitTrap, d);
        trapMin = min(trapMin, de.y);
        if (d < 0.001) {
            hit = true;
            steps = i;
            break;
        }
        if (t_dist > 10.0) { break; }
        t_dist = t_dist + d;
    }

    var col = vec3<f32>(0.0);
    var alpha = 0.0;

    if (hit) {
        // Normal via central differences
        let p = ro + rd * t_dist;
        let e = vec2<f32>(0.001, 0.0);
        let n = normalize(vec3<f32>(
            quaternionJuliaDE((p + e.xyy) * zoom, c, iters).x - quaternionJuliaDE((p - e.xyy) * zoom, c, iters).x,
            quaternionJuliaDE((p + e.yxy) * zoom, c, iters).x - quaternionJuliaDE((p - e.yxy) * zoom, c, iters).x,
            quaternionJuliaDE((p + e.yyx) * zoom, c, iters).x - quaternionJuliaDE((p - e.yyx) * zoom, c, iters).x
        ));

        // Lighting
        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.3));
        let diff = max(dot(n, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 32.0);
        let ao = 1.0 - f32(steps) / 64.0;
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        // IQ cosine palette keyed on the minimum orbit-trap distance
        // over the whole march — classic Julia glow bands.
        let hue = f32(steps) / detailHue + time * 0.05 * colorCycles;
        let trapKey = clamp(trapMin * 0.35, 0.0, 1.0);
        let baseColor = iqCosinePalette(trapKey * colorCycles + hue);

        // Orbit-trap glow: tight bands where the orbit grazed the origin.
        let glow = exp(-trapMin * 3.0);
        let glowColor = iqCosinePalette(trapKey * colorCycles + hue + 0.15);

        col = baseColor * (diff * 0.7 + 0.3) * ao
            + glowColor * glow * 0.6
            + vec3<f32>(spec * 0.5)
            + baseColor * fresnel * 0.25;
        alpha = 1.0;
    } else {
        // Background: sample input image distorted, plus a faint halo of
        // the nearest fractal approach keyed off the march orbit trap.
        let bgUV = uv + vec2<f32>(sin(time * 0.1 + uv.y * 3.0), cos(time * 0.1 + uv.x * 3.0)) * 0.02;
        col = textureSampleLevel(readTexture, u_sampler, bgUV, 0.0).rgb * 0.3;
        let halo = exp(-orbitTrap * 6.0);
        col = col + iqCosinePalette(clamp(trapMin * 0.35, 0.0, 1.0) * colorCycles) * halo * 0.25;
        // Contract fix: alpha must stay within [0,1] in rgba32float.
        alpha = clamp(orbitTrap / 10.0, 0.0, 1.0);
    }

    // Blue-noise-ish dither to hide banding in the tonemapped gradients.
    let dither = (hash22(vec2<f32>(gid.xy) + vec2<f32>(fract(time), fract(time * 0.7))).x - 0.5) * (1.0 / 255.0);
    let display = toneMapACES(col) + vec3<f32>(dither);
    textureStore(writeTexture, gid.xy, vec4<f32>(display, alpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(col, alpha));
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
