// ═══════════════════════════════════════════════════════════════════
//  Navier-Stokes Dye Injection
//  Category: simulation
//  Features: dye-advection, vorticity-confinement, audio-reactive, mouse-source
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
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // velocity
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // dye
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=DyeStrength, y=Vorticity, z=Diffusion, w=PaletteShift
  ripples: array<vec4<f32>, 50>,
};

const DT:  f32 = 0.016;
const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

@compute @workgroup_size(16, 16, 1)
fn advect_velocity(@builtin(global_invocation_id) gid: vec3<u32>) {
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let vel = textureLoad(dataTextureC, coord, 0).rg;
    let pos = vec2<f32>(f32(coord.x), f32(coord.y));
    let sourcePos = pos - vel * DT;
    let dim = textureDimensions(dataTextureC);
    let res = textureSampleLevel(dataTextureC, u_sampler, sourcePos / vec2<f32>(f32(dim.x), f32(dim.y)), 0.0).rg;
    textureStore(dataTextureA, coord, vec4<f32>(res, 0.0, 0.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let dim = textureDimensions(dataTextureA);
    let dimF = vec2<f32>(f32(dim.x), f32(dim.y));
    let uv = vec2<f32>(gid.xy) / dimF;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouseDown = u.zoom_config.w;

    let dyeStrength    = u.zoom_params.x * 2.0 + 0.3;
    let vorticityScale = u.zoom_params.y * 5.0 + 0.5;
    let diffusion      = u.zoom_params.z * 0.4 + 0.1;
    let paletteShift   = u.zoom_params.w;

    let src = textureLoad(readTexture, coord, 0);

    // Add energy from ripples (cap to first 8 for cost)
    var added_energy = vec2<f32>(0.0);
    for (var i = 0; i < 8; i++) {
        let rip = u.ripples[i];
        let isActive = step(1e-4, rip.z);
        let age = max(time - rip.z, 0.0);
        let alive = step(age, 2.0);
        let toR = uv - rip.xy;
        let dr = length(toR);
        let force = exp(-dr * dr * 800.0) * (1.0 - age * 0.5) * isActive * alive;
        let dir = toR / max(dr, 1e-4);
        added_energy += dir * 20.0 * force;
    }

    // Mouse as continuous inflow source — Gaussian, click amplifies
    let mouse = u.zoom_config.yz;
    let toMouse = uv - mouse;
    let dM2 = dot(toMouse, toMouse);
    let mouseSrc = exp(-dM2 * 900.0) * (8.0 + mouseDown * 12.0) * (1.0 + bass * 0.4 + mids * 0.2);
    added_energy += (toMouse / max(length(toMouse), 1e-4)) * mouseSrc;

    var vel = textureLoad(dataTextureC, coord, 0).rg + added_energy * dyeStrength;

    // Vorticity confinement — sample neighbour curls, drive velocity along ∇|ω|
    let velL = textureLoad(dataTextureC, coord + vec2<i32>(-1, 0), 0).rg;
    let velR = textureLoad(dataTextureC, coord + vec2<i32>( 1, 0), 0).rg;
    let velT = textureLoad(dataTextureC, coord + vec2<i32>( 0,-1), 0).rg;
    let velB = textureLoad(dataTextureC, coord + vec2<i32>( 0, 1), 0).rg;
    let curl = (velR.y - velL.y) - (velB.x - velT.x);
    let omegaL = abs((textureLoad(dataTextureC, coord + vec2<i32>(-2, 0), 0).rg.y) - velL.y);
    let omegaR = abs((textureLoad(dataTextureC, coord + vec2<i32>( 2, 0), 0).rg.y) - velR.y);
    let omegaT = abs((velT.x) - (textureLoad(dataTextureC, coord + vec2<i32>( 0,-2), 0).rg.x));
    let omegaB = abs((velB.x) - (textureLoad(dataTextureC, coord + vec2<i32>( 0, 2), 0).rg.x));
    let gradOmega = vec2<f32>(omegaR - omegaL, omegaB - omegaT);
    let nGrad = gradOmega / max(length(gradOmega), 1e-4);
    let confine = vec2<f32>(nGrad.y, -nGrad.x) * curl * vorticityScale * 0.04;
    vel = vel + confine;
    vel = vel * (1.0 - diffusion * 0.02);
    textureStore(dataTextureA, coord, vec4<f32>(vel, curl, 1.0));

    // Dye coloring: source image tinted by curl phase via plasma palette
    let palIdx = u32(clamp((curl * 0.1 + 0.5 + paletteShift + time * 0.05 + treble * 0.1) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[palIdx % 256u].rgb;
    let saturation = clamp(length(vel) * 0.05, 0.0, 1.0);
    let dyed = mix(src.rgb, src.rgb * (0.6 + palette * 0.8), saturation);

    let cur = textureLoad(dataTextureC, coord, 0);
    let blended = mix(cur.rgb, dyed, 0.15 + bass * 0.1);
    textureStore(dataTextureB, coord, vec4<f32>(blended, 1.0));

    // Alpha: vorticity magnitude + dye saturation drives compositing weight
    let lumaOut = dot(blended, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.4 + lumaOut * 0.3 + abs(curl) * 0.4 + saturation * 0.3, 0.0, 1.0);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(blended, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(blended, alpha));
}
