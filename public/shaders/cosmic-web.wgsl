// ═══ Cosmic Web Filament ═══════════════════════════════════════════
//  Category: generative
//  Features: mouse-driven, organic, temporal, audio-reactive, depth-aware,
//            aces-tone-map, chromatic-aberration, semantic-alpha

// ── IMMUTABLE 13-BINDING CONTRACT ─────────────────────────────────
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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv (0-1), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = time_created, .w = strength
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const BASE_FREQ: f32 = 3.0;
const TIME_SCALE: f32 = 0.1;
const FILAMENT_SHARP: f32 = 10.0;
const FILAMENT_BIAS: f32 = 0.05;
const VOID_CUTOFF: f32 = 0.03;
const GALAXY_SCALE: f32 = 38.0;
const GALAXY_THRESH: f32 = 0.55;
const NODE_THRESHOLD: f32 = 0.35;
const DECAY: f32 = 0.96;
const FEEDBACK: f32 = 0.25;

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// Branchless Voronoi F1/F2
fn voronoi3(p: vec3<f32>) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);
    var f1 = 1.0;
    var f2 = 1.0;
    for (var k = -1; k <= 1; k = k + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            for (var i = -1; i <= 1; i = i + 1) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let r = g + o - f;
                let d = dot(r, r);
                let b1 = f32(d < f1);
                let b2 = f32(d < f2) * (1.0 - b1);
                f2 = mix(f2, mix(f1, d, b2), b1 + b2);
                f1 = mix(f1, d, b1);
            }
        }
    }
    return vec2<f32>(sqrt(f1), sqrt(f2));
}

// 3-octave FBM over 3D Voronoi
fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i = 0; i < 3; i = i + 1) {
        v += a * voronoi3(pp).x;
        pp = pp * 2.0 + vec3<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

fn hueShift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735);
    let s = sin(shift);
    let c = cos(shift);
    return color * c + cross(k, color) * s + k * dot(k, color) * (1.0 - c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(color.r * (1.0 + shift.x * 0.8), color.g, color.b * (1.0 - shift.y * 0.5));
}

fn filamentDensity(border: f32, scale: f32) -> f32 {
    let f = 1.0 / (border * FILAMENT_SHARP + FILAMENT_BIAS);
    return smoothstep(0.0, 1.0, f * scale);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let aspect = res.x / res.y;
    var uv = (uv01 - 0.5) * vec2<f32>(aspect, 1.0) + 0.5;

    let time = u.config.x * u.zoom_params.z;
    let warpStrength = u.zoom_params.x;
    let densityScale = u.zoom_params.y;
    let colorShift = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // Mouse gravity well — branchless normalization
    let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0) + 0.5;
    let toMouse = mouse - uv;
    let distMouse = length(toMouse);
    let dirToMouse = select(vec2<f32>(0.0), toMouse / distMouse, distMouse > 0.001);
    uv += dirToMouse * (0.3 * smoothstep(0.8, 0.0, distMouse));

    // Domain warp with audio-driven pulse
    var p = vec3<f32>(uv * BASE_FREQ, time * TIME_SCALE);
    let warp = fbm(p);
    p += vec3<f32>(warp * (warpStrength + bass * 0.15));

    // Coarse Voronoi for early-exit culling of deep voids
    let v0 = voronoi3(p);
    let density0 = filamentDensity(v0.y - v0.x, densityScale);

    if (density0 < VOID_CUTOFF) {
        let voidColor = vec3<f32>(0.05, 0.0, 0.1);
        textureStore(writeTexture, pixel, vec4<f32>(voidColor, 0.0));
        textureStore(writeDepthTexture, pixel, vec4<f32>(0.0, 0.0, 0.0, 0.0));
        textureStore(dataTextureA, pixel, vec4<f32>(voidColor, 0.0));
        return;
    }

    // Full filament evaluation
    let v = voronoi3(p);
    let f1 = v.x;
    let f2 = v.y;
    let density = filamentDensity(f2 - f1, densityScale);

    let colVoid = vec3<f32>(0.05, 0.0, 0.1);
    var colFilament = vec3<f32>(0.2, 0.6, 1.0);
    let colCore = vec3<f32>(1.0, 1.0, 1.0);
    colFilament = hueShift(colFilament, colorShift * TAU + bass * 0.3);

    var color = mix(colVoid, colFilament, density);
    color = mix(color, colCore, smoothstep(0.8, 1.0, density));

    // Cluster nodes at Voronoi vertices
    let nodeMetric = smoothstep(NODE_THRESHOLD, 0.0, f1) * density;
    color += vec3<f32>(1.0, 0.85, 0.6) * (nodeMetric * nodeMetric) * (1.3 + treble * 0.5);

    // Galaxy point field along filaments
    let gCell = floor(uv * GALAXY_SCALE);
    let gRand = hash3(vec3<f32>(gCell, 1.0));
    let gPos = (gCell + gRand.xy) / GALAXY_SCALE;
    let gd = length((uv - gPos) * vec2<f32>(aspect, 1.0));
    let twinkle = 0.6 + 0.4 * sin(time * 3.0 + gRand.z * TAU);
    let galaxy = smoothstep(0.006, 0.0, gd) * step(GALAXY_THRESH, gRand.z) * twinkle * density;
    let gTint = mix(vec3<f32>(0.7, 0.85, 1.0), vec3<f32>(1.0, 0.9, 0.7), gRand.x);
    color += gTint * galaxy * (1.5 + bass * 0.6);

    // Depth-aware intensity boost
    color *= 1.0 + depth * 0.25;

    // Temporal feedback
    let temporal = mix(prev.rgb * DECAY, color, FEEDBACK);

    // Chromatic aberration + ACES tone map
    color = genChromaticShift(temporal, uv01, 0.003 * (1.0 + bass));
    color = acesToneMap(color * (0.9 + mids * 0.2));

    // Semantic alpha = intensity/density
    let alpha = clamp(luma(color) * 1.5 + density * 0.3 + galaxy, 0.0, 0.95);

    textureStore(dataTextureA, pixel, vec4<f32>(temporal, 1.0));
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(density, 0.0, 0.0, 0.0));
}
