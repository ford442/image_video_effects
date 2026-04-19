// ═══════════════════════════════════════════════════════════════════
//  Hyperbolic Dreamweaver Julia
//  Category: advanced-hybrid
//  Features: hyperbolic-geometry, quaternion-julia, raymarched, depth-aware
//  Complexity: Very High
//  Chunks From: hyperbolic-dreamweaver, spec-quaternion-julia
//  Created: 2026-04-18
//  By: Agent CB-26
// ═══════════════════════════════════════════════════════════════════
//  Raymarches a 4D quaternion Julia set through hyperbolic Poincaré
//  disk space. Hyperbolic translation warps the camera ray, creating
//  impossible infinite fractal geometries within curved space.
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

// ═══ CHUNK: hash22 (from spec-quaternion-julia) ═══
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ═══ CHUNK: quaternionMul (from spec-quaternion-julia) ═══
fn quaternionMul(a: vec4<f32>, b: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(
        a.x*b.x - a.y*b.y - a.z*b.z - a.w*b.w,
        a.x*b.y + a.y*b.x + a.z*b.w - a.w*b.z,
        a.x*b.z - a.y*b.w + a.z*b.x + a.w*b.y,
        a.x*b.w + a.y*b.z - a.z*b.y + a.w*b.x
    );
}

// ═══ CHUNK: quaternionJuliaDE (from spec-quaternion-julia) ═══
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

// ═══ CHUNK: toneMapACES (from spec-quaternion-julia) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

// ═══ CHUNK: hyperbolicDist (from hyperbolic-dreamweaver) ═══
fn hyperbolicDist(z: vec2<f32>) -> f32 {
    let r2 = dot(z, z);
    let safeR2 = min(r2, 0.99);
    return 0.5 * log((1.0 + safeR2) / (1.0 - safeR2));
}

// ═══ CHUNK: hyperbolicTranslate (from hyperbolic-dreamweaver) ═══
fn hyperbolicTranslate(z: vec2<f32>, t: vec2<f32>) -> vec2<f32> {
    let tLen2 = dot(t, t);
    let zDotZ = dot(z, z);
    let zt = dot(z, t);
    let num = z * (1.0 + tLen2) - t * (1.0 - zDotZ + 2.0 * zt);
    let den = 1.0 + tLen2 - 2.0 * zt;
    let safeDen = max(den, 0.0001);
    return num / safeDen;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));

    let zoom = mix(1.5, 4.0, u.zoom_params.x);
    let morphSpeed = mix(0.1, 1.0, u.zoom_params.y);
    let colorCycles = mix(0.5, 3.0, u.zoom_params.z);
    let detail = mix(6.0, 12.0, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Map to Poincaré disk
    let centered = (uv - 0.5) * 2.0;
    let r = length(centered);
    let lodFactor = smoothstep(0.5, 0.95, r);
    let edgeThreshold = step(r, 0.99);

    // Hyperbolic translation animated
    let intensity = 0.3;
    let audioReactivity = 1.0 + u.zoom_config.x * 0.3;
    let t = vec2<f32>(
        cos(time * 0.2 * audioReactivity) * intensity * 0.3,
        sin(time * 0.3 * audioReactivity) * intensity * 0.3
    );
    let translated = hyperbolicTranslate(centered, t);

    // Camera setup in hyperbolic-warped space
    var ro = vec3<f32>(translated * 1.5, -2.5);
    var rd = normalize(vec3<f32>((uv - 0.5) * 2.0, 1.0));

    // Mouse orbit
    if (isMouseDown) {
        let rotY = (mousePos.x - 0.5) * 3.14;
        let rotX = (mousePos.y - 0.5) * 1.57;
        let cy = cos(rotY);
        let sy = sin(rotY);
        let cx = cos(rotX);
        let sx = sin(rotX);
        ro = vec3<f32>(ro.x * cy + ro.z * sy, ro.y, -ro.x * sy + ro.z * cy);
        rd = vec3<f32>(rd.x * cy + rd.z * sy, rd.y, -rd.x * sy + rd.z * cy);
        rd = vec3<f32>(rd.x, rd.y * cx - rd.z * sx, rd.y * sx + rd.z * cx);
    } else {
        let autoRot = time * 0.1;
        let ca = cos(autoRot);
        let sa = sin(autoRot);
        ro = vec3<f32>(ro.x * ca + ro.z * sa, ro.y, -ro.x * sa + ro.z * ca);
        rd = vec3<f32>(rd.x * ca + rd.z * sa, rd.y, -rd.x * sa + rd.z * ca);
    }

    // Animate 4D Julia constant
    let mt = time * morphSpeed;
    let c = vec4<f32>(
        -0.2 + 0.1 * sin(mt * 0.7),
        0.6 + 0.15 * cos(mt * 0.5),
        0.1 * sin(mt * 0.3),
        0.2 * cos(mt * 0.4)
    );

    // Raymarch
    var t_dist = 0.0;
    var hit = false;
    var steps = 0;

    for (var i: i32 = 0; i < 48; i = i + 1) {
        let p = ro + rd * t_dist;
        let d = quaternionJuliaDE(p * zoom, c) / zoom;
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
        alpha = 1.0;
    } else {
        // Background: hyperbolic-distorted image
        let hyperDist = hyperbolicDist(centered);
        let bgUV = uv + vec2<f32>(sin(time * 0.1 + uv.y * 3.0), cos(time * 0.1 + uv.x * 3.0)) * 0.02 * (1.0 + hyperDist);
        col = textureSampleLevel(readTexture, u_sampler, bgUV, 0.0).rgb * 0.3;
        alpha = 0.0;
    }

    // LOD-aware color enhancement
    let colorEnhancement = 1.0 + hyperbolicDist(centered) * 0.2 * (1.0 - lodFactor);
    col *= colorEnhancement;

    // Branchless edge handling
    let display = toneMapACES(col);
    let finalColor = mix(display, vec3<f32>(0.0), 1.0 - edgeThreshold);
    let finalAlpha = alpha * edgeThreshold;

    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, finalAlpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(col, finalAlpha));

    // Depth with hyperbolic modulation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMod = 1.0 + hyperbolicDist(centered) * 0.1 * (1.0 - lodFactor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
