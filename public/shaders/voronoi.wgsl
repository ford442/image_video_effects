// ═══════════════════════════════════════════════════════════════════
//  Voronoi Tessellation
//  Category: image
//  Features: cellular, mouse-seeded, ripple-seeded, ridges, audio-reactive
//  Complexity: Medium
//  Phase B / Algorithmist
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=CellDensity, y=Jitter, z=RidgeStrength, w=PaletteShift
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const PHI: f32 = 1.61803398874989484820;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}

// Worley/Voronoi returning F1, F2, and cell-id (cellID stable across frames)
struct Voro { F1: f32, F2: f32, cellId: vec2<f32>, };
fn worley(p: vec2<f32>, t: f32, jitter: f32) -> Voro {
    let ip = floor(p);
    let fp = fract(p);
    var F1 = 1e9; var F2 = 1e9;
    var bestCell = vec2<f32>(0.0);
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let n = vec2<f32>(f32(i), f32(j));
            let cellId = ip + n;
            // Slow phase drift per-cell so seeds breathe
            let h = hash22(cellId);
            let pt = n + 0.5 + (h - 0.5) * jitter
                     + 0.15 * jitter * vec2<f32>(sin(t * (h.x + 0.5) * PHI),
                                                  cos(t * (h.y + 0.5) * PHI));
            let d = length(pt - fp);
            if (d < F1) { F2 = F1; F1 = d; bestCell = cellId; }
            else if (d < F2) { F2 = d; }
        }
    }
    return Voro(F1, F2, bestCell);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(gid.xy);

    let uv = vec2<f32>(gid.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let cellDensity   = mix(8.0, 80.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let jitter        = clamp(u.zoom_params.y * (1.0 + bass * 0.5), 0.0, 1.0);
    let ridgeStrength = clamp(u.zoom_params.z, 0.0, 1.0);
    let paletteShift  = u.zoom_params.w;

    // Mouse + ripple seed disturbance (warps lookup space — deformable cells)
    var p = uv * cellDensity;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let dMouse = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let mouseInfl = exp(-dMouse * dMouse * 6.0) * (0.5 + mouseDown * 1.0);
    p += (mouse - uv) * mouseInfl * 4.0;

    // Ripple-stirred seeds — first 6 active ripples (cap loop for cost)
    for (var r = 0; r < 6; r++) {
        let rip = u.ripples[r];
        if (rip.z > 0.0) {
            let age = time - rip.z;
            if (age > 0.0 && age < 4.0) {
                let dr = length((uv - rip.xy) * vec2<f32>(aspect, 1.0));
                let pulse = exp(-dr * dr * 8.0) * (1.0 - age * 0.25);
                let perp = vec2<f32>(-(uv.y - rip.y), (uv.x - rip.x));
                p += perp * pulse * cellDensity * 0.4;
            }
        }
    }

    let v = worley(p, time, jitter);
    let ridge = 1.0 - smoothstep(0.0, 0.18, v.F2 - v.F1);   // bright nodal lines
    let cellMask = smoothstep(0.55, 0.05, v.F1);            // darker cell interior

    // Sample image at the cell's anchor (gives flat-shaded cell color, painting feel)
    let anchorUV = (v.cellId + 0.5) / cellDensity;
    let cellSample = textureSampleLevel(readTexture, u_sampler, fract(anchorUV), 0.0).rgb;

    // Plasma palette colored by cellId hash, blended with sampled cell color
    let cellHash = hash21(v.cellId);
    let palIdx = u32(clamp((cellHash + paletteShift + time * 0.03) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[palIdx % 256u].rgb;

    var color = mix(cellSample, palette, 0.35);
    color = color * mix(0.7, 1.15, cellMask);
    color = color + ridge * ridgeStrength * mix(palette, vec3<f32>(1.0), 0.4) * 0.6;

    // Anti-aliased boundary (approx by F2-F1 derivative scale)
    let edgeAA = smoothstep(0.0, 0.04, v.F2 - v.F1);
    color = color * (0.5 + 0.5 * edgeAA);

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.5 + ridge * ridgeStrength * 0.4 + mouseInfl * 0.2 + 0.1, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(v.F1, ridge, cellHash, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
