// ═══════════════════════════════════════════════════════════════════
//  Holographic Lens-Flare Matrix
//  Category: generative
//  Features: anamorphic-flare, mouse-spin, audio-reactive, palette-tinted,
//            chromatic-dispersion, temporal-flare-persistence, depth-aware
//  Complexity: Medium
//  Phase B / Optimizer
//  Upgraded: 2026-05-31
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let coords = vec2<i32>(gid.xy);
    let res = textureDimensions(writeTexture);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(coords) / vec2<f32>(res);
    let aspect = f32(res.x) / max(f32(res.y), 1.0);
    let p = (uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);

    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouse_p = (mouse - 0.5) * vec2<f32>(aspect, 1.0);

    var mouseOffset = vec2<f32>(0.0);
    for (var i = 0; i < 6; i++) {
        let ripple = u.ripples[i];
        let alive = step(1e-4, ripple.w);
        let rPos = ripple.xy;
        let toR = p - rPos;
        let d = length(toR);
        let push = exp(-d * d * 50.0) * ripple.w * alive;
        mouseOffset = mouseOffset + (toR / max(d, 1e-4)) * push;
    }

    let gridSize = 10.0 + u.zoom_params.x * 5.0 + bass * 2.0;
    let flareSpread = u.zoom_params.y;

    let gUv = (p + mouseOffset * 0.1) * gridSize;
    let idc = floor(gUv);
    let fUv = fract(gUv) - vec2<f32>(0.5);

    let r = hash22(idc);
    let offset = (r - vec2<f32>(0.5)) * flareSpread * 2.0;
    let flarePos = fUv - offset;
    let dist = length(flarePos);

    let streak = exp(-flarePos.y * flarePos.y * 80.0) * exp(-abs(flarePos.x) * 4.0);

    let size = 0.08 + bass * 0.25 + mouseDown * 0.05;
    let spinSpeed = time * (1.0 + bass * 2.0);
    let angle = atan2(flarePos.y, flarePos.x) + spinSpeed + u.zoom_params.z * TAU;

    let core = exp(-dist * dist / max(size * size, 1e-6));
    let starMod = 0.5 + 0.5 * sin(angle * 4.0 + time * 5.0);
    let density = core * starMod + streak * 0.4;

    // Chromatic dispersion per flare: RGB stars at different angular offsets
    let chromaOff = u.zoom_params.w * 0.3 + treble * 0.2;
    let angleR = angle + chromaOff;
    let angleB = angle - chromaOff;
    let starR = 0.5 + 0.5 * sin(angleR * 4.0 + time * 5.0);
    let starB = 0.5 + 0.5 * sin(angleB * 4.0 + time * 5.0);
    let densityR = core * starR + streak * 0.4;
    let densityG = density;
    let densityB = core * starB + streak * 0.4;

    let plasmaIdx = u32(abs(fract(r.x + time * 0.1)) * 256.0);
    let pColor = plasmaBuffer[plasmaIdx % 256u].rgb;
    let brightness = 1.0 + u.zoom_params.w + bass * 0.5;
    var col = vec3<f32>(pColor.r * densityR, pColor.g * densityG, pColor.b * densityB) * brightness;

    let motion = textureLoad(readTexture, coords, 0).rgb;
    col = motion * (1.0 - density * 0.6) + col;

    // Temporal flare persistence: previous frame density burns in
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let prevDensity = prev.r;
    let persistent = mix(density, prevDensity, 0.08 + bass * 0.03);
    textureStore(dataTextureA, coords, vec4<f32>(persistent, streak, dist, 1.0));

    // Depth-aware compositing: flares behind depth are dimmer
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthDim = 0.6 + depth * 0.4;
    col = col * depthDim;

    let lumaOut = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let bloom = max(0.0, lumaOut - 0.7) * 3.0;
    let alpha = clamp(0.4 + density * 0.4 + bloom * 0.3 + bass * 0.1, 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
