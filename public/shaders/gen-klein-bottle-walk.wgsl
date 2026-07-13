// ═══════════════════════════════════════════════════════════════════
//  Klein Bottle Walk
//  Category: generative
//  Features: generative, audio-reactive, upgraded-rgba, mouse-gravity-well,
//            click-shockwaves, attack-release-envelopes, temporal-feedback
//  Complexity: High
//  Created: 2026-05-23
//  Upgraded: 2026-07-13
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        val = val + amp * noise(p * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return val;
}

// Klein bottle parametric with UV mapping
fn kleinBottlePoint(u: f32, v: f32, r: f32) -> vec3<f32> {
    let cu = cos(u);
    let su = sin(u);
    let cv = cos(v);
    let sv = sin(v);
    let x = (r + cu * 0.5) * cv;
    let y = (r + cu * 0.5) * sv;
    let z = su * 0.5;
    return vec3<f32>(x, y, z);
}

fn hue2rgb(h: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(h + k) * 6.0 - 3.0);
    return clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Attack/release envelope follower — state carried through dataTextureC -> dataTextureA
fn envFollow(prev: f32, raw: f32, attack: f32, release: f32) -> f32 {
    let delta = raw - prev;
    let rate = select(release, attack, delta > 0.0);
    return clamp(prev + delta * rate, 0.0, 2.0);
}

// Click bursts / shockwaves from ripple buffer
fn shockwave(uv: vec2<f32>, time: f32) -> f32 {
    var shock = 0.0;
    for (var i: i32 = 0; i < 50; i = i + 1) {
        let rp = u.ripples[i];
        let rippleActive = rp.w > 0.001 && rp.z > 0.0;
        let age = max(time - rp.z, 0.0);
        let d = length(uv - rp.xy);
        let wave = rp.w * exp(-age * 1.8) * exp(-(d - age * 0.22) * (d - age * 0.22) / 0.003);
        shock = shock + wave * f32(rippleActive);
    }
    return clamp(shock, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;
    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;

    let param1 = u.zoom_params.x;
    let param2 = u.zoom_params.y;
    let param3 = u.zoom_params.z;
    let param4 = u.zoom_params.w;

    // Envelope state carried through dataTextureC -> dataTextureA
    let prevData = textureLoad(dataTextureC, pixel, 0);
    let eBass = envFollow(prevData.r, bass, 0.28, 0.035);
    let eMids = envFollow(prevData.g, mids, 0.24, 0.04);
    let eTreble = envFollow(prevData.b, treble, 0.30, 0.03);

    // Mouse gravity well and click shockwaves
    let mouseVec = uv01 - mouse;
    let mouseDist = length(mouseVec);
    let gravity = 1.0 / (mouseDist + 0.12);
    let gravityWell = clamp(gravity * 0.08, 0.0, 1.0) * (1.0 + f32(mouseDown) * 0.5);
    let shock = shockwave(uv01, time) * (1.0 + f32(mouseDown) * 0.4);

    // Walk position on Klein bottle surface — mouse gravity bends speed & radius
    let walkSpeed = mix(0.1, 0.5, param2) * (1.0 + gravityWell * 0.35 + eBass * 0.15);
    let walkU = time * walkSpeed + uv.x * TAU * 2.0 + gravityWell * 0.5;
    let walkV = time * walkSpeed * 0.7 + uv.y * TAU * 2.0 + eMids * 0.2;
    let baseRadius = 1.0 + eBass * 0.25 + shock * 0.15;
    let radiusWarp = baseRadius + gravityWell * 0.35;

    let kb = kleinBottlePoint(walkU, walkV, radiusWarp);

    // Surface texture from FBM
    let texCoord = vec2<f32>(walkU / TAU, walkV / TAU);
    let surfaceNoise = fbm(texCoord * mix(4.0, 16.0, param3) + vec2<f32>(time * 0.05) + gravityWell, 4);

    // Curvature approximation for lighting
    let kb_u = kleinBottlePoint(walkU + 0.01, walkV, radiusWarp);
    let kb_v = kleinBottlePoint(walkU, walkV + 0.01, radiusWarp);
    let du = kb_u - kb;
    let dv = kb_v - kb;
    let normal = normalize(cross(du, dv));

    let lightDir = normalize(vec3<f32>(sin(time * 0.2 + eMids), cos(time * 0.15 + eTreble), 0.8));
    let diffuse = max(dot(normal, lightDir), 0.0);
    let specular = pow(max(dot(normal, normalize(lightDir + vec3<f32>(0.0, 0.0, 1.0))), 0.0), 32.0);

    // Audio-driven color with envelope smoothing
    let hue = fract(kb.z * 0.3 + surfaceNoise * 0.4 + time * 0.02 + eMids * 0.15 + gravityWell * 0.1);
    let sat = mix(0.3, 0.85, param4 + eTreble * 0.25);
    let val = mix(0.2, 1.0, diffuse + surfaceNoise * 0.3 + eBass * 0.3);

    let rgb = hue2rgb(hue) * sat + vec3<f32>(1.0 - sat) * val;
    let specColor = vec3<f32>(1.0, 0.9, 0.7) * specular * (1.0 + eTreble);

    var finalRGB = rgb * val + specColor;
    finalRGB = finalRGB + vec3<f32>(0.4, 0.5, 0.7) * shock * 0.6;

    // Temporal feedback trails via readTexture
    let decay = 0.94 - param4 * 0.03;
    let prevColor = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;
    let blend = 0.18 + eBass * 0.12 + shock * 0.15;
    finalRGB = mix(prevColor * decay, finalRGB, blend);

    let alpha = clamp(diffuse * 0.4 + surfaceNoise * 0.25 + specular * 0.2 + shock * 0.25 + gravityWell * 0.1 + 0.12, 0.0, 1.0);
    let finalColor = vec4<f32>(acesToneMap(finalRGB * 1.1), alpha);

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let interaction = clamp(gravityWell * 0.5 + shock, 0.0, 1.0);

    textureStore(writeTexture, pixel, finalColor);
    textureStore(dataTextureA, pixel, vec4<f32>(eBass, eMids, eTreble, interaction));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth * 0.5 + alpha * 0.3, 0.0, 0.0, 0.0));
}
