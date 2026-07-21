// ═══════════════════════════════════════════════════════════════════
//  hyb-hex-voronoi-distort
//  Category: hybrid
//  Features: hex-grid, voronoi, image-distortion, depth-passthrough, mouse-driven, audio-reactive, upgraded-rgba
//  Chunks: nearestHexCenter + voronoi2D
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

// ── Chunk: hash22 (from voronoi-glass.wgsl / chunk-library.md) ──
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ── Chunk: voronoi2D (from interactive-voronoi-lens.wgsl) ──
struct VoronoiResult {
    dist: f32,
    point: vec2<f32>,
    cell: vec2<f32>,
};

fn voronoi2D(st: vec2<f32>, time: f32, chaos: f32) -> VoronoiResult {
    let i_st = floor(st);
    let f_st = fract(st);
    var result = VoronoiResult(1.0, vec2<f32>(0.0), vec2<f32>(0.0));
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            var point = hash22(i_st + neighbor);
            point = 0.5 + 0.5 * sin(time * chaos + 6.2831 * point);
            let d = length(neighbor + point - f_st);
            if (d < result.dist) {
                result.dist = d;
                result.point = point;
                result.cell = i_st + neighbor;
            }
        }
    }
    return result;
}

// ── Chunk: nearestHexCenter (from hex-mosaic.wgsl / quantum-prism.wgsl) ──
fn nearestHexCenter(uv: vec2<f32>, scale: f32) -> vec2<f32> {
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let uvScaled = uv * scale;
    let uvA = uvScaled / r;
    let idA = floor(uvA + 0.5);
    let uvB = (uvScaled - h) / r;
    let idB = floor(uvB + 0.5);
    let centerA = idA * r;
    let centerB = idB * r + h;
    let distA = distance(uvScaled, centerA);
    let distB = distance(uvScaled, centerB);
    return select(centerB, centerA, distA < distB);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(gid.xy);
    let dimsI = vec2<i32>(dims);

    if (any(coord >= dimsI)) {
        return;
    }

    let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Normalize zoom_params
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Mouse pulls cells toward the cursor, bass inflates the distortion
    let mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z) / vec2<f32>(dims);
    let mouseFalloff = 1.0 - smoothstep(0.0, 0.4, length(uv - mousePos));

    let hexScale = mix(6.0, 48.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let voronoiDensity = mix(3.0, 28.0, clamp(u.zoom_params.y, 0.0, 1.0)) * (1.0 + mids * 0.3);
    let distortAmount = mix(0.0, 0.12, clamp(u.zoom_params.z, 0.0, 1.0))
                        * (1.0 + bass * 0.5 + mouseFalloff * 0.8);
    let blend = mix(0.0, 1.0, clamp(u.zoom_params.w, 0.0, 1.0));

    // Hex nearest center in normalized UV space
    let hexCenter = nearestHexCenter(uv, hexScale) / hexScale;

    // Voronoi pattern drives the distortion phase
    let voro = voronoi2D(uv * voronoiDensity, time, 0.6);
    let phase = sin(time * 0.8 + voro.dist * 6.28318) * 0.5 + 0.5;

    // Distort sampling coordinate toward hex center, modulated by Voronoi distance
    let distortedUV = mix(uv, hexCenter, distortAmount * phase);
    let clampedUV = clamp(distortedUV, vec2<f32>(0.0), vec2<f32>(1.0));
    let distorted = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0);

    // Edge tint from Voronoi cells; bass ignites the cell walls
    let edge = smoothstep(0.02, 0.22, voro.dist);
    let tint = mix(vec3<f32>(1.0, 0.95, 0.85), vec3<f32>(1.0), edge);
    let wall = (1.0 - edge) * bass;
    let glow = vec3<f32>(0.35, 0.75, 1.0) * wall * 0.8;

    let effectRGB = distorted.rgb * tint + glow;
    let outRGB = mix(src.rgb, effectRGB, blend);

    // Alpha: source alpha carried, lifted where cell walls are burning
    let alpha = clamp(src.a * (0.85 + wall * 0.6) + wall * 0.2, 0.0, 1.0);
    let outColor = vec4<f32>(outRGB, alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
