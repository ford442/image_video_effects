// ═══════════════════════════════════════════════════════════════════
//  Polka Dot Reveal — Phase B (Advanced Alpha)
//  Category: artistic
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba,
//            depth-aware, alpha-layered, edge-preserve, luminance-key,
//            hash-jitter, optimized
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-07-08
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const LUMA: vec3<f32> = vec3<f32>(0.2126, 0.7152, 0.0722);

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}


fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, LUMA);
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

// Single-pixel edge estimator for depth and luminance boundaries.
// Returns ~1.0 on strong edges, 0.0 in smooth regions.
fn edge_mask(gid: vec2<i32>, uv: vec2<f32>, res: vec2<f32>) -> f32 {
    let d0 = textureLoad(readDepthTexture, gid, 0).r;
    let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let l0 = luma(c0.rgb);

    let dx = vec2<i32>(1, 0);
    let dy = vec2<i32>(0, 1);
    let d1 = textureLoad(readDepthTexture, gid + dx, 0).r;
    let d2 = textureLoad(readDepthTexture, gid - dx, 0).r;
    let d3 = textureLoad(readDepthTexture, gid + dy, 0).r;
    let d4 = textureLoad(readDepthTexture, gid - dy, 0).r;
    let depthEdge = length(vec2<f32>(0.5 * (d1 - d2), 0.5 * (d3 - d4)));

    let sx = vec2<f32>(1.0 / res.x, 0.0);
    let sy = vec2<f32>(0.0, 1.0 / res.y);
    let l1 = luma(textureSampleLevel(readTexture, u_sampler, uv + sx, 0.0).rgb);
    let l2 = luma(textureSampleLevel(readTexture, u_sampler, uv - sx, 0.0).rgb);
    let l3 = luma(textureSampleLevel(readTexture, u_sampler, uv + sy, 0.0).rgb);
    let l4 = luma(textureSampleLevel(readTexture, u_sampler, uv - sy, 0.0).rgb);
    let lumaEdge = length(vec2<f32>(0.5 * (l1 - l2), 0.5 * (l3 - l4)));

    return clamp(depthEdge * 3.0 + lumaEdge * 4.0, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(pixel) / res;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;
    let mouseDown = u.zoom_config.w > 0.5;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let speed = clamp(u.zoom_params.y, 0.0, 1.0);
    let scale = clamp(u.zoom_params.z, 0.01, 1.0);
    let detail = clamp(u.zoom_params.w, 0.01, 1.0);

    let prev = textureLoad(dataTextureC, pixel, 0);
    let bass_smooth = bass_env(prev.r, bass, 0.8, 0.15);
    let smoothMouse = mix(prev.gb, mouse, 0.12);
    let mouseVel = length(mouse - smoothMouse);

    let aspect = res.x / res.y;
    let mAspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
    let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
    let dist = distance(uvAspect, mAspect);

    let densityMin = mix(10.0, 40.0, scale);
    let densityMax = mix(80.0, 250.0, scale);
    let revealRadius = 0.7 + mouseVel * 3.0;
    let density = mix(densityMax, densityMin, smoothstep(0.0, revealRadius, dist));

    // Per-cell hash jitter (blue-noise substitute) plus a chromatic cell hash.
    let jitter = (hash21(uv * 131.0 + vec2<f32>(17.0, 31.0)) - 0.5) / density;
    let cellHash = hash21(uv * 97.0 + vec2<f32>(43.0, 19.0));
    let grid_uv = floor((uv + jitter) * density) / density;
    let cell_center = grid_uv + (0.5 / density);

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let color = textureSampleLevel(readTexture, u_sampler, cell_center, 0.0);
    let lum = luma(color.rgb);

    // ── Advanced Alpha Composition ───────────────────────────────
    // Depth-layered: far pixels are more translucent.
    let depthAlpha = mix(0.25, 1.0, pow(depth, 0.7));
    // Luminance key: dark pixels fade out.
    let lumaAlpha = smoothstep(0.04, 0.32, lum);
    // Edge-preserve: content boundaries stay opaque.
    let edge = edge_mask(pixel, uv, res);
    let edgeAlpha = mix(0.2, 1.0, smoothstep(0.06, 0.35, edge));
    // Detail param blends luminance-key vs. depth-layered modes.
    let baseAlpha = mix(lumaAlpha, depthAlpha, detail) * edgeAlpha;

    let audioBoost = 1.0 + bass_smooth * 0.5 + mids * 0.2;
    let clickBoost = select(1.0, 1.4, mouseDown);
    let depthBoost = 1.0 + depth * 0.35;
    let radius = lum * 0.5 * audioBoost * clickBoost * depthBoost;

    let pulse = 1.0 + sin(time * (0.5 + speed * 2.0)) * 0.06 * speed;
    let animated_radius = radius * pulse;

    let local_uv = fract((uv + jitter) * density);
    let dist_to_center = distance(local_uv, vec2<f32>(0.5));

    let aa = mix(0.03, 0.15, detail) * density / 50.0;
    let circle = 1.0 - smoothstep(animated_radius - aa, animated_radius + aa, dist_to_center);

    // Soft halo outside the dot prevents hard cutouts and carries depth context.
    let halo = 1.0 - smoothstep(animated_radius, animated_radius + aa * 3.0, dist_to_center);
    let haloAlpha = halo * 0.25 * depthAlpha * (0.4 + 0.6 * lumaAlpha);

    let trailDecay = mix(0.72, 0.96, intensity);
    let trailAlpha = prev.a * trailDecay;
    var dotAlpha = max(circle * baseAlpha * intensity * (1.0 + bass_smooth * 0.2), haloAlpha);
    dotAlpha = max(dotAlpha, trailAlpha);

    let interaction = clamp(bass_smooth * 0.5 + mouseVel * 2.0 + treble * 0.1, 0.0, 1.0);
    let finalAlpha = clamp(dotAlpha + interaction * 0.25, 0.05, 1.0);

    // Chromatic offset inside dots, keyed by treble and depth.
    let chromaShift = (cellHash - 0.5) * 0.015 * (1.0 + treble * 1.5) * (1.0 - depth * 0.5);
    let rColor = textureSampleLevel(readTexture, u_sampler, cell_center + vec2<f32>(chromaShift, 0.0), 0.0).r;
    let bColor = textureSampleLevel(readTexture, u_sampler, cell_center - vec2<f32>(chromaShift, 0.0), 0.0).b;
    var rgb = color.rgb;
    rgb.r = mix(rgb.r, rColor, circle * 0.6);
    rgb.b = mix(rgb.b, bColor, circle * 0.6);

    let satBoost = 1.0 + bass_smooth * 0.3 + treble * 0.1;
    var final_color = vec4<f32>(rgb * satBoost, finalAlpha);
    final_color = clamp(final_color, vec4<f32>(0.0), vec4<f32>(1.0));

    // State: R=bass envelope, G=smoothed mouse x, B=smoothed mouse y, A=alpha.
    let state = vec4<f32>(bass_smooth, smoothMouse.x, smoothMouse.y, final_color.a);

    textureStore(writeTexture, pixel, final_color);
    textureStore(dataTextureA, pixel, state);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
