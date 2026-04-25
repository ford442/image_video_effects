// ═══════════════════════════════════════════════════════════════════
//  cosmic-web-structure
//  Category: advanced-hybrid
//  Features: voronoi-filaments, structure-tensor, lic-flow,
//            mouse-driven, depth-aware
//  Complexity: Very High
//  Chunks From: cosmic-web.wgsl, conv-structure-tensor-flow.wgsl
//  Created: 2026-04-18
//  By: Agent CB-16 — Generative & Cosmic Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Cosmic dark-matter filaments rendered through structure-tensor
//  analysis. The filament directions guide Line Integral Convolution
//  flow, creating oriented streaks along the web. Mouse gravity
//  well distorts both the Voronoi field and the tensor eigenvectors.
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

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

fn voronoi3(p: vec3<f32>) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);
    var f1 = 1.0;
    var f2 = 1.0;
    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let r = g + o - f;
                let d = dot(r, r);
                if (d < f1) { f2 = f1; f1 = d; }
                else if (d < f2) { f2 = d; }
            }
        }
    }
    return vec2<f32>(sqrt(f1), sqrt(f2));
}

fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var p_loop = p;
    for (var i = 0; i < 5; i++) {
        let v_dist = voronoi3(p_loop).x;
        v += a * v_dist;
        p_loop = p_loop * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn sampleLuma(uv: vec2<f32>, pixelSize: vec2<f32>, dx: i32, dy: i32) -> f32 {
    let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
    return dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

fn smoothTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
    var sum = vec4<f32>(0.0);
    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let gx = 
                -1.0 * sampleLuma(uv + offset, pixelSize, -1, -1) +
                -2.0 * sampleLuma(uv + offset, pixelSize, -1,  0) +
                -1.0 * sampleLuma(uv + offset, pixelSize, -1,  1) +
                 1.0 * sampleLuma(uv + offset, pixelSize,  1, -1) +
                 2.0 * sampleLuma(uv + offset, pixelSize,  1,  0) +
                 1.0 * sampleLuma(uv + offset, pixelSize,  1,  1);
            let gy = 
                -1.0 * sampleLuma(uv + offset, pixelSize, -1, -1) +
                -2.0 * sampleLuma(uv + offset, pixelSize,  0, -1) +
                -1.0 * sampleLuma(uv + offset, pixelSize,  1, -1) +
                 1.0 * sampleLuma(uv + offset, pixelSize, -1,  1) +
                 2.0 * sampleLuma(uv + offset, pixelSize,  0,  1) +
                 1.0 * sampleLuma(uv + offset, pixelSize,  1,  1);
            let Ix2 = gx * gx;
            let Iy2 = gy * gy;
            let Ixy = gx * gy;
            sum += vec4<f32>(Ix2, Iy2, Ixy, 0.0);
        }
    }
    return sum / 9.0;
}

fn lic(uv: vec2<f32>, direction: vec2<f32>, pixelSize: vec2<f32>, steps: i32, stepSize: f32) -> f32 {
    var pos = uv;
    var accum = 0.0;
    var weight = 0.0;
    for (var i = 0; i < steps; i++) {
        let lum = dot(textureSampleLevel(readTexture, u_sampler, pos, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
        let w = 1.0 - f32(i) / f32(steps);
        accum += lum * w;
        weight += w;
        pos += direction * stepSize * pixelSize;
    }
    pos = uv;
    for (var i = 0; i < steps; i++) {
        let lum = dot(textureSampleLevel(readTexture, u_sampler, pos, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
        let w = 1.0 - f32(i) / f32(steps);
        accum += lum * w;
        weight += w;
        pos -= direction * stepSize * pixelSize;
    }
    return accum / max(weight, 0.001);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv_screen = vec2<f32>(gid.xy) / res;
    var uv = (uv_screen - 0.5) * vec2<f32>(res.x / res.y, 1.0) + 0.5;
    let time = u.config.x * u.zoom_params.z;
    let pixelSize = 1.0 / res;

    // Parameters
    let warpStrength = u.zoom_params.x;
    let density = u.zoom_params.y;
    let licSteps = i32(mix(8.0, 24.0, u.zoom_params.w));
    let coherencyBoost = mix(0.5, 4.0, u.zoom_params.w);

    // Mouse gravity well
    let mouseRaw = u.zoom_config.yz;
    var mouse = (mouseRaw - 0.5) * vec2<f32>(res.x / res.y, 1.0) + 0.5;
    let toMouse = mouse - uv;
    let distMouse = length(toMouse);
    let dirToMouse = select(vec2<f32>(0.0), normalize(toMouse), distMouse > 0.001);
    let pullStrength = 0.3 * smoothstep(0.8, 0.0, distMouse);
    uv += dirToMouse * pullStrength;

    // ═══ Cosmic Web Voronoi ═══
    var p = vec3<f32>(uv * 3.0, time * 0.1);
    let warp = fbm(p);
    p += vec3<f32>(warp * warpStrength);

    var v = voronoi3(p);
    let border = v.y - v.x;
    let filament = 1.0 / (border * 10.0 + 0.05);
    let webDensity = smoothstep(0.0, 1.0, filament * density);

    // ═══ Structure Tensor ═══
    let tensor = smoothTensor(uv_screen, pixelSize);
    let Jxx = tensor.x;
    let Jyy = tensor.y;
    let Jxy = tensor.z;
    let trace = Jxx + Jyy;
    let det = Jxx * Jyy - Jxy * Jxy;
    let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
    let lambda1 = (trace + diff) * 0.5;
    let lambda2 = (trace - diff) * 0.5;

    var eigenvec = vec2<f32>(1.0, 0.0);
    if (abs(Jxy) > 0.0001 || abs(Jxx - lambda1) > 0.0001) {
        eigenvec = normalize(vec2<f32>(lambda1 - Jyy, Jxy));
    }

    let coherency = select(0.0, (lambda1 - lambda2) / (lambda1 + lambda2 + 0.0001), lambda1 + lambda2 > 0.0001);
    let boostedCoherency = pow(coherency, 1.0 / coherencyBoost);

    // Blend filament direction with tensor eigenvector
    let filamentDir = dirToMouse;
    eigenvec = normalize(mix(eigenvec, filamentDir, webDensity * 0.5));

    // Ripple turbulence
    var rippleTurb = vec2<f32>(0.0);
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time * 0.5 - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv_screen - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.3) * 8.0, 2.0));
            let turbAngle = atan2(uv_screen.y - rPos.y, uv_screen.x - rPos.x) + rElapsed * 3.0;
            rippleTurb += vec2<f32>(cos(turbAngle), sin(turbAngle)) * wave * (1.0 - rElapsed / 3.0);
        }
    }
    eigenvec = normalize(eigenvec + rippleTurb * 2.0);

    // LIC along filament-tensor direction
    let licValue = lic(uv_screen, eigenvec, pixelSize, licSteps, 1.5);

    // Color by filament density and flow direction
    let colVoid = vec3<f32>(0.05, 0.0, 0.1);
    var colFilament = vec3<f32>(0.2, 0.6, 1.0);
    let colCore = vec3<f32>(1.0, 1.0, 1.0);

    let flowAngle = atan2(eigenvec.y, eigenvec.x) * 0.15915 + 0.5;
    let flowColor = palette(flowAngle, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));

    var color = mix(colVoid, colFilament, webDensity);
    color = mix(color, colCore, smoothstep(0.8, 1.0, webDensity));
    color = mix(color, flowColor, boostedCoherency * 0.5);
    color = color * (0.3 + 0.7 * boostedCoherency) * (0.5 + 0.5 * licValue);

    textureStore(writeTexture, coord, vec4<f32>(color, licValue));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv_screen, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
