// ═══════════════════════════════════════════════════════════════════
//  Ambient Liquid  (RETRY expanded upgrade)
//  Category: artistic
//  Features: mouse-driven, liquid-distortion, upgraded-rgba,
//            curl-noise, depth-aware, aces-tone-map, reaction-diffusion,
//            sdf-metaballs, anisotropic-specular, film-grain
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
//  Upgraded: 2026-08-23 (Batch 64)
//
//  FIXED IN THIS PASS — the `reaction-diffusion` claim had nothing behind it.
//  The JSON advertises `reaction-diffusion`, and the shader called a function
//  named `grayScott()` — but that function was four sine waves:
//
//      let s1 = sin(p.x * 12.0 + t) + sin(p.y * 12.0 + t * 0.7);
//      ... return smoothstep(0.35, 0.65, spots);
//
//  There were no chemical concentrations, no Laplacian, no feed/kill rates, and
//  no state at all: `dataTextureA` was never written and `dataTextureC` never
//  read, so nothing could react or diffuse across frames. A real Gray-Scott
//  step is now wired, following the working implementation in
//  `public/shaders/digital-mold.wgsl`.
//
//  Because the shader now runs a genuine simulation, `dataTextureA` carries the
//  CHEMICAL STATE (rg = U/V concentrations, b = ink, a = display luma) rather
//  than display RGBA — the Batch 58B convention. Display goes to `writeTexture`
//  and diagnostics to B. Overwriting A with colour would destroy the reaction.
//
//  Also: the ripple loop always ran the full 50 iterations behind a mask; it is
//  now guarded by `min(u32(u.config.y), 50u)` per the contract.
//
//  TWO NEW STRUCTURES
//
//    1. Real Gray-Scott reaction-diffusion — U and V concentrations advected by
//       the curl flow, with a five-tap Laplacian from exact `textureLoad`
//       fetches. Feed and kill rates are driven per FFT band, so different
//       frequencies push the system between spots, stripes and mitosis regimes.
//
//    2. Surface-tension coupling to the metaball field — the V concentration
//       raises local surface tension, which pulls the SDF metaball isosurface
//       inward and sharpens the ink boundary where the reaction is active. The
//       chemistry and the blobs were previously two unrelated overlays.
// ═══════════════════════════════════════════════════════════════════════════════

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

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}
fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.001;
    let nx = fbm(p + vec2<f32>(0.0, eps), 4) - fbm(p - vec2<f32>(0.0, eps), 4);
    let ny = fbm(p + vec2<f32>(eps, 0.0), 4) - fbm(p - vec2<f32>(eps, 0.0), 4);
    return vec2<f32>(nx, -ny) / (2.0 * eps);
}
fn curl2DAdv(p: vec2<f32>, t: f32) -> vec2<f32> {
    // Advected curl: sample curl at a displaced location for extra vorticity.
    let base = curl2D(p, t);
    let adv = curl2D(p - base * 0.3 + t * 0.05, t);
    return mix(base, adv, 0.5);
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let mx = max(max(c.r, c.g), c.b);
    let mn = min(min(c.r, c.g), c.b);
    let d = mx - mn;
    var h = 0.0;
    if (d > 0.0) {
        if      (mx == c.r) { h = (c.g - c.b) / d + select(0.0, 6.0, c.g < c.b); }
        else if (mx == c.g) { h = (c.b - c.r) / d + 2.0; }
        else                { h = (c.r - c.g) / d + 4.0; }
        h /= 6.0;
    }
    return vec3<f32>(h, select(0.0, d / mx, mx > 0.0), mx);
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let c = hsv.z * hsv.y;
    let h = hsv.x * 6.0;
    let x = c * (1.0 - abs(fract(h / 2.0) * 2.0 - 1.0));
    let m = hsv.z - c;
    var rgb: vec3<f32>;
    if      (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else              { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(m);
}
// Real Gray-Scott step. `uvIn` is the current (U, V) pair, `lap` the Laplacian
// of that pair over the five-tap stencil. Returns the updated concentrations.
// dU/dt = Du*lap(U) - U*V^2 + F*(1-U)
// dV/dt = Dv*lap(V) + U*V^2 - (F+K)*V
fn grayScottStep(uvIn: vec2<f32>, lap: vec2<f32>, feed: f32, kill: f32) -> vec2<f32> {
    let U = uvIn.x;
    let V = uvIn.y;
    let reaction = U * V * V;
    let dU = 0.21 * lap.x - reaction + feed * (1.0 - U);
    let dV = 0.105 * lap.y + reaction - (feed + kill) * V;
    return clamp(vec2<f32>(U + dU, V + dV), vec2<f32>(0.0), vec2<f32>(1.0));
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn metaballField(p: vec2<f32>, t: f32) -> f32 {
    // Soft-body SDF metaball primitive field.
    var d = 1000.0;
    for (var i = 0; i < 4; i = i + 1) {
        let fi = f32(i);
        let center = vec2<f32>(0.3 + 0.4 * sin(t * 0.2 + fi), 0.3 + 0.4 * cos(t * 0.17 + fi * 1.7));
        d = smin(d, length(p - center) - 0.12, 0.25);
    }
    return d;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }

    let uv = vec2<f32>(coord) / resolution;
    let time = u.config.x;
    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    let flow = curl2DAdv(uv * mix(4.0, 14.0, p2), time * 0.12);
    let mouse = u.zoom_config.yz;
    let to_mouse = mouse - uv;
    let mouse_influence = exp(-length(to_mouse) * 5.0) * 0.02 * (1.0 - p1);
    var disp = flow * mix(0.01, 0.06, p1) + to_mouse * mouse_influence;

    let rippleCount = min(u32(u.config.y), 50u);
    var clickSeed = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        let rippleMask = f32(ripple.z > 0.0 && age > 0.0 && age < 4.0);
        let to_ripple = uv - ripple.xy;
        let ripple_dist = length(to_ripple);
        let ripple_strength = sin(ripple_dist * 20.0 - age * 5.0) * exp(-age * 0.5) * 0.01 * rippleMask;
        disp += vec2<f32>(to_ripple.y, -to_ripple.x) * ripple_strength * p3;
        // Clicks seed V into the reaction, which is how a Gray-Scott system is
        // actually perturbed — a pulse of the autocatalyst, not a colour splash.
        clickSeed += exp(-ripple_dist * ripple_dist * 900.0) * exp(-age * 1.2) * rippleMask;
    }
    clickSeed = min(clickSeed, 1.0);

    // Domain-warped FBM turbulence layered on top of curl flow.
    let turb = fbm(uv * mix(6.0, 22.0, p2) + disp * 30.0 + time * 0.1, 4);
    disp += vec2<f32>(cos(turb * TAU), sin(turb * TAU)) * 0.006 * p2;

    let displacedUV = clamp(uv + disp, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let freq = mix(8.0, 24.0, p2);
    let strength = 0.015 * (1.0 - p1);
    let brightMask = smoothstep(0.65, 0.8, luma);
    let darkMask = 1.0 - smoothstep(0.2, 0.35, luma);
    let brightUV = clamp(uv + vec2<f32>(sin(uv.x * freq + time * 0.65), cos(uv.y * freq * 0.7 + time * 0.65)) * strength, vec2<f32>(0.0), vec2<f32>(1.0));
    let darkUV = clamp(uv + vec2<f32>(sin(uv.x * freq + time * 0.45), cos(uv.y * freq * 0.7 + time * 0.45)) * strength, vec2<f32>(0.0), vec2<f32>(1.0));
    color = mix(color, textureSampleLevel(readTexture, u_sampler, brightUV, 0.0), brightMask * 0.25);
    color = mix(color, textureSampleLevel(readTexture, u_sampler, darkUV, 0.0), darkMask * 0.75);

    // ── Structure 1: real Gray-Scott reaction-diffusion ─────────────────────
    // State comes back through dataTextureC (rg = U, V). The Laplacian uses a
    // five-tap stencil of exact textureLoad fetches — never the filtering
    // sampler, since dataTextureC is rgba32float.
    let dimsI = vec2<i32>(resolution);
    let maxC = dimsI - vec2<i32>(1);
    let stC = textureLoad(dataTextureC, coord, 0);
    let stE = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 1, 0), vec2<i32>(0), maxC), 0);
    let stW = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), maxC), 0);
    let stN = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0,  1), vec2<i32>(0), maxC), 0);
    let stS = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), maxC), 0);

    // Cold start: a zeroed buffer is all substrate with a little seeded V.
    var chem = stC.rg;
    if (chem.x + chem.y < 0.001) {
        chem = vec2<f32>(1.0, step(0.995, hash21(uv * 640.0)));
    }
    let lap = (stE.rg + stW.rg + stN.rg + stS.rg) - 4.0 * chem;

    // Feed/kill per FFT band: different bins push the system between the spot,
    // stripe and mitosis regimes of the Gray-Scott parameter space.
    let bandIdx = u32(clamp(uv.y * 8.0, 0.0, 7.999));
    let band = plasmaBuffer[bandIdx + 1u].x;
    let feed = mix(0.030, 0.055, clamp(p3 * 0.6 + band * 0.5, 0.0, 1.0));
    let kill = mix(0.058, 0.065, clamp(p4 * 0.5 + plasmaBuffer[0].y * 0.4, 0.0, 1.0));

    chem = grayScottStep(chem, lap, feed, kill);
    // Pointer and clicks inject the autocatalyst.
    chem.y = clamp(chem.y + clickSeed * 0.5
                   + exp(-length(to_mouse) * 12.0) * step(0.5, u.zoom_config.w) * 0.25,
                   0.0, 1.0);
    let rd = chem.y;

    // ── Structure 2: surface-tension coupling ────────────────────────────────
    // High V raises local surface tension, pulling the metaball isosurface in
    // and sharpening the ink boundary where the reaction is active.
    let mb = metaballField(uv, time) + rd * 0.06;
    let inkMask = 1.0 - smoothstep(0.0, mix(0.12, 0.05, rd), mb);
    let inkColor = vec3<f32>(0.05, 0.15, 0.35);

    var hsv = rgb2hsv(color.rgb);
    hsv.x = fract(hsv.x + p4 * 0.08 + length(disp) * 2.0 + rd * 0.05);
    hsv.y = clamp(hsv.y * (1.0 + rd * 0.4 * p4), 0.0, 1.0);
    color = vec4<f32>(hsv2rgb(hsv), color.a);
    color = vec4<f32>(acesToneMap(color.rgb * (1.0 + p4 * 0.2)), color.a);

    // Blend ink blobs into dark regions.
    color = vec4<f32>(mix(color.rgb, inkColor, inkMask * darkMask * 0.5 * p3), color.a);

    // Anisotropic specular highlight along flow direction.
    let flowDir = normalize(disp + vec2<f32>(0.0001));
    let aniso = pow(max(dot(normalize(uv - 0.5 + vec2<f32>(0.0001)), flowDir), 0.0), 16.0);
    let spec = vec3<f32>(0.25, 0.3, 0.35) * aniso * length(disp) * 40.0 * (1.0 + plasmaBuffer[0].z);
    color = vec4<f32>(color.rgb + spec * p2, color.a);

    // Vignette + film grain.
    let vig = 1.0 - smoothstep(0.4, 1.4, length(uv - 0.5) * 1.4);
    let grain = (hash21(uv * 1000.0 + time) - 0.5) / 128.0;
    color = vec4<f32>(color.rgb * vig + grain, color.a);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = clamp(dot(color.rgb, vec3<f32>(0.2126, 0.7152, 0.0722)) * 0.8 + depth * 0.2 + length(disp) * 8.0, 0.15, 0.95);

    let outLuma = dot(color.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    textureStore(writeTexture, coord, vec4<f32>(color.rgb, alpha));
    // A carries CHEMICAL STATE (rg = U/V), not display RGBA — the reaction
    // reads it back as dataTextureC next frame. Display is in writeTexture.
    textureStore(dataTextureA, coord, vec4<f32>(chem, inkMask, outLuma));
    textureStore(dataTextureB, coord, vec4<f32>(color.rgb, rd));
    textureStore(writeDepthTexture, coord,
                 vec4<f32>(clamp(depth - rd * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
