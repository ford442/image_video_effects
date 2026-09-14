// ═══════════════════════════════════════════════════════════════════
//  Symbiotic Cyber-Mycelium
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13
//  Ideas: axis-aligned data packets along nearest cylinder; infection quarantine rim
//  A packing: ACES display RGBA (C unused)
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
  zoom_params: vec4<f32>,  // .x = Data Speed, .y = Network Density, .z = Growth Twist, .w = Infection Bloom
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(TAU * (c * t + d));
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uu = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    return mix(mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                       dot(hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), uu.x),
                   mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                       dot(hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), uu.x), uu.y),
               mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                       dot(hash3(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), uu.x),
                   mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                       dot(hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), uu.x), uu.y), uu.z);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.001), 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn opRep(p: vec3<f32>, c: vec3<f32>) -> vec3<f32> {
    return p - c * round(p / c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// returns (sdf, mat, alongAxis, infectionFalloff)
fn map(p: vec3<f32>) -> vec4<f32> {
    var pos = p;

    let audioBass = plasmaBuffer[0].x;
    let densityMod = 1.0 + audioBass * 0.5;

    let aspect = u.config.z / max(u.config.w, 1.0);
    let mousePos = vec2<f32>((u.zoom_config.y * 2.0 - 1.0) * aspect, -(u.zoom_config.z * 2.0 - 1.0));
    let infectionCenter = vec3<f32>(mousePos.x * 3.0, mousePos.y * 3.0, p.z);

    let distToMouse = length(p.xy - infectionCenter.xy);
    let infectionStr = u.zoom_params.w * max(0.0, 1.0 - distToMouse / 2.0);
    let falloff = clamp(1.0 - distToMouse / 2.0, 0.0, 1.0);

    let twistFactor = u.zoom_params.z;
    let twr = rot(pos.z * twistFactor * 0.1);
    let pxy = twr * pos.xy;
    pos = vec3<f32>(pxy.x, pxy.y, pos.z);

    let cellSpace = 4.0 / max(u.zoom_params.y * densityMod, 0.001);
    let q = opRep(pos, vec3<f32>(cellSpace));

    let cylRadius = 0.05 + noise(pos * 5.0) * 0.02 + infectionStr * 0.05;

    let dCylX = length(q.yz) - cylRadius;
    let dCylY = length(q.xz) - cylRadius;
    let dCylZ = length(q.xy) - cylRadius;

    var dCyl = smin(dCylX, dCylY, 0.2);
    dCyl = smin(dCyl, dCylZ, 0.2);

    let dSphere = length(q) - (0.15 + infectionStr * 0.1);
    let d = smin(dCyl, dSphere, 0.3);
    let finalD = d + noise(pos * 2.0) * 0.05;

    let mat = select(1.0, 2.0, dSphere < dCyl + 0.1);

    let alongZ = select(q.z, q.y, dCylY < dCylZ);
    let alongAxis = select(alongZ, q.x, (dCylX < dCylY) && (dCylX < dCylZ));

    return vec4<f32>(finalD, mat, alongAxis, falloff);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * map(p + e.xyy).x +
                     e.yyx * map(p + e.yyx).x +
                     e.yxy * map(p + e.yxy).x +
                     e.xxx * map(p + e.xxx).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = vec2<i32>(textureDimensions(writeTexture));
    let coord = vec2<i32>(global_id.xy);

    if (coord.x >= dimensions.x || coord.y >= dimensions.y) {
        return;
    }

    let resolution = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let uv = (vec2<f32>(coord) - 0.5 * resolution) / resolution.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let time = u.config.x;
    let dataSpeed = u.zoom_params.x * (1.0 + treble * 0.6);

    let ro = vec3<f32>(0.0, 0.0, time * 2.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var hitMap = vec4<f32>(-1.0);
    var d = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        hitMap = map(p);
        d = hitMap.x;
        if (d < 0.001 || t > 20.0) { break; }
        t += d * 0.7;
    }

    var col = vec3<f32>(0.0, 0.02, 0.05);
    var packet = 0.0;
    var rim = 0.0;
    let hit = t < 20.0;

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        hitMap = map(p);

        let lig = normalize(vec3<f32>(0.5, 0.8, -0.2));
        let dif = clamp(dot(n, lig), 0.0, 1.0);
        let amb = 0.5 + 0.5 * dot(n, vec3<f32>(0.0, 1.0, 0.0));

        let sssDist = 0.1;
        let sssVal = map(p + n * sssDist).x;
        let sss = smoothstep(0.0, sssDist, sssVal);

        var baseCol = vec3<f32>(0.05, 0.15, 0.2);
        if (hitMap.y > 1.5) {
            baseCol = vec3<f32>(0.2, 0.1, 0.3);
        }

        col = baseCol * (dif * 0.5 + amb * 0.5) + vec3<f32>(0.0, 0.5, 0.2) * (1.0 - sss) * 2.0;

        // Idea 1 — packets travel along the nearest cylinder axis in q
        let pulsePhase = fract(hitMap.z * 4.0 - time * dataSpeed);
        packet = smoothstep(0.78, 1.0, pulsePhase) * smoothstep(1.0, 0.82, pulsePhase + 0.08);

        let aspect = u.config.z / max(u.config.w, 1.0);
        let mousePos = vec2<f32>((u.zoom_config.y * 2.0 - 1.0) * aspect, -(u.zoom_config.z * 2.0 - 1.0));
        let distToMouseHit = length(p.xy - mousePos * 3.0);
        let hitInfectionStr = u.zoom_params.w * max(0.0, 1.0 - distToMouseHit / 2.0);

        // Idea 2 — quarantine rim at the infection falloff edge (not a disk fill)
        let falloff = hitMap.w;
        rim = smoothstep(0.0, 0.12, falloff) * smoothstep(0.42, 0.18, falloff) * u.zoom_params.w;

        let glowColor = palette(hitMap.z * 0.1 - time * 0.1 + hitInfectionStr * 0.5);
        let emissionStr = (packet * 5.0 + hitInfectionStr * 1.2) * select(1.0, 2.0, hitMap.y > 1.5);
        col += glowColor * emissionStr;
        col += vec3<f32>(0.2, 1.0, 0.55) * rim * (2.2 + mids);

        col = mix(col, vec3<f32>(0.0, 0.02, 0.05), 1.0 - exp(-0.05 * t));
    }

    let display = acesToneMap(col);
    let alpha = clamp(select(0.08, 0.4, hit) + packet * 0.35 + rim * 0.4, 0.04, 1.0);
    let depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);
    let outColor = vec4<f32>(display, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
