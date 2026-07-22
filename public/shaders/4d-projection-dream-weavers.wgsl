// ═══════════════════════════════════════════════════════════════════
//  4D Projection Dream Weavers
//  Category: generative
//  Features: 4d-fractal, smooth-navigation, mouse-4d-control, audio-parameter, dream-like,
//            temporal-persistence, chromatic-dimension-separation, bass-detail, upgraded-rgba,
//            aces-tone-map, spring-damper-4d-navigation, worley-dream-dust, dimension-tint
//  Complexity: High
//  Chunks From: 4D noise projection techniques
//  Created: 2026-05-31
//  Upgraded: 2026-06-06, 2026-07-22 (Algorithmist: spring-damper nav, worley dust, palette tint)
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

// extraBuffer layout (0..4 reserved; 5..132 = engine FFT bins): [133]=z angle [134]=z vel [135]=w angle [136]=w vel

fn hash13(p: vec3<f32>) -> f32 {
    var p4 = fract(vec4<f32>(p.xyz, 0.0) * 0.1031);
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.x + p4.y) * (p4.z + p4.w));
}

fn noise4D(p: vec4<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let a = hash13(i.xyz);
    let b = hash13(i.xyz + vec3<f32>(1.0, 0.0, 0.0));
    let c = hash13(i.xyz + vec3<f32>(0.0, 1.0, 0.0));
    let d = hash13(i.xyz + vec3<f32>(1.0, 1.0, 0.0));
    let e = hash13(i.xyz + vec3<f32>(0.0, 0.0, 1.0));
    let f2 = hash13(i.xyz + vec3<f32>(1.0, 0.0, 1.0));
    let g = hash13(i.xyz + vec3<f32>(0.0, 1.0, 1.0));
    let h = hash13(i.xyz + vec3<f32>(1.0, 1.0, 1.0));

    return mix(
        mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
        mix(mix(e, f2, u.x), mix(g, h, u.x), u.y),
        u.z
    );
}

// Worley (cellular) F1 distance over a 3D domain, used for dream-dust sparkles
// suspended in the projected 3D slice of 4-space.
fn worley3D(p: vec3<f32>) -> f32 {
    let ip = floor(p);
    let fp = fract(p);
    var f1 = 8.0;
    for (var x = -1; x <= 1; x++) {
        for (var y = -1; y <= 1; y++) {
            for (var z = -1; z <= 1; z++) {
                let cell = vec3<f32>(f32(x), f32(y), f32(z));
                let jitter = vec3<f32>(
                    hash13(ip + cell),
                    hash13(ip + cell + vec3<f32>(17.17, 31.31, 47.47)),
                    hash13(ip + cell + vec3<f32>(59.59, 71.71, 83.83))
                );
                let d = cell + jitter - fp;
                f1 = min(f1, dot(d, d));
            }
        }
    }
    return sqrt(f1);
}

// Cosine palette: classic a + b*cos(TAU*(c*t + d)) dimension-tint generator.
fn cosinePalette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(TAU * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.2;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Sliders wired to real algorithm constants (saved-preset contract) ──
    let pScale = clamp(u.zoom_params.x, 0.0, 1.0);       // Base Scale
    let pSpeed = clamp(u.zoom_params.y, 0.0, 1.0);       // Temporal Speed
    let pDetail = clamp(u.zoom_params.z, 0.0, 1.0);      // Fractal Detail
    let pMouse = clamp(u.zoom_params.w, 0.0, 1.0);       // 4D Mouse Sensitivity

    let mouse = u.zoom_config.yz;

    // ── Spring-damper smoothing of the 4D slice coordinates ─────────────
    // Thread (0,0) integrates one step per frame; everyone reads the
    // previous frame's smoothed state (one-frame lag, race-free in practice).
    let mouseRange = mix(1.5, 6.0, pMouse);
    let targetZ = (mouse.y - 0.5) * mouseRange;
    let targetW = (mouse.x - 0.5) * mouseRange;
    var z = targetZ;
    var w = targetW;
    if (arrayLength(&extraBuffer) > 136u) {
        let dt = clamp(u.config.y, 0.001, 0.05);
        let stiffness = mix(6.0, 18.0, pMouse); // snappier at high sensitivity
        let damping = 0.82;
        if (gid.x == 0u && gid.y == 0u) {
            var sz = extraBuffer[133];
            var vz = extraBuffer[134];
            var sw = extraBuffer[135];
            var vw = extraBuffer[136];
            vz = (vz + (targetZ - sz) * stiffness * dt) * damping;
            vw = (vw + (targetW - sw) * stiffness * dt) * damping;
            sz += vz * dt * 60.0 * 0.016;
            sw += vw * dt * 60.0 * 0.016;
            extraBuffer[133] = sz;
            extraBuffer[134] = vz;
            extraBuffer[135] = sw;
            extraBuffer[136] = vw;
        }
        z = extraBuffer[133];
        w = extraBuffer[135];
    }

    // Sliders drive the actual 4D field constants, audio adds modulation.
    let scale = mix(1.0, 3.2, pScale) + mids * 1.4;
    let speed = mix(0.15, 1.4, pSpeed) + bass * 0.8;
    let detail = mix(0.35, 1.6, pDetail) + treble * 1.2;

    let p4 = vec4<f32>(uv * scale, z, w);

    // Chromatic dimension separation: sample at different 4D offsets per channel
    let n_r = noise4D(p4 * 1.0 + time * speed + vec4<f32>(bass * 0.1, 0.0, 0.0, 0.0));
    let n_g = noise4D(p4 * 1.0 + time * speed);
    let n_b = noise4D(p4 * 1.0 + time * speed - vec4<f32>(treble * 0.1, 0.0, 0.0, 0.0));
    // Detail slider scales the higher octaves' amplitude (fine structure on/off)
    let n2 = noise4D(p4 * 2.3 - time * speed * 0.7) * 0.5 * detail;
    let n3 = noise4D(p4 * 4.7 + time * speed * 1.3) * 0.25 * detail;

    let fractal_r = n_r + n2 + n3;
    let fractal_g = n_g + n2 + n3;
    let fractal_b = n_b + n2 + n3;
    let depthField = (fractal_r + fractal_g + fractal_b) * 0.2 + 0.3;

    // Temporal persistence for dream-like trails
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let fractal_col = vec3<f32>(fractal_r, fractal_g, fractal_b);
    let temporal = mix(fractal_col, prev * 0.92, 0.12 + bass * 0.05);

    let col = mix(
        vec3<f32>(0.1, 0.15, 0.25),
        vec3<f32>(0.9, 0.85, 0.7),
        temporal * 0.6 + 0.4
    );

    // Cosine-palette dimension tint: hue drifts with the smoothed 4D angles,
    // mixed at ~0.25 so the original palette stays dominant.
    let dimPhase = (z + w) * 0.11 + fractal_col.x * 0.35 + time * 0.03;
    let tint = cosinePalette(
        dimPhase,
        vec3<f32>(0.5, 0.5, 0.55),
        vec3<f32>(0.35, 0.3, 0.4),
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.0, 0.33, 0.67)
    );
    var tinted = mix(col, col * (0.6 + tint * 1.1), 0.25);

    let extraColor = vec3<f32>(abs(z) * 0.1, abs(w) * 0.08, (z + w) * 0.05);
    tinted += extraColor;

    // ── Worley dream-dust: sparse animated sparkle in the projected slice ──
    let dustP = vec3<f32>(uv * scale * 3.0, time * speed * 0.5 + z * 0.25 + w * 0.15);
    let wor = worley3D(dustP);
    // Sparse: sharp pow keeps only the cell centers; depth-fade hides dust in
    // dense fractal regions; treble modulates brightness.
    let sparkle = pow(clamp(1.0 - wor, 0.0, 1.0), 24.0);
    let depthFade = smoothstep(0.9, 0.35, depthField);
    let dust = sparkle * depthFade * (0.25 + treble * 0.9);
    let dustCol = cosinePalette(
        dimPhase + 0.5,
        vec3<f32>(0.7, 0.7, 0.8),
        vec3<f32>(0.3, 0.3, 0.2),
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.0, 0.5, 0.8)
    );
    let finalCol = tinted + dustCol * dust;

    let alpha = clamp((fractal_r + fractal_g + fractal_b) * 0.25 + 0.4 + bass * 0.05 + dust * 0.3, 0.25, 1.0);
    let a = clamp(alpha, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(acesToneMap(finalCol * 1.1), a));
    textureStore(dataTextureA, gid.xy, vec4<f32>(finalCol, a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depthField, 0.0, 0.0, 0.0));
}
