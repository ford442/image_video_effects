// ═══ IFS Fractal Flame v4 ════════════════════════════════════════
//  Category: generative
//  Features: ifs, flame, bass-envelope, gravity-well, click-burst,
//            treble-sparkle, luma-spawn, depth-aware, temporal-feedback,
//            organic-drift, chromatic-aberration, aces-tone-map
//  Complexity: Medium

// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Math helpers ────────────────────────────────────────────────
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = wellPos - pos;
    let dist2 = dot(d, d) + 0.01;
    return normalize(d) * strength / dist2;
}
fn flamePalette(t: f32) -> vec3<f32> {
    let stops = array<vec3<f32>, 5>(
        vec3<f32>(0.05, 0.0, 0.02),
        vec3<f32>(0.6, 0.0, 0.0),
        vec3<f32>(1.0, 0.4, 0.0),
        vec3<f32>(1.0, 0.9, 0.2),
        vec3<f32>(1.0, 1.0, 0.95)
    );
    let idx = clamp(t, 0.0, 1.0) * 4.0;
    let i = i32(clamp(idx, 0.0, 3.0));
    return mix(stops[i], stops[i + 1], fract(idx));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;

    let bassRaw = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let bass = bass_env(extraBuffer[0], bassRaw, 0.8, 0.15);

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let iterations = i32(mix(24.0, 56.0, clamp(u.zoom_params.x + bass * 0.3, 0.0, 1.0)));
    let spread = mix(0.8, 2.2, u.zoom_params.y);
    let heat = mix(0.5, 2.0, u.zoom_params.z);
    let caAmt = u.zoom_params.w;

    let aspect = res.x / max(res.y, 1.0);
    var p = uv * spread;

    // Organic drift from fbm, driven by mids
    let drift = (vec2<f32>(fbm(uv * 4.0 + time * 0.1, 3),
                           fbm(uv * 4.0 + vec2<f32>(5.2, 1.3) - time * 0.08, 3)) - 0.5) * 0.15;
    p = p + drift * (1.0 + mids);

    // Mouse gravity well / attractor
    let mAttr = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * spread * 0.5;
    p = p - mAttr * 0.25 + gravityWell(p, mAttr, 0.4 + mouseDown * 0.9) * 0.06;

    // Temporal feedback from previous frame
    let prev = textureLoad(dataTextureC, pixel, 0);
    p = p + (prev.xy - 0.5) * 0.04;

    // Click rotation burst
    let clickBurst = mouseDown * sin(time * 12.0) * 0.12;

    // Depth + video input
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let depthFactor = clamp(depth * 1.5, 0.1, 1.0);
    let video = textureLoad(readTexture, pixel, 0);
    let spawnMask = smoothstep(0.62, 0.88, luma(video.rgb) + treble * 0.15);

    var density = 0.0;
    var orbit = vec2<f32>(0.0);

    for (var i = 0; i < iterations; i++) {
        let seed = hash22(p + vec2<f32>(f32(i) * 1.618, time * 0.05));
        let idx = i % 4;

        var tp = p;
        if idx == 0 { tp = vec2<f32>(0.5 * p.x, 0.5 * p.y + 0.25); }
        else if idx == 1 { tp = vec2<f32>(0.5 * p.x + 0.433, 0.5 * p.y + 0.25); }
        else if idx == 2 { tp = vec2<f32>(0.5 * p.x - 0.433, 0.5 * p.y + 0.25); }
        else { tp = vec2<f32>(0.5 * p.x, 0.5 * p.y - 0.5); }

        let varSel = seed.x + mids * 0.12;
        if varSel < 0.33 {
            tp = vec2<f32>(sin(tp.x), sin(tp.y)) * (1.0 + bass * 0.2);
        } else if varSel < 0.66 {
            tp = tp / (dot(tp, tp) + 1e-6);
        } else {
            let r2 = dot(tp, tp);
            let c = cos(r2 + clickBurst);
            let s = sin(r2 + clickBurst);
            tp = vec2<f32>(tp.x * c - tp.y * s, tp.x * s + tp.y * c);
        }

        p = tp;
        let d2 = dot(p, p);
        density += exp(-d2 * 8.0);
        orbit += p;
    }

    density = density / f32(iterations) * heat;
    let flameTemp = clamp(density * 3.0, 0.0, 1.0);
    var color = flamePalette(flameTemp) * (0.3 + density * 2.5);

    // HDR bloom
    color += flamePalette(flameTemp * 0.7) * density * density * 0.8;

    // Treble sparkle particles
    let sparkle = hash21(uv01 * 300.0 + time * 5.0);
    let sparkleMask = smoothstep(0.96, 1.0, sparkle) * treble * 2.0;
    color += vec3<f32>(1.0, 0.95, 0.8) * sparkleMask;

    // Video luma spawn
    color = mix(color, video.rgb * 1.6, spawnMask * 0.35);

    // Chromatic aberration
    let angle = atan2(uv01.y - 0.5, uv01.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * caAmt * 0.04 * (1.0 + bass);
    color = vec3<f32>(color.r * (1.0 + shift.x), color.g, color.b * (1.0 - shift.y * 0.5));

    // Depth-aware fog + tone map
    let fog = 1.0 - exp(-depth * 2.0);
    color = mix(color, color * 0.5, fog * 0.4);
    color = acesToneMap(color * 1.4);

    // Alpha encodes intensity
    let clickDist = length(uv01 - mouse);
    let mouseProx = smoothstep(0.3, 0.0, clickDist);
    let alpha = clamp(density * flameTemp * depthFactor + mouseProx * 0.3 + sparkleMask * 0.5, 0.0, 1.0);

    // Depth output
    let depthOut = clamp(1.0 - flameTemp * 0.8, 0.0, 1.0);

    // Temporal accumulation with decay
    let decay = 0.94 - caAmt * 0.04;
    let trail = mix(prev.rgb * decay, color, 0.25 + bass * 0.1);
    color = mix(color, trail, 0.55);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));

    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[0] = bass;
    }
}
