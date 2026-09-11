// ═══════════════════════════════════════════════════════════════════
//  Ethereal Quantum-Glass Nautilus
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-11
//  Ideas: chamber septa walls between adjacent spiral chambers; pearl nacre luster on inner chamber ridges
//  A packing: ACES display RGBA in A
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
  zoom_params: vec4<f32>,  // .x = Refraction Index, .y = Spiral Tightness, .z = Iridescence Shift, .w = Audio Reactivity
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 20.0;
const SURF_DIST: f32 = 0.005;
const TAU: f32 = 6.28318530718;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453);
}

fn voronoi(p: vec3<f32>) -> f32 {
    let n = floor(p);
    let f = fract(p);
    var md = 8.0;
    for (var i = -1; i <= 1; i++) {
        for (var j = -1; j <= 1; j++) {
            for (var k = -1; k <= 1; k++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let d = g + o - f;
                let dist = dot(d, d);
                if (dist < md) {
                    md = dist;
                }
            }
        }
    }
    return md;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Log-spiral nautilus map with chamber septa walls (native idea 1).
fn map(p_in: vec3<f32>, audioReactive: f32, spiralTightness: f32) -> f32 {
    var p = p_in;

    let pulse = 1.0 + audioReactive * 0.2 * sin(u.config.x * 2.0);
    p *= 1.0 / pulse;

    let a = atan2(p.z, p.x);
    let r = length(p.xz);

    let b = spiralTightness;
    let theta = log(max(r, 0.001)) / b;

    var n = theta - a / TAU;
    let nf = floor(n);
    let nf1 = nf + 1.0;

    let r0 = exp((nf + a / TAU) * b);
    let r1 = exp((nf1 + a / TAU) * b);

    let d0 = length(vec2<f32>(r - r0, p.y)) - r0 * 0.4;
    let d1 = length(vec2<f32>(r - r1, p.y)) - r1 * 0.4;

    var d = min(d0, d1);

    // Chamber septa: radial partition walls between adjacent spiral chambers.
    let chamberFrac = fract(n);
    let nearSeptum = min(chamberFrac, 1.0 - chamberFrac);
    let radialWall = nearSeptum * r * 7.5;
    let septaPlane = length(vec2<f32>(radialWall, p.y * 0.55)) - 0.035;
    d = min(d, septaPlane);

    let vNoise = voronoi(p * 20.0);
    d += vNoise * 0.02;

    return d * pulse;
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, audioReactive: f32, spiralTightness: f32) -> f32 {
    var d0 = 0.0;
    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * d0;
        let dS = map(p, audioReactive, spiralTightness);
        d0 += dS;
        if (d0 > MAX_DIST || abs(dS) < SURF_DIST) {
            break;
        }
    }
    return d0;
}

fn calcNormal(p: vec3<f32>, audioReactive: f32, spiralTightness: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, audioReactive, spiralTightness) - map(p - e.xyy, audioReactive, spiralTightness),
        map(p + e.yxy, audioReactive, spiralTightness) - map(p - e.yxy, audioReactive, spiralTightness),
        map(p + e.yyx, audioReactive, spiralTightness) - map(p - e.yyx, audioReactive, spiralTightness)
    );
    return normalize(n);
}

// Native idea 2: pearl nacre luster on inner chamber ridges.
fn pearlNacreLuster(p: vec3<f32>, n: vec3<f32>, viewDir: vec3<f32>, spiralTightness: f32, iridescenceShift: f32, t: f32) -> vec3<f32> {
    let r = length(p.xz);
    let a = atan2(p.z, p.x);
    let b = spiralTightness;
    let theta = log(max(r, 0.001)) / b;
    let nf = floor(theta - a / TAU);
    let r0 = exp((nf + a / TAU) * b);
    let innerRidge = smoothstep(0.38, 0.0, abs(r - r0 * 0.62));
    let nacrePhase = dot(n, viewDir) * 9.0 + iridescenceShift * TAU + t * 0.35;
    let nacre = 0.5 + 0.5 * cos(vec3<f32>(1.0, 1.28, 1.62) * nacrePhase + innerRidge * 4.0);
    return nacre * innerRidge * vec3<f32>(0.92, 0.96, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let coord = vec2<i32>(id.xy);
    let base_uv = vec2<f32>(f32(id.x), f32(id.y)) / resolution.xy;
    var uv = base_uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;

    let refrIndex = u.zoom_params.x;
    let spiralTightness = u.zoom_params.y;
    let iridescenceShift = u.zoom_params.z;
    let audioParam = u.zoom_params.w;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let audioReactive = audioParam * (0.35 + bass * 0.65 + mids * 0.2);

    let ta = vec3<f32>(0.0, 0.0, 0.0);
    var ro = vec3<f32>(0.0, 2.0, -4.0);

    var mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
    mouse_uv.x *= resolution.x / resolution.y;

    let time = u.config.x * 0.2;
    ro = vec3<f32>(ro.x * cos(time) - ro.z * sin(time), ro.y, ro.x * sin(time) + ro.z * cos(time));

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);

    var rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    if (u.zoom_config.w > 0.0) {
        let mouseDist = length(uv - mouse_uv);
        let pull = 0.5 / (mouseDist * mouseDist + 0.1);
        rd = normalize(rd + vec3<f32>(uv - mouse_uv, 0.0) * pull * 0.2);
    }

    let d = raymarch(ro, rd, audioReactive, spiralTightness);

    var col = vec3<f32>(0.02, 0.02, 0.05);
    var alpha = 0.05 + treble * 0.03;
    var depth = textureLoad(readDepthTexture, coord, 0).r;
    let hit = d < MAX_DIST;

    if (hit) {
        let p = ro + rd * d;
        let n = calcNormal(p, audioReactive, spiralTightness);
        let viewDir = normalize(ro - p);

        let lightDir = normalize(vec3<f32>(1.0, 2.0, -2.0));
        let diffuse = max(dot(n, lightDir), 0.0);

        let NdotV = max(dot(n, viewDir), 0.0);
        let phase = NdotV * 5.0 + iridescenceShift * TAU + time;
        let iridescence = 0.5 + 0.5 * cos(vec3<f32>(1.0, 1.2, 1.4) * phase);

        let envUV = clamp(base_uv + n.xy * 0.1 * (refrIndex - 1.0), vec2<f32>(0.0), vec2<f32>(1.0));
        let envRefr = textureSampleLevel(readTexture, u_sampler, envUV, 0.0).rgb;

        let coreDist = length(p);
        let glow = exp(-coreDist * 0.5) * vec3<f32>(0.2, 0.8, 1.0) * (1.0 + audioReactive);

        let nacre = pearlNacreLuster(p, n, viewDir, spiralTightness, iridescenceShift, time);
        col = iridescence * diffuse * 0.5 + envRefr * 0.3 + glow + nacre * 0.55;

        let edge = 1.0 - NdotV;
        col += vec3<f32>(edge * 0.5, edge * 0.2, 0.0);

        depth = clamp(1.0 - d / MAX_DIST, 0.0, 1.0);
        alpha = clamp(diffuse * 0.55 + NdotV * 0.25 + length(nacre) * 0.2, 0.0, 1.0);
    }

    let previous = textureLoad(dataTextureC, coord, 0);
    col = mix(col, previous.rgb * 0.94, 0.04 + mids * 0.02);

    col = acesToneMap(col * (1.05 + bass * 0.15));
    let finalAlpha = clamp(alpha + previous.a * 0.06, 0.0, 1.0);
    let finalColor = vec4<f32>(col, finalAlpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
