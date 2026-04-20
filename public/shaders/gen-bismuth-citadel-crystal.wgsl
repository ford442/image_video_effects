// ═══════════════════════════════════════════════════════════════════
//  Bismuth Citadel Crystal
//  Category: advanced-hybrid
//  Features: raymarching, crystal-growth, phase-field, iridescence, temporal
//  Complexity: Very High
//  Chunks From: gen-bismuth-crystal-citadel.wgsl, alpha-crystal-growth-phase.wgsl
//  Created: 2026-04-18
//  By: Agent CB-20 — Generative Nature Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Endless bismuth crystal canyon where terrace surfaces exhibit
//  dendritic crystal growth patterns from phase-field simulation.
//  Crystal orientation determines surface color via anisotropic
//  thin-film interference.
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

const IOR_BISMUTH: f32 = 1.8;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: crystalPhaseField (from alpha-crystal-growth-phase.wgsl) ═══
fn crystalPhaseField(p: vec2<f32>, time: f32, supercooling: f32, anisotropy: f32) -> vec4<f32> {
    // Procedural phase field approximation
    let centerDist = length(p);
    let phase = smoothstep(0.5 + supercooling * 0.3, 0.0, centerDist)
              + 0.3 * smoothstep(0.2, 0.0, abs(p.x - p.y * 0.5))
              + 0.3 * smoothstep(0.2, 0.0, abs(p.x + p.y * 0.5));
    let orientation = atan2(p.y, p.x);
    let impurity = hash31(vec3<f32>(p.x * 10.0, p.y * 10.0, 0.0)) * 0.3;
    let temp = -0.2 + impurity * 0.5;
    return vec4<f32>(clamp(phase, 0.0, 1.0), temp, orientation, impurity);
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    var time = u.config.x;
    let twist = p.y * 0.05;
    let p_xz = rot(twist) * p.xz;
    p.x = p_xz.x;
    p.z = p_xz.y;
    let spacingY = 4.0;
    p.y = fract(p.y / spacingY + 0.5) * spacingY - spacingY * 0.5;
    let angle = atan2(p.z, p.x);
    let radius = length(p.xz);
    let segments = 6.0;
    let segmentAngle = 6.28318 / segments;
    let a = angle + 3.14159;
    let a_mod = fract(a / segmentAngle) * segmentAngle - segmentAngle * 0.5;
    p.x = radius * cos(a_mod);
    p.z = radius * sin(a_mod);
    let stepSize = u.zoom_params.x * 0.5 + 0.1;
    var pStep = p;
    pStep.x = floor(pStep.x / stepSize) * stepSize + stepSize * 0.5;
    pStep.z = floor(pStep.z / stepSize) * stepSize + stepSize * 0.5;
    pStep.y = floor(pStep.y / stepSize) * stepSize + stepSize * 0.5;
    let basePos = vec3<f32>(2.0, 0.0, 0.0);
    let d1 = sdBox(p - basePos, vec3<f32>(1.0, 1.5, 1.0));
    let innerSize = vec3<f32>(0.8, 1.6, 0.8);
    let inner_hollow = sdBox(p - basePos, innerSize);
    let terraceSize = stepSize * 0.45;
    let d2 = sdBox(p - pStep, vec3<f32>(terraceSize));
    var d = max(d1, -inner_hollow);
    d = smin(d, d2 - 0.05, 0.1);
    let crystalPos = vec3<f32>(1.5 + sin(u.config.x * 0.5 + p.y) * 0.2, 0.0, 0.0);
    let d3 = sdBox(p - crystalPos, vec3<f32>(0.3, 0.8, 0.3));
    d = smin(d, d3, 0.2);
    return vec2<f32>(d, 1.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

fn fresnelMetal(cosTheta: f32, F0: vec3<f32>) -> vec3<f32> {
    return F0 + (vec3<f32>(1.0) - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }
    var uv = (fragCoord * 2.0 - dims) / dims.y;
    let stepSize = u.zoom_params.x * 0.5 + 0.1;
    let speed = u.zoom_params.y;
    let metallic = u.zoom_params.z;
    let iridescence = u.zoom_params.w;
    let oxidePurity = 0.7 + u.zoom_params.x * 0.3;
    let supercooling = mix(0.1, 0.8, u.zoom_params.x);
    let anisotropy = mix(0.0, 0.5, u.zoom_params.y);
    var time = u.config.x * speed;
    var ro = vec3<f32>(0.0, time * 2.0, -5.0);
    let mouseX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mouseY = (u.zoom_config.z / dims.y) * 2.0 - 1.0;
    let rotY = rot(mouseX * 3.14 + time * 0.2);
    let rotX = rot(mouseY * 1.0 + 0.2);
    var rd = normalize(vec3<f32>(uv, 1.0));
    let temp_rd_yz = rotX * rd.yz;
    rd.y = temp_rd_yz.x;
    rd.z = temp_rd_yz.y;
    let temp_rd_xz = rotY * rd.xz;
    rd.x = temp_rd_xz.x;
    rd.z = temp_rd_xz.y;
    let ta = vec3<f32>(0.0, time * 2.0 + 2.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);
    var t = 0.0;
    var d = 0.0;
    var m = -1.0;
    let maxSteps = 100;
    let maxDist = 50.0;
    for (var i = 0; i < maxSteps; i++) {
        var p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        if (d < 0.001 || t > maxDist) { break; }
        t += d * 0.8;
    }
    var col = vec3<f32>(0.02, 0.02, 0.03);
    col += vec3<f32>(0.05, 0.08, 0.12) * max(0.0, rd.y);
    var alpha = 1.0;
    if (t < maxDist) {
        var p = ro + rd * t;
        let n = calcNormal(p);
        let v = normalize(ro - p);
        let mouseLightPos = vec3<f32>(
            (u.zoom_config.y / dims.x - 0.5) * 10.0,
            ro.y + 2.0,
            (u.zoom_config.z / dims.y - 0.5) * 10.0 + 3.0
        );
        let lig = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let l_mouse = normalize(mouseLightPos - p);
        let dif = max(dot(n, lig), 0.0);
        let dif_mouse = max(dot(n, l_mouse), 0.0);
        let hal = normalize(lig - rd);
        let spec = pow(max(dot(n, hal), 0.0), 32.0);
        let ndotv = max(dot(n, v), 0.0);
        let fresnel = pow(1.0 - ndotv, 5.0);

        // ═══ CHUNK: crystal phase-field growth pattern ═══
        let phaseState = crystalPhaseField(p.xz * 0.5, u.config.x, supercooling, anisotropy);
        let phase = phaseState.r;
        let orientation = phaseState.b;
        let impurity = phaseState.a;
        let interfaceMask = smoothstep(0.3, 0.5, phase) * smoothstep(0.7, 0.5, phase);

        // Orientation-based color (from alpha-crystal-growth-phase)
        let orientNorm = fract(orientation / 6.283185307);
        let h6 = orientNorm * 6.0;
        let c = 0.8;
        let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
        var crystalColor: vec3<f32>;
        if (h6 < 1.0) { crystalColor = vec3(c, x, 0.3); }
        else if (h6 < 2.0) { crystalColor = vec3(x, c, 0.3); }
        else if (h6 < 3.0) { crystalColor = vec3(0.3, c, x); }
        else if (h6 < 4.0) { crystalColor = vec3(0.3, x, c); }
        else if (h6 < 5.0) { crystalColor = vec3(x, 0.3, c); }
        else { crystalColor = vec3(c, 0.3, x); }

        let interferenceOffset = p.y * 0.1 + p.x * 0.05 + u.config.x * 0.1;
        let iriPhase = fresnel * iridescence + interferenceOffset;
        let c_a = vec3<f32>(0.5, 0.5, 0.5);
        let c_b = vec3<f32>(0.5, 0.5, 0.5);
        let c_c = vec3<f32>(1.0, 1.0, 0.8);
        let c_d = vec3<f32>(0.0, 0.33, 0.67);
        let iridColor = palette(iriPhase, c_a, c_b, c_c, c_d);
        let baseColor = vec3<f32>(0.08, 0.08, 0.1);
        let F0_bismuth = vec3<f32>(0.75, 0.8, 0.85);
        let metalFresnel = fresnelMetal(ndotv, F0_bismuth * metallic);
        var litColor = baseColor * (dif * 0.7 + dif_mouse * 0.5 + 0.2);
        litColor += iridColor * fresnel * 0.8 * oxidePurity;
        litColor += vec3<f32>(1.0) * spec * metallic;
        // Blend crystal growth colors
        litColor = mix(litColor, crystalColor * (0.5 + 0.5 * dif), interfaceMask * 0.6);
        litColor = mix(litColor, vec3<f32>(0.8, 0.6, 0.4), impurity * 0.2);
        let terracePattern = sin(p.x * 10.0) * sin(p.y * 10.0) * sin(p.z * 10.0);
        litColor += vec3<f32>(0.3, 0.5, 0.6) * max(0.0, terracePattern) * fresnel * 0.5;
        col = litColor;
        let ao = 1.0 - f32(100) / f32(maxSteps);
        col *= mix(0.5, 1.0, ao);
        col = mix(col, vec3<f32>(0.02, 0.02, 0.03), 1.0 - exp(-0.015 * t));
        let oxideTransmission = (1.0 - metallic * 0.8) * oxidePurity;
        alpha = mix(0.3, 1.0, metallic * 0.7 + fresnel * 0.3);
    } else {
        alpha = 0.9;
    }
    col *= 1.0 - 0.3 * length(uv);
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(t / maxDist, 0.0, 0.0, 0.0));
}
