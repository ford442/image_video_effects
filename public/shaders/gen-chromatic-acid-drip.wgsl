// ═══════════════════════════════════════════════════════════════════
//  Chromatic Acid Drip
//  Category: generative
//  Features: acid, chromatic, drip, audio-reactive, mouse-interactive,
//            semantic-alpha, upgraded-rgba, temporal, chromatic-aberration
//  Complexity: Medium
//  Created: 2026-05-31
//  Updated: 2026-06-07
//  By: Kimi Agent Upgrade
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

// --- Simplex noise helpers (3D) ---
fn mod289_3(v: vec3<f32>) -> vec3<f32> { return v - floor(v * (1.0 / 289.0)) * 289.0; }
fn mod289_4(v: vec4<f32>) -> vec4<f32> { return v - floor(v * (1.0 / 289.0)) * 289.0; }
fn permute(v: vec4<f32>) -> vec4<f32> { return mod289_4(((v * 34.0) + 10.0) * v); }
fn taylorInvSqrt(v: vec4<f32>) -> vec4<f32> { return 1.79284291400159 - 0.85373472095314 * v; }

fn snoise3(v: vec3<f32>) -> f32 {
    let C = vec2<f32>(1.0/6.0, 1.0/3.0);
    let D = vec4<f32>(0.0, 0.5, 1.0, 2.0);
    var i = floor(v + dot(v, C.yyy));
    let x0 = v - i + dot(i, C.xxx);
    let g = step(x0.yzx, x0.xyz);
    let l = 1.0 - g;
    let i1 = min(g.xyz, l.zxy);
    let i2 = max(g.xyz, l.zxy);
    let x1 = x0 - i1 + C.xxx;
    let x2 = x0 - i2 + C.yyy;
    let x3 = x0 - D.yyy;
    i = mod289_3(i);
    let p = permute(permute(permute(
        i.z + vec4<f32>(0.0, i1.z, i2.z, 1.0))
        + i.y + vec4<f32>(0.0, i1.y, i2.y, 1.0))
        + i.x + vec4<f32>(0.0, i1.x, i2.x, 1.0));
    var n_ = 0.142857142857;
    let ns = n_ * D.wyz - D.xzx;
    let j = p - 49.0 * floor(p * ns.z * ns.z);
    let x_ = floor(j * ns.z);
    let y_ = floor(j - 7.0 * x_);
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
    let norm = taylorInvSqrt(vec4<f32>(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    var m = max(0.5 - vec4<f32>(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), vec4<f32>(0.0));
    m *= m;
    return 105.0 * dot(m * m, vec4<f32>(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

fn fbm3(p: vec3<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        v += a * snoise3(pp);
        pp *= 2.0;
        a *= 0.5;
    }
    return v;
}

// ═══ CHUNK: acesToneMap (standard ACES) ═══
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: phToColor (universal indicator pH→RGB) ═══
fn phToColor(ph: f32) -> vec3<f32> {
    let p = clamp(ph, 0.0, 14.0);
    let c0 = vec3<f32>(1.0, 0.0, 0.2);   // pH 0  strong acid
    let c1 = vec3<f32>(1.0, 0.6, 0.0);   // pH 3.5 weak acid
    let c2 = vec3<f32>(0.0, 0.8, 0.3);   // pH 7   neutral
    let c3 = vec3<f32>(0.0, 0.4, 1.0);   // pH 9   weak base
    let c4 = vec3<f32>(0.6, 0.0, 1.0);   // pH 14  strong base
    let t1 = smoothstep(0.0, 3.5, p);
    let t2 = smoothstep(3.5, 7.0, p);
    let t3 = smoothstep(7.0, 9.0, p);
    let t4 = smoothstep(9.0, 14.0, p);
    var col = mix(c0, c1, t1);
    col = mix(col, c2, t2);
    col = mix(col, c3, t3);
    col = mix(col, c4, t4);
    return col;
}

// ═══ CHUNK: Snell's Law / Critical Angle ═══
fn snellRefract(incident: f32, n1: f32, n2: f32) -> f32 {
    let sinTheta2 = (n1 / n2) * sin(incident);
    return asin(clamp(sinTheta2, -1.0, 1.0));
}

fn criticalAngle(n1: f32, n2: f32) -> f32 {
    return asin(clamp(n2 / n1, 0.0, 1.0));
}

fn metaballField(p: vec2<f32>, time: f32) -> f32 {
    var field = 0.0;

    for (var i: i32 = 0; i < 7; i = i + 1) {
        let fi = f32(i);
        let phase = fi * 0.93 + time * (0.3 + fi * 0.1);
        let bx = sin(phase * 1.1) * 0.4 + sin(phase * 0.7 + fi) * 0.15;
        let by = cos(phase * 0.9) * 0.35 + cos(phase * 1.3 + fi * 0.5) * 0.15 + fi * 0.05;
        let bpos = vec2<f32>(bx, by);
        let r = 0.06 + 0.04 * sin(phase * 1.5);
        let d = length(p - bpos);
        field += r / (d + 0.005);
    }

    for (var i: i32 = 7; i < 12; i = i + 1) {
        let fi = f32(i);
        let phase = fi * 1.27 + time * 0.5;
        let bx = sin(phase * 0.8) * 0.5 + 0.1;
        let by = cos(phase * 1.1) * 0.3 - 0.3 + sin(phase * 0.4) * 0.1;
        let bpos = vec2<f32>(bx, by);
        let r = 0.04 + 0.02 * sin(phase * 2.0);
        let d = length(p - bpos);
        field += r * r / (d * d + 0.001);
    }

    return field;
}

// Drip color changes as it falls through pH gradient
fn phDripColor(dripCoord: f32, t: f32, colorShift: f32, phGradient: f32) -> vec3<f32> {
    let ph = fract(dripCoord * 2.5 + t * 0.3 + colorShift + phGradient) * 14.0;
    return phToColor(ph);
}

fn chromaticDrip(uv: vec2<f32>, time: f32, offset: f32, colorShift: f32, phCycle: f32, mids: f32) -> vec3<f32> {
    let noiseY = fbm3(vec3<f32>(uv.x * 3.0 + offset, time * 0.5, offset), 4);
    // Mids control drip speed
    let flowSpeed = 0.3 + 0.2 * sin(uv.x * 6.28318530718 + offset) + mids * 0.5;
    let dripLine = uv.y + noiseY * 0.3 - time * flowSpeed;
    let drip = fract(dripLine);
    let dripIntensity = smoothstep(0.0, 0.15, drip) * smoothstep(0.85, 0.5, drip);

    let flowNoise = fbm3(vec3<f32>(uv * 2.0 + offset, time * 0.3), 3);
    let flowDistort = flowNoise * 0.15;

    // pH changes as drip falls (lower in frame = more acidic, higher = more basic)
    let fallPH = mix(2.0, 12.0, drip) + phCycle;
    let chromaticAmount = 0.03 + 0.02 * sin(time + offset);
    let dripCoord = drip + flowDistort;

    var col = vec3<f32>(0.0);
    col.r = phDripColor(dripCoord + chromaticAmount, time, colorShift, fallPH * 0.1).r;
    col.g = phDripColor(dripCoord, time, colorShift + 0.1, fallPH * 0.1).g;
    col.b = phDripColor(dripCoord - chromaticAmount, time, colorShift + 0.2, fallPH * 0.1).b;

    col *= dripIntensity * (1.0 + flowNoise * 0.5);
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let aspect = res.x / res.y;

    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let audioSpeed = speed * (0.85 + bass * 0.6);
    let audioIntensity = intensity * (0.9 + treble * 0.5);
    let audioColor = colorShift + mids * 0.2;

    // pH oscillation driven by bass: 0→14→0 cycle
    let phCycle = 7.0 + 7.0 * sin(time * (0.5 + bass * 2.0));

    let t = time * (0.3 + audioSpeed * 1.5);
    let centeredUV = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5);
    let scaledUV = centeredUV * (1.5 + scale * 4.0);

    let mouseUV = vec2<f32>((mousePos.x / res.x - 0.5) * aspect, mousePos.y / res.y - 0.5);
    let mouseDist = length(scaledUV - mouseUV);

    // Mouse creates acid/base splashes with realistic color shifts
    let splashPH = select(2.0, 12.0, mouseDown > 0.5 && fract(time * 0.7) > 0.5);
    let mouseAttraction = select(0.0, exp(-mouseDist * 6.0) * 2.0, mouseDown > 0.5);

    // Critical-angle refraction distortion (water-air ~48.6°)
    let crit = criticalAngle(1.33, 1.0);
    let refractUV = scaledUV + vec2<f32>(
        sin(scaledUV.y * 3.0 + t) * 0.02 * sin(crit),
        cos(scaledUV.x * 3.0 + t) * 0.02 * sin(crit)
    ) * bass;

    var field = metaballField(refractUV * (0.8 + scale), t);
    field += mouseAttraction * 3.0;

    let fieldThreshold1 = 2.5;
    let fieldThreshold2 = 3.5;
    let fieldThreshold3 = 4.5;

    let blob1 = smoothstep(fieldThreshold1 + 0.5, fieldThreshold1, field);
    let blob2 = smoothstep(fieldThreshold2 + 0.5, fieldThreshold2, field);
    let blob3 = smoothstep(fieldThreshold3 + 0.5, fieldThreshold3, field);

    let edgeGlow1 = smoothstep(fieldThreshold1 + 0.8, fieldThreshold1, field) - blob1;
    let edgeGlow2 = smoothstep(fieldThreshold2 + 0.6, fieldThreshold2, field) - blob2;
    let edgeGlow3 = smoothstep(fieldThreshold3 + 0.5, fieldThreshold3, field) - blob3;

    let hue1 = 0.0 + colorShift;
    let hue2 = 0.33 + colorShift;
    let hue3 = 0.66 + colorShift;

    let c1 = phToColor(fract(hue1 + phCycle / 14.0) * 14.0);
    let c2 = phToColor(fract(hue2 + phCycle / 14.0) * 14.0);
    let c3 = phToColor(fract(hue3 + phCycle / 14.0) * 14.0);

    let edgeColor1 = phToColor(fract(hue1 + 0.15 + phCycle / 14.0) * 14.0);
    let edgeColor2 = phToColor(fract(hue2 + 0.15 + phCycle / 14.0) * 14.0);
    let edgeColor3 = phToColor(fract(hue3 + 0.15 + phCycle / 14.0) * 14.0);

    var color = vec3<f32>(0.02, 0.0, 0.04);

    color += c1 * blob1 * 1.5;
    color += c2 * blob2 * 1.2;
    color += c3 * blob3 * 1.0;

    color += edgeColor1 * edgeGlow1 * 2.0;
    color += edgeColor2 * edgeGlow2 * 2.0;
    color += edgeColor3 * edgeGlow3 * 2.0;

    let drip1 = chromaticDrip(uv, t, 0.0, colorShift, phCycle, mids);
    let drip2 = chromaticDrip(uv, t * 1.1 + 10.0, 3.33, colorShift + 0.2, phCycle, mids);
    let drip3 = chromaticDrip(uv, t * 0.9 + 20.0, 6.67, colorShift + 0.4, phCycle, mids);

    color += drip1 * 0.3 * intensity;
    color += drip2 * 0.25 * intensity;
    color += drip3 * 0.2 * intensity;

    let flowDetail = fbm3(vec3<f32>(refractUV * 5.0, t * 0.4), 3);
    color += phToColor(fract(flowDetail * 0.5 + 0.5 + phCycle / 14.0) * 14.0) * flowDetail * 0.15 * intensity;

    // Mouse splash glow with pH color
    let glow = exp(-mouseDist * 4.0) * 0.5;
    color += phToColor(splashPH) * glow * mouseDown;

    // ═══ TEMPORAL FEEDBACK ═══
    let prev = textureSampleLevel(dataTextureC, u_sampler, (vec2<f32>(pixel) + 0.5) / res, 0.0);
    color = mix(prev.rgb * 0.96, color, 0.25);
    textureStore(dataTextureA, pixel, vec4<f32>(color, 1.0));

    // ═══ CHROMATIC ABERRATION ═══
    let caStr = 0.003 * (1.0 + bass);
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    // ═══ ACES TONE MAP + SEMANTIC ALPHA ═══
    color = acesToneMap(color * 1.1);
    let alpha = clamp(length(color) * 1.2, 0.2, 0.95);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
}
