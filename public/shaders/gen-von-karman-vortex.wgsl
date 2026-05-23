// ═══════════════════════════════════════════════════════════════════
//  Von Kármán Vortex Street
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Description: Analytic vortex-street flow visualization using N
//    point-vortex pairs of alternating sign. The streamfunction
//    ψ = U·y + Σ ±(Γ/2π)·ln(r_i) produces isocontours that trace
//    the classic alternating wake pattern shed behind an obstacle.
//    Mouse positions the obstacle; bass drives the shedding speed.
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=flow_speed, y=vortex_separation, z=vortex_spacing, w=hue

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
  config:      vec4<f32>,  // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,  // x=speed, y=separation, z=spacing, w=hue
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32   = 6.28318530718;
const N_VTX: i32 = 10;  // vortex pairs per row
const CORE_R: f32 = 0.04; // regularisation core radius

// Compute streamfunction for N vortex pairs on a periodic domain
fn compute_psi(pos: vec2<f32>, time: f32, U: f32,
               h: f32, spacing: f32, obstX: f32, obstY: f32) -> f32 {
    var psi = U * pos.y;  // free-stream contribution
    let domainW = f32(N_VTX) * spacing;
    let phase   = fract(U * time / domainW);  // periodic advection

    for (var i = 0; i < N_VTX; i = i + 1) {
        let fi  = f32(i);
        // Periodic x positions for top (+Γ) and bottom (−Γ) rows
        let xT  = obstX + (fi / f32(N_VTX) - phase) * domainW - domainW * 0.5;
        let xB  = obstX + ((fi + 0.5) / f32(N_VTX) - phase) * domainW - domainW * 0.5;
        let yT  = obstY + h;
        let yB  = obstY - h;

        let rT  = max(length(pos - vec2<f32>(xT, yT)), CORE_R);
        let rB  = max(length(pos - vec2<f32>(xB, yB)), CORE_R);
        psi    += log(rT) / TAU;   // Γ = +1
        psi    -= log(rB) / TAU;   // Γ = −1
    }
    return psi;
}

// Velocity field via finite-difference of ψ: u=∂ψ/∂y, v=−∂ψ/∂x
fn compute_vel(pos: vec2<f32>, time: f32, U: f32,
               h: f32, spacing: f32, obstX: f32, obstY: f32) -> vec2<f32> {
    let eps = 0.005;
    let px = compute_psi(pos + vec2<f32>(eps, 0.0), time, U, h, spacing, obstX, obstY);
    let mx = compute_psi(pos - vec2<f32>(eps, 0.0), time, U, h, spacing, obstX, obstY);
    let py = compute_psi(pos + vec2<f32>(0.0, eps), time, U, h, spacing, obstX, obstY);
    let my = compute_psi(pos - vec2<f32>(0.0, eps), time, U, h, spacing, obstX, obstY);
    let inv2e = 1.0 / (2.0 * eps);
    return vec2<f32>((py - my) * inv2e, -(px - mx) * inv2e);
}

// Cyclic HSV-like palette for streamlines
fn streamline_color(t: f32, hueShift: f32, speed: f32) -> vec3<f32> {
    let h = fract(t + hueShift);
    let a = vec3<f32>(0.55, 0.55, 0.55);
    let b = vec3<f32>(0.45, 0.45, 0.45);
    let c = vec3<f32>(1.00, 1.00, 1.00);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    let base = clamp(a + b * cos(TAU * (c * h + d)), vec3<f32>(0.0), vec3<f32>(1.0));
    // Bright high-speed regions
    return base * (0.6 + 0.4 * clamp(speed * 0.4, 0.0, 1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord  = vec2<i32>(gid.xy);
    let uv     = vec2<f32>(gid.xy) / res;
    let time   = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let U        = (0.20 + u.zoom_params.x * 0.50) * (1.0 + bass * 0.6);  // flow speed
    let h        = 0.10 + u.zoom_params.y * 0.25 + mids * 0.05;            // vortex half-separation
    let spacing  = 0.35 + u.zoom_params.z * 0.40;                           // vortex x-spacing
    let hueShift = u.zoom_params.w;

    // Map UV to physical coords: x∈[-2,2], y∈[-1,1] (corrected for aspect)
    let aspect  = res.x / res.y;
    let physPos = (uv - 0.5) * vec2<f32>(2.0 * aspect, 2.0);

    // Mouse = obstacle position
    let mouse   = u.zoom_config.yz;
    let obstX   = (mouse.x - 0.5) * 2.0 * aspect;
    let obstY   = (mouse.y - 0.5) * 2.0;

    // Streamfunction and velocity
    let psi  = compute_psi(physPos, time, U, h, spacing, obstX, obstY);
    let vel  = compute_vel(physPos, time, U, h, spacing, obstX, obstY);
    let spd  = length(vel);

    // Obstacle mask — darken a disk around the obstruction point
    let obstDist = length(physPos - vec2<f32>(obstX, obstY));
    let obstMask = smoothstep(0.06, 0.10, obstDist);

    // Streamline contours: 6 lines per unit of ψ, with treble adding fine lines
    let nLines  = 6.0 + treble * 4.0;
    let psiNorm = fract(psi * nLines * 0.15);
    let lineW   = 0.06 + 0.06 * mids;
    let lineGlow = exp(-abs(psiNorm - 0.5) / lineW);  // bright at ψ = integer

    let col     = streamline_color(psi * 0.05, hueShift, spd) * lineGlow * obstMask;

    // Speed halo around vortex cores
    let speedHalo = clamp(spd * 0.15, 0.0, 1.0);
    let finalRGB  = clamp(col + vec3<f32>(speedHalo * 0.3 * (1.0 + bass)), vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha: strong at streamlines, fades to transparent in calm regions
    let alpha = clamp(lineGlow * 0.75 * obstMask + speedHalo * 0.25 + bass * 0.08, 0.0, 1.0);
    let finalOut = vec4<f32>(finalRGB, alpha);

    textureStore(writeTexture, coord, finalOut);
    textureStore(dataTextureA, coord, finalOut);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
