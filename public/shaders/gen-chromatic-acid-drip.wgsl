// ═══════════════════════════════════════════════════════════════════
//  Chromatic Acid Drip
//  Category: generative
//  Features: acid, chromatic, drip, audio-reactive, mouse-interactive, semantic-alpha
//  Complexity: Medium
//  Created: 2026-05-31
//  Updated: 2026-06-01
//  By: Kimi Agent (Bright batch)
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

fn acidColor(dripCoord: f32, t: f32, colorShift: f32) -> vec3<f32> {
    let hue = fract(dripCoord * 2.5 + t * 0.3 + colorShift);
    var col = vec3<f32>(0.0);
    col.r = pow(abs(sin(hue * 6.28318530718 + 0.0)), 0.5);
    col.g = pow(abs(sin(hue * 6.28318530718 + 2.094)), 0.5);
    col.b = pow(abs(sin(hue * 6.28318530718 + 4.189)), 0.5);
    return col * 3.0;
}

fn chromaticDrip(uv: vec2<f32>, time: f32, offset: f32, colorShift: f32) -> vec3<f32> {
    let noiseY = fbm3(vec3<f32>(uv.x * 3.0 + offset, time * 0.5, offset), 4);
    let flowSpeed = 0.3 + 0.2 * sin(uv.x * 6.28318530718 + offset);
    let dripLine = uv.y + noiseY * 0.3 - time * flowSpeed;
    let drip = fract(dripLine);
    let dripIntensity = smoothstep(0.0, 0.15, drip) * smoothstep(0.85, 0.5, drip);

    let flowNoise = fbm3(vec3<f32>(uv * 2.0 + offset, time * 0.3), 3);
    let flowDistort = flowNoise * 0.15;

    let chromaticAmount = 0.03 + 0.02 * sin(time + offset);
    let dripCoord = drip + flowDistort;

    var col = vec3<f32>(0.0);
    col.r = acidColor(dripCoord + chromaticAmount, time, colorShift).r;
    col.g = acidColor(dripCoord, time, colorShift + 0.1).g;
    col.b = acidColor(dripCoord - chromaticAmount, time, colorShift + 0.2).b;

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

    let t = time * (0.3 + audioSpeed * 1.5);
    let centeredUV = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5);
    let scaledUV = centeredUV * (1.5 + scale * 4.0);

    let mouseUV = vec2<f32>((mousePos.x / res.x - 0.5) * aspect, mousePos.y / res.y - 0.5);
    let mouseDist = length(scaledUV - mouseUV);
    let mouseAttraction = mouseDown > 0.5 ? exp(-mouseDist * 6.0) * 2.0 : 0.0;

    var field = metaballField(scaledUV * (0.8 + scale), t);
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

    let c1 = acidColor(0.1, t, hue1);
    let c2 = acidColor(0.4, t, hue2);
    let c3 = acidColor(0.7, t, hue3);

    let edgeColor1 = acidColor(0.2, t, hue1 + 0.15);
    let edgeColor2 = acidColor(0.5, t, hue2 + 0.15);
    let edgeColor3 = acidColor(0.8, t, hue3 + 0.15);

    var color = vec3<f32>(0.02, 0.0, 0.04);

    color += c1 * blob1 * 1.5;
    color += c2 * blob2 * 1.2;
    color += c3 * blob3 * 1.0;

    color += edgeColor1 * edgeGlow1 * 2.0;
    color += edgeColor2 * edgeGlow2 * 2.0;
    color += edgeColor3 * edgeGlow3 * 2.0;

    let drip1 = chromaticDrip(uv, t, 0.0, colorShift);
    let drip2 = chromaticDrip(uv, t * 1.1 + 10.0, 3.33, colorShift + 0.2);
    let drip3 = chromaticDrip(uv, t * 0.9 + 20.0, 6.67, colorShift + 0.4);

    color += drip1 * 0.3 * intensity;
    color += drip2 * 0.25 * intensity;
    color += drip3 * 0.2 * intensity;

    let flowDetail = fbm3(vec3<f32>(scaledUV * 5.0, t * 0.4), 3);
    color += acidColor(flowDetail * 0.5 + 0.5, t, colorShift + 0.3) * flowDetail * 0.15 * intensity;

    color *= 1.0 + intensity * 2.0;
    color = color / (1.0 + color * 0.15);

    let glow = exp(-mouseDist * 4.0) * 0.5;
    color += acidColor(glow, t, colorShift + t * 0.1) * glow * mouseDown;

    textureStore(writeTexture, pixel, vec4<f32>(color, 0.85));
}
