// ═══════════════════════════════════════════════════════════════════
//  astral-kaleidoscope-julia
//  Category: advanced-hybrid
//  Features: kaleidoscope, quaternion-julia, raymarching, depth-aware
//  Complexity: Very High
//  Chunks From: astral-kaleidoscope.wgsl, spec-quaternion-julia.wgsl
//  Upgraded: 2026-11-01
//  Ideas: photo-mapped Schlick reflection on the Julia surface; mirror-gap seam (dark line + bevel at the fold seams)
//  A packing: raw colour + alpha in A (no reader), ACES on writeTexture
//  Created: 2026-04-18
//  By: Agent CB-16 — Generative & Cosmic Enhancer
// ═══════════════════════════════════════════════════════════════════
//  4D Quaternion Julia set rendered through a kaleidoscope mirror
//  system. The fractal is raymarched, then its UV coordinates are
//  folded into kaleidoscope segments with chromatic separation.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn quaternionMul(a: vec4<f32>, b: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(
        a.x*b.x - a.y*b.y - a.z*b.z - a.w*b.w,
        a.x*b.y + a.y*b.x + a.z*b.w - a.w*b.z,
        a.x*b.z - a.y*b.w + a.z*b.x + a.w*b.y,
        a.x*b.w + a.y*b.z - a.z*b.y + a.w*b.x
    );
}

fn quaternionJuliaDE(p: vec3<f32>, c: vec4<f32>) -> f32 {
    var q = vec4<f32>(p, 0.0);
    var dq = vec4<f32>(1.0, 0.0, 0.0, 0.0);
    for (var i: i32 = 0; i < 12; i = i + 1) {
        dq = 2.0 * quaternionMul(q, dq);
        q = quaternionMul(q, q) + c;
        if (dot(q, q) > 256.0) { break; }
    }
    let r = length(q);
    let dr = length(dq);
    return 0.5 * r * log(r) / max(dr, 0.001);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rotate2(v: vec2<f32>, a: f32) -> vec2<f32> {
    let s = sin(a); let c = cos(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    // Kaleidoscope parameters
    // A mirror fan only closes for an integer count (a fractional count left a seam at the atan2 cut).
    let segments = max(3.0, round(u.zoom_params.x * 12.0 + 3.0));
    let rotSpeed = u.zoom_params.y * 0.5;
    let spiralStr = u.zoom_params.z * 2.0;
    let aberration = u.zoom_params.w * 0.02;

    // Center with oscillation
    var center = vec2<f32>(0.5, 0.5) + vec2<f32>(sin(time * 0.3), cos(time * 0.4)) * 0.05;

    // ═══ Kaleidoscope UV Transform ═══
    let toPixel = uv - center;
    var r = length(toPixel);
    var a = atan2(toPixel.y, toPixel.x);

    let spiral = r * spiralStr * sin(time * 0.2);
    let rotation = time * rotSpeed;
    a = a + rotation + spiral;

    let segmentAngle = 2.0 * PI / segments;
    a = a - segmentAngle * floor(a / segmentAngle);
    if (a < 0.0) { a = a + segmentAngle; }
    if (a > segmentAngle * 0.5) { a = segmentAngle - a; }
    // 2026-11 Idea 2: distance to the nearest mirror seam, in angle.
    let seamDist = min(a, segmentAngle * 0.5 - a);

    let r_pulse = r - log(r + 0.1) * (0.75 * sin(time));
    let kUV = center + vec2<f32>(cos(a), sin(a)) * r_pulse;

    // ═══ Quaternion Julia Raymarch ═══
    // HEAD read u.zoom_config.x here, which is engine TIME, so the zoom extrapolated without bound and
    // shrank the Julia set to a dot within seconds. Held at the old slider midpoint, mix(1.5, 4.0, 0.5).
    let zoom = 2.75;
    let morphSpeed = mix(0.1, 1.0, u.zoom_config.y);
    let colorCycles = mix(0.5, 3.0, u.zoom_config.z);
    let detail = mix(6.0, 12.0, u.zoom_config.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    var ro = vec3<f32>(0.0, 0.0, -2.5);
    var rd = normalize(vec3<f32>((kUV - 0.5) * 2.0, 1.0));

    if (isMouseDown) {
        let rotY = (mousePos.x - 0.5) * 3.14;
        let rotX = (mousePos.y - 0.5) * 1.57;
        let cy = cos(rotY); let sy = sin(rotY);
        let cx = cos(rotX); let sx = sin(rotX);
        ro = vec3<f32>(ro.x * cy + ro.z * sy, ro.y, -ro.x * sy + ro.z * cy);
        rd = vec3<f32>(rd.x * cy + rd.z * sy, rd.y, -rd.x * sy + rd.z * cy);
        rd = vec3<f32>(rd.x, rd.y * cx - rd.z * sx, rd.y * sx + rd.z * cx);
    } else {
        let autoRot = time * 0.1;
        let ca = cos(autoRot); let sa = sin(autoRot);
        ro = vec3<f32>(ro.x * ca + ro.z * sa, ro.y, -ro.x * sa + ro.z * ca);
        rd = vec3<f32>(rd.x * ca + rd.z * sa, rd.y, -rd.x * sa + rd.z * ca);
    }

    let t = time * morphSpeed;
    let c = vec4<f32>(
        -0.2 + 0.1 * sin(t * 0.7),
        0.6 + 0.15 * cos(t * 0.5),
        0.1 * sin(t * 0.3),
        0.2 * cos(t * 0.4)
    );

    var t_dist = 0.0;
    var hit = false;
    var steps = 0;
    for (var i: i32 = 0; i < 48; i = i + 1) {
        let p = ro + rd * t_dist;
        let d = quaternionJuliaDE(p * zoom, c) / zoom;
        if (d < 0.001) { hit = true; steps = i; break; }
        if (t_dist > 10.0) { break; }
        t_dist = t_dist + d;
    }

    var col = vec3<f32>(0.0);
    var alpha = 0.0;

    if (hit) {
        let p = ro + rd * t_dist;
        let e = vec2<f32>(0.001, 0.0);
        let n = normalize(vec3<f32>(
            quaternionJuliaDE((p + e.xyy) * zoom, c) - quaternionJuliaDE((p - e.xyy) * zoom, c),
            quaternionJuliaDE((p + e.yxy) * zoom, c) - quaternionJuliaDE((p - e.yxy) * zoom, c),
            quaternionJuliaDE((p + e.yyx) * zoom, c) - quaternionJuliaDE((p - e.yyx) * zoom, c)
        ));
        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.3));
        let diff = max(dot(n, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 32.0);
        let ao = 1.0 - f32(steps) / 48.0;
        let hue = f32(steps) / detail + time * 0.05 * colorCycles;
        let baseColor = vec3<f32>(
            0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
            0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
            0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
        );
        col = baseColor * (diff * 0.7 + 0.3) * ao + vec3<f32>(spec * 0.5);
        // 2026-11 Idea 1: photo-mapped Schlick reflection. The glossy fractal reflects the photo: the
        // reflected view ray indexes the photo at 0.5 + refl.xy * 0.5, weighted by Schlick Fresnel (F0 0.04).
        let reflRay = reflect(rd, n);
        let envPhoto = textureSampleLevel(readTexture, u_sampler, clamp(vec2<f32>(0.5) + reflRay.xy * 0.5, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        let schlick = 0.04 + 0.96 * pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
        col = col + envPhoto * schlick * 0.8;
        alpha = 1.0;
    } else {
        let bgUV = uv + vec2<f32>(sin(time * 0.1 + uv.y * 3.0), cos(time * 0.1 + uv.x * 3.0)) * 0.02;
        col = textureSampleLevel(readTexture, u_sampler, bgUV, 0.0).rgb * 0.3;
        alpha = 0.5;
    }

    // ═══ Chromatic Separation on Kaleidoscope Edges ═══
    let chromaOffset = aberration * (1.0 + spiralStr);
    let uvR = rotate2(kUV - center, chromaOffset) + center;
    let uvB = rotate2(kUV - center, -chromaOffset) + center;

    let bgR = textureSampleLevel(readTexture, u_sampler, clamp(uvR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let bgB = textureSampleLevel(readTexture, u_sampler, clamp(uvB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    if (!hit) {
        col = vec3<f32>(bgR, col.g, bgB);
    }

    // 2026-11 Idea 2: mirror-gap seam. Where the fold meets a mirror there is a dark gap with a thin
    // bevel beside it (the glass edge catching light), on both the fractal and the background.
    let gapW = segmentAngle * 0.03;
    let seamGap = 1.0 - smoothstep(0.0, gapW, seamDist);
    let seamBevel = smoothstep(gapW, gapW * 2.0, seamDist) * (1.0 - smoothstep(gapW * 2.0, gapW * 3.5, seamDist));
    col = col * (1.0 - 0.6 * seamGap) + vec3<f32>(0.08) * seamBevel;

    let display = toneMapACES(col);
    let luma = dot(display, vec3<f32>(0.299, 0.587, 0.114));
    let finalAlpha = mix(0.7, 1.0, luma) * alpha;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(display, finalAlpha));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
