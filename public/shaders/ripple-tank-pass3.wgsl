// ═══ RIPPLE TANK — PASS 3/3: PSYCHEDELIC WATER RENDER ══════════════════════
//  Category: simulation (multipass 3 of 3: step → optics gather → render)
//  Features: mouse-driven, audio-reactive, depth-aware, aces-tone-map,
//            chromatic-refraction, semantic-alpha
//
//  Reads wave state from dataTextureC (host copies dataB→C) and the same-frame
//  coarse caustic-energy grid that pass 2 wrote into extraBuffer[140..239].
//
//  State packing: .r height, .g velocity, .b prev height, .a driver phase.
//  Commits final sim state to dataTextureA for end-of-frame feedback copy.

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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .x wave speed, .y damping, .z source, .w boundary
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const GRID: i32 = 10;
const GRID_BASE: i32 = 140;

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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14),
                 vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn loadState(pixel: vec2<i32>, res: vec2<i32>) -> vec4<f32> {
    let p = clamp(pixel, vec2<i32>(0), res - vec2<i32>(1));
    return textureLoad(dataTextureC, p, 0);
}

// Bilinear sample of the 10×10 caustic-energy grid pass 2 wrote this frame
fn coarseEnergy(uv: vec2<f32>) -> f32 {
    let g  = uv * f32(GRID) - vec2<f32>(0.5);
    let g0 = clamp(vec2<i32>(floor(g)), vec2<i32>(0), vec2<i32>(GRID - 1));
    let g1 = clamp(g0 + vec2<i32>(1), vec2<i32>(0), vec2<i32>(GRID - 1));
    let f  = clamp(g - floor(g), vec2<f32>(0.0), vec2<f32>(1.0));
    let e00 = extraBuffer[GRID_BASE + g0.y * GRID + g0.x];
    let e10 = extraBuffer[GRID_BASE + g0.y * GRID + g1.x];
    let e01 = extraBuffer[GRID_BASE + g1.y * GRID + g0.x];
    let e11 = extraBuffer[GRID_BASE + g1.y * GRID + g1.x];
    return mix(mix(e00, e10, f.x), mix(e01, e11, f.x), f.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let resI = vec2<i32>(res);
    let uv   = vec2<f32>(pixel) / res;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Wave field + finite-difference normals ─────────────────────────────
    let state    = loadState(pixel, resI);
    let height   = state.r;
    let velocity = state.g;

    let hL = loadState(pixel + vec2<i32>(-1, 0), resI).r;
    let hR = loadState(pixel + vec2<i32>( 1, 0), resI).r;
    let hT = loadState(pixel + vec2<i32>( 0,-1), resI).r;
    let hB = loadState(pixel + vec2<i32>( 0, 1), resI).r;
    let grad   = vec2<f32>(hR - hL, hB - hT);
    let lap    = hL + hR + hT + hB - 4.0 * height;
    let normal = normalize(vec3<f32>(-grad * 6.0, 0.12));

    // ── Chromatic refraction of the source image ───────────────────────────
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let refractStrength = 0.045 * (1.0 + bass * 0.4) * (0.5 + depth * 0.5);
    let baseOffset = normal.xy * refractStrength;
    let rCol = textureSampleLevel(readTexture, u_sampler, uv + baseOffset * 1.15, 0.0).r;
    let gCol = textureSampleLevel(readTexture, u_sampler, uv + baseOffset, 0.0).g;
    let bCol = textureSampleLevel(readTexture, u_sampler, uv + baseOffset * 0.8, 0.0).b;
    let sourceColor = vec3<f32>(rCol, gCol, bCol);

    // ── Phase → rainbow interference bands (the "strange" pillar) ──────────
    let phase = atan2(velocity, height);
    let rawAmp = sqrt(height * height + velocity * velocity);
    let amplitude = rawAmp / (0.15 + rawAmp);  // soft-saturating response
    let hue = fract(phase / TAU + 0.5 + time * 0.06);
    let waveColor = hsv2rgb(vec3<f32>(
        hue,
        clamp(0.55 + mids * 0.3, 0.0, 1.0),
        clamp(amplitude * 1.6, 0.0, 1.0)
    ));

    // ── Lighting: diffuse + specular glints off the water surface ──────────
    let lightDir = normalize(vec3<f32>(0.4, 0.55, 0.8));
    let diffuse  = max(dot(normal, lightDir), 0.0);
    let viewDir  = vec3<f32>(0.0, 0.0, 1.0);
    let specular = pow(max(dot(reflect(-lightDir, normal), viewDir), 0.0), 48.0);

    // ── Caustics: local curvature sparks × same-frame coarse focus energy ──
    let focus = coarseEnergy(uv);
    let caustic = pow(min(abs(lap) * 18.0, 1.4), 1.7) * (0.4 + min(focus * 80.0, 1.6));
    let shimmer = caustic * (1.0 + treble * 0.8);

    // ── Composite ──────────────────────────────────────────────────────────
    var color = sourceColor * (0.55 + diffuse * 0.55);
    color += waveColor * amplitude * 1.15;
    color += vec3<f32>(1.0, 0.97, 0.88) * specular * 0.35;
    color += vec3<f32>(0.55, 0.85, 1.0) * shimmer * 0.2;
    color = acesToneMap(color * (1.05 + bass * 0.1));

    // Alpha carries wave intensity; depth dips where crests rise
    let alpha = clamp(0.35 + amplitude * 1.5 + shimmer * 0.1, 0.35, 0.97);
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel,
        vec4<f32>(clamp(depth - height * 0.06, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, state);
}
