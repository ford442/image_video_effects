// ═══════════════════════════════════════════════════════════════════
//  Crystalline Shatter
//  Category: image
//  Features: audio-reactive, upgraded-rgba, semantic-alpha
//  Complexity: Medium-High
//  Created: 2026-05-30
// ═══════════════════════════════════════════════════════════════════
//  Voronoi cell decomposition gives each fragment an independent
//  refraction vector and chromatic offset, making the image look
//  shattered into crystal facets. Bass pulses crack new cells;
//  the shatter amount is also mouse-proximity-driven.
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
  config: vec4<f32>,      // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>, // x=CellScale, y=Refraction, z=ChromaticAberration, w=EdgeGlow
  ripples: array<vec4<f32>, 50>,
};

fn hash2f(p: vec2<f32>) -> vec2<f32> {
    let k = vec2<f32>(0.3183099, 0.3678794);
    var x = p * k + k.yx;
    return fract(16.0 * k * fract(x.x * x.y * (x.x + x.y))) * 2.0 - 1.0;
}

// Voronoi: returns (dist-to-nearest, dist-to-edge, cell-id-hash)
fn voronoi(uv: vec2<f32>) -> vec3<f32> {
    let i = floor(uv);
    let f = fract(uv);

    var minDist1 = 8.0;
    var minDist2 = 8.0;
    var cellHash  = 0.0;
    var nearestPoint = vec2<f32>(0.0);

    for (var y = -2; y <= 2; y++) {
        for (var x = -2; x <= 2; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point    = hash2f(i + neighbor) * 0.5 + neighbor + 0.5;
            let d        = length(point - f);
            if (d < minDist1) {
                minDist2    = minDist1;
                minDist1    = d;
                nearestPoint = point;
                cellHash     = fract(sin(dot(i + neighbor, vec2<f32>(127.1, 311.7))) * 43758.5453);
            } else if (d < minDist2) {
                minDist2 = d;
            }
        }
    }
    // edge distance = distance difference between nearest and second nearest
    return vec3<f32>(minDist1, minDist2 - minDist1, cellHash);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv    = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time  = u.config.x;

    // Audio
    let bass   = extraBuffer[0];
    let mid    = extraBuffer[1];
    let treble = extraBuffer[2];

    // Params
    let cellScale  = mix(4.0, 25.0, u.zoom_params.x) * (1.0 + bass * 0.5);
    let refraction = mix(0.0, 0.06,  u.zoom_params.y);
    let chromatic  = mix(0.0, 0.012, u.zoom_params.z);
    let edgeGlow   = mix(0.0, 1.0,   u.zoom_params.w);

    // Mouse proximity increases shatter
    let mouse      = u.zoom_config.yz;
    let mouseDist  = length(uv - mouse);
    let mouseStr   = smoothstep(0.5, 0.0, mouseDist);

    let vor = voronoi(uv * cellScale);
    let cell     = vor.z;        // unique hash per cell
    let edgeDist = vor.y;        // closeness to cell boundary

    // Per-cell refraction direction (random unit vector per cell)
    let refVec = hash2f(vec2<f32>(cell * 113.0, cell * 47.0));
    let refStr = refraction * (1.0 + mouseStr * 2.0) * (1.0 + bass * 1.5);

    let baseUV = uv + refVec * refStr;

    // Chromatic aberration: sample R/G/B at slightly offset UVs
    let caDir = normalize(refVec + vec2<f32>(0.0001));
    let rUV = clamp(baseUV + caDir * chromatic,        vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(baseUV,                             vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(baseUV - caDir * chromatic,        vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let a = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).a;

    var col = vec3<f32>(r, g, b);

    // Edge crack lines: bright and slightly tinted
    let edgeMask  = smoothstep(0.04, 0.0, edgeDist) * edgeGlow;
    let crackTint = vec3<f32>(0.9, 0.95, 1.0) * (1.0 + treble);
    let glintPulse = 0.4 + 0.6 * sin(cell * 314.1 + time * 3.0 + bass * 5.0);
    col = mix(col, crackTint * glintPulse, edgeMask);

    // Slight iridescent tint on facet interior based on cell hash + time
    let iriAngle = cell * 6.28318 + time * 0.3;
    let iri      = vec3<f32>(
        0.5 + 0.5 * cos(iriAngle),
        0.5 + 0.5 * cos(iriAngle + 2.094),
        0.5 + 0.5 * cos(iriAngle + 4.189)
    );
    col = mix(col, col * iri * 1.2, 0.12 * (1.0 + mid));

    // Semantic alpha
    let alpha = clamp(a + edgeMask * 0.5, 0.0, 1.0);

    let outColor = vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(1.5)), alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(edgeDist, vor.x, 0.0, 1.0));
    textureStore(dataTextureA, coord, outColor);
    textureStore(dataTextureB, coord, vec4<f32>(cell, edgeDist, bass, mid));
}
