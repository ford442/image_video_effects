// ═══════════════════════════════════════════════════════════════════════════════
//  Velocity Field Paint — Vorticity Confinement
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal
//  Complexity: High
//  Scientific: Vorticity ω = ∂v_y/∂x − ∂v_x/∂y computed from 4-neighbour
//              finite-difference velocity samples (advected from dataTextureC),
//              vorticity confinement force F = ε·(η̂ × ω̂) restores turbulent
//              detail dissipated by numerical diffusion,
//              enstrophy (ω²) colour coding: blue=irrotational, red=rotating,
//              audio bass drives brush force, treble drives confinement epsilon
//  Upgraded: Phase B
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0)  var u_sampler: sampler;
@group(0) @binding(1)  var readTexture: texture_2d<f32>;
@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3)  var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,  // x=Dissipation, y=BrushSize, z=Force, w=VortConfinement
    ripples:     array<vec4<f32>, 50>,
}

// Read velocity from dataTextureC at pixel offset
fn velAt(px: vec2<i32>, res: vec2<f32>) -> vec2<f32> {
    let clamped = clamp(px, vec2<i32>(0), vec2<i32>(i32(res.x)-1, i32(res.y)-1));
    return textureLoad(dataTextureC, clamped, 0).xy;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord      = vec2<i32>(global_id.xy);
    let uv         = vec2<f32>(global_id.xy) / resolution;
    let aspect     = resolution.x / resolution.y;
    let mousePos   = u.zoom_config.yz;
    let bass       = clamp(plasmaBuffer[0].x, 0.0, 8.0);
    let treble     = clamp(plasmaBuffer[0].z, 0.0, 4.0);

    let dissipation = clamp(0.90 + u.zoom_params.x * 0.09, 0.0, 1.0);
    let brushSize   = 0.04 + u.zoom_params.y * 0.18;
    let force       = clamp(u.zoom_params.z * 0.6 * (1.0 + bass * 0.5), 0.0, 5.0);
    let epsilon     = mix(0.0, 0.4, u.zoom_params.w) * (1.0 + treble * 0.3); // VCF strength

    // ─── Advect: read velocity from previous frame ───
    let prevData = textureLoad(dataTextureC, coord, 0);
    var vel = prevData.xy;

    // Mouse brush adds velocity
    let dVec  = uv - mousePos;
    let dist  = length(vec2<f32>(dVec.x * aspect, dVec.y));
    let brush = smoothstep(brushSize, 0.0, dist);
    let dir   = select(normalize(dVec + vec2<f32>(0.0001)), vec2<f32>(0.0), dist < 0.0001);
    vel += dir * force * brush;

    // ─── Vorticity from 4-neighbour stencil ───
    // ω = (v_y(x+1) − v_y(x−1))/(2h) − (v_x(y+1) − v_x(y−1))/(2h)
    let vE  = velAt(coord + vec2<i32>( 1, 0), resolution);
    let vW  = velAt(coord + vec2<i32>(-1, 0), resolution);
    let vN  = velAt(coord + vec2<i32>( 0, 1), resolution);
    let vS  = velAt(coord + vec2<i32>( 0,-1), resolution);
    let omega = (vE.y - vW.y - vN.x + vS.x) * 0.5;   // curl (scalar in 2D)

    // ─── Vorticity Confinement force ───
    // Gradient of |ω| to find vortex centre direction
    let omE = velAt(coord + vec2<i32>( 1, 0), resolution).x - velAt(coord + vec2<i32>(-1, 0), resolution).x;
    let omN = velAt(coord + vec2<i32>( 0, 1), resolution).y - velAt(coord + vec2<i32>( 0,-1), resolution).y;
    let gradOm = vec2<f32>(omE, omN);
    let gradLen = length(gradOm);
    let eta = select(gradOm / gradLen, vec2<f32>(0.0), gradLen < 0.0001);   // η̂ (normalised gradient)
    // F_vc = ε · (η̂ × ω̂)  →  in 2D: (−ω·η_y, ω·η_x)
    let vcForce = epsilon * vec2<f32>(-omega * eta.y, omega * eta.x);
    vel += vcForce;

    // Dissipate
    vel *= dissipation;

    // Advect the image along velocity
    let offsetUV  = clamp(uv - vel * 0.05, vec2<f32>(0.0), vec2<f32>(1.0));
    let lod       = clamp(length(vel) * 8.0, 0.0, 3.0);
    let sampled   = textureSampleLevel(readTexture, u_sampler, offsetUV, lod);

    // ─── Colour overlay: enstrophy (ω²) tinting ───
    let enstrophy = clamp(omega * omega * 6.0, 0.0, 1.0);
    // Positive vorticity (CCW) → cyan, negative (CW) → magenta
    let vortCol = select(
        vec3<f32>(1.0, 0.1, 0.8),   // CW magenta
        vec3<f32>(0.1, 0.8, 1.0),   // CCW cyan
        omega > 0.0
    );
    let color = mix(sampled.rgb, vortCol, enstrophy * 0.35);

    let dep = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(vel, omega, enstrophy));
    textureStore(writeDepthTexture, coord, vec4<f32>(dep, 0.0, 0.0, 0.0));
}
