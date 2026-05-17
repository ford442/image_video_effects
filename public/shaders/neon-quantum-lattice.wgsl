// ═══════════════════════════════════════════════════════════════════
//  Neon Quantum Lattice
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-17
// ═══════════════════════════════════════════════════════════════════

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
    ripples: array<vec4<f32>, 50>,
};

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let t = u.config.x;
    let mouse = u.zoom_config.yz;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Quantum lattice grid — bass expands grid frequency
    let gridFreq = 12.0 * (1.0 + bass * 0.4);
    let grid = fract(uv * gridFreq + sin(t * 0.4) * 0.3);
    let lattice = smoothstep(0.45, 0.55, abs(grid.x - 0.5)) *
                  smoothstep(0.45, 0.55, abs(grid.y - 0.5));

    // Bloom layers — mids drive shimmer
    let bloom1 = sin(uv.x * 7.0 + t) * cos(uv.y * 5.5 + t * 0.9);
    let bloom2 = sin(uv.x * 11.3 - t * 0.6) * cos(uv.y * 9.8 + t * 1.2);
    let bloom = (bloom1 + bloom2 * 0.7) * 0.5 + 0.5;
    let shimmer = bloom * (1.0 + mids * 0.35);

    let base = mix(vec3(0.1, 0.3, 0.9), vec3(0.9, 0.2, 0.6), lattice);
    var rgb = base * shimmer;

    // Mouse attraction
    let attract = 1.0 - smoothstep(0.0, 0.4, length(uv - mouse));
    rgb += vec3(0.4, 0.9, 1.0) * attract * 0.4;

    // Depth rim lighting
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    rgb += vec3(0.6, 0.8, 1.0) * (1.0 - depth) * 0.25;

    // Treble sparkle
    rgb += vec3(1.0, 0.9, 0.7) * treble * lattice * 0.3;

    rgb = clamp(rgb, vec3<f32>(0.0), vec3<f32>(1.0));

    // Meaningful alpha: lattice edge strength + mouse proximity + bass pulse
    let edgeStrength = lattice * (0.6 + bass * 0.3);
    let alpha = clamp(edgeStrength + attract * 0.25 + 0.15, 0.0, 1.0);

    let finalColor = vec4<f32>(rgb, alpha);

    textureStore(writeTexture, gid.xy, finalColor);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, gid.xy, finalColor);
}
